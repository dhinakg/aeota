#import <AppleArchive/AppleArchive.h>
#import <Foundation/Foundation.h>

#import "extract.h"
#import "extract_standalone.h"
#import "utils.h"

#define APPLE_ARCHIVE_MAGIC @"AA01"
#define APPLE_ENCRYPTED_ARCHIVE_MAGIC @"AEA1"

int main(int argc, char** argv) {
    @autoreleasepool {
        NSError* error = nil;

        if (argc < 3) {
            ERRLOG(@"Usage: %s <archive> <output directory> [key in base64]", argv[0]);
            ERRLOG(@"Key is required for encrypted archives");
            return argc == 1 ? 0 : 1;
        }

        NSString* archivePath = [NSString stringWithUTF8String:argv[1]];
        NSString* outputDirectory = [NSString stringWithUTF8String:argv[2]];
        NSString* keyBase64 = nil;
        if (argc > 3) {
            keyBase64 = [NSString stringWithUTF8String:argv[3]];
        }

        if (!archivePath || !outputDirectory) {
            ERRLOG(@"Failed to parse arguments");
            return 1;
        }

        NSFileManager* fileManager = [NSFileManager defaultManager];

        if (![fileManager fileExistsAtPath:archivePath]) {
            ERRLOG(@"Archive does not exist");
            return 1;
        }

        bool isDirectory = false;
        if (![fileManager fileExistsAtPath:outputDirectory isDirectory:&isDirectory]) {
            if (![fileManager createDirectoryAtPath:outputDirectory withIntermediateDirectories:NO attributes:nil error:&error]) {
                ERRLOG(@"Failed to create directory: %@", error);
                return 1;
            }
        } else {
            if (!isDirectory) {
                ERRLOG(@"Output path is not a directory");
                return 1;
            }
        }

        NSFileHandle* handle = [NSFileHandle fileHandleForReadingAtPath:archivePath];
        if (!handle) {
            ERRLOG(@"Failed to open archive file");
            return 1;
        }

        NSData* magic = [handle readDataUpToLength:4 error:&error];
        // If this fails, can't do anything about it, so just ignore the error
        [handle closeAndReturnError:nil];

        if (!magic || magic.length != 4) {
            ERRLOG(@"Failed to read magic: %@", error);
            return 1;
        }

        bool encrypted = false;
        NSString* magicStr = [[NSString alloc] initWithData:magic encoding:NSUTF8StringEncoding];
        if ([magicStr isEqualToString:APPLE_ENCRYPTED_ARCHIVE_MAGIC]) {
            encrypted = true;
        } else if ([magicStr isEqualToString:APPLE_ARCHIVE_MAGIC]) {
            encrypted = false;
        } else {
            ERRLOG(@"Unknown magic: %@", magicStr);
            return 1;
        }

        if (encrypted && !keyBase64) {
            ERRLOG(@"Encrypted archive requires key");
            return 1;
        }

        AAByteStream stream = AAFileStreamOpenWithPath(archivePath.UTF8String, O_RDONLY, 0644);
        if (!stream) {
            ERRLOG(@"Failed to open archive file stream");
            return 1;
        }

        AAByteStream decryptionStream = NULL;
        AEAContext decryptionContext = NULL;
        if (encrypted) {
            NSData* key = [[NSData alloc] initWithBase64EncodedString:keyBase64 options:0];
            if (!key) {
                ERRLOG(@"Failed to parse key");
                AAByteStreamClose(stream);
                return 1;
            }

            decryptionContext = AEAContextCreateWithEncryptedStream(stream);
            if (!decryptionContext) {
                ERRLOG(@"Failed to create encrypted stream context");
                AAByteStreamClose(stream);
                return 1;
            }

            int ret = AEAContextSetFieldBlob(decryptionContext, AEA_CONTEXT_FIELD_SYMMETRIC_KEY, 0, key.bytes, key.length);
            if (ret != 0) {
                ERRLOG(@"Failed to set key");
                AEAContextDestroy(decryptionContext);
                AAByteStreamClose(stream);
                return 1;
            }

            decryptionStream = AEADecryptionInputStreamOpen(stream, decryptionContext, 0, 0);
            if (!decryptionStream) {
                ERRLOG(@"Failed to open decryption stream");
                AEAContextDestroy(decryptionContext);
                AAByteStreamClose(stream);
                return 1;
            }
        }

#if AASTUFF_STANDALONE
        if (extractAssetStandalone(encrypted ? decryptionStream : stream, outputDirectory)) {
#else
        if (extractAsset(encrypted ? decryptionStream : stream, outputDirectory)) {
#endif
            ERRLOG(@"Extracting asset failed");
            AEAContextDestroy(decryptionContext);
            AAByteStreamClose(decryptionStream);
            AAByteStreamClose(stream);
            return 1;
        }

        AEAContextDestroy(decryptionContext);
        AAByteStreamClose(decryptionStream);
        AAByteStreamClose(stream);

        DBGLOG(@"Done!");

        return 0;
    }
}
