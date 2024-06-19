#import <AppleArchive/AppleArchive.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <sys/cdefs.h>

#define APPLE_ARCHIVE_MAGIC @"AA01"
#define APPLE_ENCRYPTED_ARCHIVE_MAGIC @"AEA1"

#define ALLOC_SIZE 0x100000uLL

__BEGIN_DECLS

// TODO: Figure out how this is different from normal AppleArchive
typedef void* AAAssetExtractor;

AAAssetExtractor AAAssetExtractorCreate(const char* destDir, void** something, int something2);
// AAAssetExtractorSetParameterCallback
// AAAssetExtractorSetParameterPtr
int AAAssetExtractorWrite(AAAssetExtractor extractor, void* buffer, size_t size);
void AAAssetExtractorDestroy(AAAssetExtractor extractor);

__END_DECLS

int extractAsset(AAByteStream stream, NSString* outputDirectory) {
    void* something = NULL;
    AAAssetExtractor extractor = AAAssetExtractorCreate(outputDirectory.UTF8String, &something, 0LL);
    if (!extractor) {
        NSLog(@"Failed to create asset extractor");
        return 1;
    }

    void* allocated = valloc(ALLOC_SIZE);
    if (!allocated) {
        NSLog(@"Failed to allocate memory");
        AAAssetExtractorDestroy(extractor);
        return 1;
    }

    bool readAnything = false;
    while (1) {
        size_t read = AAByteStreamRead(stream, allocated, ALLOC_SIZE);
        if (read == 0) {
            if (!readAnything) {
                NSLog(@"Warning: No data read");
            }
            break;
        }

        readAnything = true;
        NSLog(@"Read %zu bytes", read);

        size_t written = AAAssetExtractorWrite(extractor, allocated, read);
        if (written != read) {
            NSLog(@"Data write mismatch: expected %zu, got %zu", read, written);

            AAAssetExtractorDestroy(extractor);
            free(allocated);
            return 1;
        }
    }

    AAAssetExtractorDestroy(extractor);
    free(allocated);
    return 0;
}

int main(int argc, char** argv) {
    @autoreleasepool {
        NSError* error = nil;

        if (argc < 3) {
            NSLog(@"Usage: %s <archive> <output directory> [key in base64]", argv[0]);
            NSLog(@"Key is required for encrypted archives");
            return 1;
        }

        NSString* archivePath = [NSString stringWithUTF8String:argv[1]];
        NSString* outputDirectory = [NSString stringWithUTF8String:argv[2]];
        NSString* keyBase64 = nil;
        if (argc > 3) {
            keyBase64 = [NSString stringWithUTF8String:argv[3]];
        }

        if (!archivePath || !outputDirectory) {
            NSLog(@"Failed to parse arguments");
            return 1;
        }

        NSFileManager* fileManager = [NSFileManager defaultManager];

        if (![fileManager fileExistsAtPath:archivePath]) {
            NSLog(@"Archive does not exist");
            return 1;
        }

        bool isDirectory = false;
        if (![fileManager fileExistsAtPath:outputDirectory isDirectory:&isDirectory]) {
            if (![fileManager createDirectoryAtPath:outputDirectory withIntermediateDirectories:NO attributes:nil error:&error]) {
                NSLog(@"Failed to create directory: %@", error);
                return 1;
            }
        } else {
            if (!isDirectory) {
                NSLog(@"Output path is not a directory");
                return 1;
            }
        }

        NSFileHandle* handle = [NSFileHandle fileHandleForReadingAtPath:archivePath];
        if (!handle) {
            NSLog(@"Failed to open archive file");
            return 1;
        }

        NSData* magic = [handle readDataUpToLength:4 error:&error];
        // If this fails, can't do anything about it, so just ignore the error
        [handle closeAndReturnError:nil];

        if (!magic || magic.length != 4) {
            NSLog(@"Failed to read magic: %@", error);
            return 1;
        }

        bool encrypted = false;
        NSString* magicStr = [[NSString alloc] initWithData:magic encoding:NSUTF8StringEncoding];
        if ([magicStr isEqualToString:APPLE_ENCRYPTED_ARCHIVE_MAGIC]) {
            encrypted = true;
        } else if ([magicStr isEqualToString:APPLE_ARCHIVE_MAGIC]) {
            encrypted = false;
        } else {
            NSLog(@"Unknown magic: %@", magicStr);
            return 1;
        }

        if (encrypted && !keyBase64) {
            NSLog(@"Encrypted archive requires key");
            return 1;
        }

        AAByteStream stream = AAFileStreamOpenWithPath(archivePath.UTF8String, O_RDONLY, 0644);
        if (!stream) {
            NSLog(@"Failed to open archive file stream");
            return 1;
        }

        AAByteStream decryptionStream = NULL;
        AEAContext decryptionContext = NULL;
        if (encrypted) {
            NSData* key = [[NSData alloc] initWithBase64EncodedString:keyBase64 options:0];
            if (!key) {
                NSLog(@"Failed to parse key");
                AAByteStreamClose(stream);
                return 1;
            }

            decryptionContext = AEAContextCreateWithEncryptedStream(stream);
            if (!decryptionContext) {
                NSLog(@"Failed to create encrypted stream context");
                AAByteStreamClose(stream);
                return 1;
            }

            int ret = AEAContextSetFieldBlob(decryptionContext, AEA_CONTEXT_FIELD_SYMMETRIC_KEY, 0, key.bytes, key.length);
            if (ret != 0) {
                NSLog(@"Failed to set key");
                AEAContextDestroy(decryptionContext);
                AAByteStreamClose(stream);
                return 1;
            }

            decryptionStream = AEADecryptionInputStreamOpen(stream, decryptionContext, 0, 0);
            if (!decryptionStream) {
                NSLog(@"Failed to open decryption stream");
                AEAContextDestroy(decryptionContext);
                AAByteStreamClose(stream);
                return 1;
            }
        }

        if (extractAsset(encrypted ? decryptionStream : stream, outputDirectory)) {
            NSLog(@"Extracting asset failed");
            AEAContextDestroy(decryptionContext);
            AAByteStreamClose(decryptionStream);
            AAByteStreamClose(stream);
            return 1;
        }

        AEAContextDestroy(decryptionContext);
        AAByteStreamClose(decryptionStream);
        AAByteStreamClose(stream);

        NSLog(@"Done!");

        return 0;
    }
}
