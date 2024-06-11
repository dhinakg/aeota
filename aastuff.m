#import <AppleArchive/AppleArchive.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <sys/cdefs.h>

#define ALLOC_SIZE 0x100000uLL

__BEGIN_DECLS

// TODO: Figure out how this is different from normal AppleArchive

typedef void* AAAssetExtractor;

AAAssetExtractor AAAssetExtractorCreate(const char* destDir, void** something, int something2);
int AAAssetExtractorWrite(AAAssetExtractor extractor, void* buffer, size_t size);
void AAAssetExtractorDestroy(AAAssetExtractor extractor);

__END_DECLS

int main(int argc, char** argv) {
    @autoreleasepool {
        NSError* error = nil;

        NSLog(@"Hello world!");

        if (argc < 4) {
            NSLog(@"Usage: %s <archive> <output directory> <key in base64>", argv[0]);
            return 1;
        }

        NSString* archive_path = [NSString stringWithUTF8String:argv[1]];
        NSString* out_path = [NSString stringWithUTF8String:argv[2]];
        NSString* key_base64 = [NSString stringWithUTF8String:argv[3]];

        if (!archive_path || !out_path || !key_base64) {
            NSLog(@"Failed to parse arguments");
            return 1;
        }

        if (![[NSFileManager defaultManager] fileExistsAtPath:archive_path]) {
            NSLog(@"Archive does not exist");
            return 1;
        }

        bool is_directory = false;
        if (![[NSFileManager defaultManager] fileExistsAtPath:out_path isDirectory:&is_directory]) {
            if (![[NSFileManager defaultManager] createDirectoryAtPath:out_path withIntermediateDirectories:NO attributes:nil
                                                                 error:&error]) {
                NSLog(@"Failed to create directory: %@", error);
                return 1;
            }
        } else {
            if (!is_directory) {
                NSLog(@"Output path is not a directory");
                return 1;
            }
        }

        NSData* key = [[NSData alloc] initWithBase64EncodedString:key_base64 options:0];
        if (!key) {
            NSLog(@"Failed to parse key");
            return 1;
        }

        // create directory
        AAByteStream stream = AAFileStreamOpenWithPath(archive_path.UTF8String, 0, 420);
        if (!stream) {
            NSLog(@"Failed to open archive file stream");
            return 1;
        }

        AEAContext context = AEAContextCreateWithEncryptedStream(stream);
        if (!context) {
            NSLog(@"Failed to create encrypted stream context");
            AAByteStreamClose(stream);
            return 1;
        }

        int ret = AEAContextSetFieldBlob(context, AEA_CONTEXT_FIELD_SYMMETRIC_KEY, 0, key.bytes, key.length);
        if (ret != 0) {
            NSLog(@"Failed to set key");
            AEAContextDestroy(context);
            AAByteStreamClose(stream);
            return 1;
        }

        AAByteStream decryption_stream = AEADecryptionInputStreamOpen(stream, context, 0, 0);
        if (!decryption_stream) {
            NSLog(@"Failed to open decryption stream");
            AEAContextDestroy(context);
            AAByteStreamClose(stream);
            return 1;
        }

        void* something = NULL;
        AAAssetExtractor extractor = AAAssetExtractorCreate(out_path.UTF8String, &something, 0LL);
        if (!extractor) {
            NSLog(@"Failed to create asset extractor");
            AAByteStreamClose(decryption_stream);
            AEAContextDestroy(context);
            AAByteStreamClose(stream);
            return 1;
        }

        void* allocated = valloc(ALLOC_SIZE);
        if (!allocated) {
            NSLog(@"Failed to allocate memory");
            AAAssetExtractorDestroy(extractor);
            AAByteStreamClose(decryption_stream);
            AEAContextDestroy(context);
            AAByteStreamClose(stream);
            return 1;
        }

        bool read_anything = false;
        while (1) {
            size_t read = AAByteStreamRead(decryption_stream, allocated, ALLOC_SIZE);
            if (read == 0) {
                if (!read_anything) {
                    NSLog(@"Warning: No data read");
                }
                break;
            }

            read_anything = true;
            NSLog(@"Read %zu bytes", read);

            size_t written = AAAssetExtractorWrite(extractor, allocated, read);
            if (written != read) {
                NSLog(@"Data write mismatch: expected %zu, got %zu", read, written);

                AAAssetExtractorDestroy(extractor);
                free(allocated);
                AAByteStreamClose(decryption_stream);
                AEAContextDestroy(context);
                AAByteStreamClose(stream);
                return 1;
            }
        }

        AAAssetExtractorDestroy(extractor);
        free(allocated);
        AAByteStreamClose(decryption_stream);
        AEAContextDestroy(context);
        AAByteStreamClose(stream);

        NSLog(@"Done!");

        return 0;
    }
}
