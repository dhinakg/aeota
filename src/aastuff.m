#import <AppleArchive/AppleArchive.h>
#import <Foundation/Foundation.h>

#import "aea.h"
#import "args.h"
#import "extract.h"
#import "extract_standalone.h"
#import "network.h"
#import "utils.h"

int main(int argc, char** argv) {
    @autoreleasepool {
        int ret = 0;
        ExtractionConfiguration* config = parseArgs(argc, argv, &ret);
        if (!config) {
            return ret;
        }

        if (validateArgs(config)) {
            return 1;
        }

        AAByteStream stream = NULL;
        if (config.remote) {
            stream = remote_archive_open(config.archivePath);
            if (!stream) {
                ERRLOG(@"Failed to open remote archive file stream");
                return 1;
            }

        } else {
            stream = AAFileStreamOpenWithPath(config.archivePath.UTF8String, O_RDONLY, 0644);
            if (!stream) {
                ERRLOG(@"Failed to open archive file stream");
                return 1;
            }
        }

        AAByteStream decryptionStream = NULL;
        AEAContext decryptionContext = NULL;
        if (config.encrypted) {
            decryptionContext = AEAContextCreateWithEncryptedStream(stream);
            if (!decryptionContext) {
                ERRLOG(@"Failed to create encrypted stream context");
                AAByteStreamClose(stream);
                return 1;
            }

            if (!config.key) {
#if HAS_HPKE
                if (fetchKey(decryptionContext, config)) {
                    AEAContextDestroy(decryptionContext);
                    AAByteStreamClose(stream);
                    return 1;
                }
#else
                assert(0 && "HPKE not supported, key should be present at this stage");
#endif
            }

            int ret = AEAContextSetFieldBlob(decryptionContext, AEA_CONTEXT_FIELD_SYMMETRIC_KEY, 0, config.key.bytes, config.key.length);
            if (ret != 0) {
                ERRLOG(@"Failed to set key");
                AEAContextDestroy(decryptionContext);
                AAByteStreamClose(stream);
                return 1;
            }

            decryptionStream = AEADecryptionInputStreamOpen(stream, decryptionContext, 0, 0);
            if (!decryptionStream) {
                ERRLOG(@"Failed to open decryption stream (invalid key?)");
                AEAContextDestroy(decryptionContext);
                AAByteStreamClose(stream);
                return 1;
            }
        }

        if (config.decryptOnly) {
            AAByteStream outputStream = AAFileStreamOpenWithPath(config.outputPath.UTF8String, O_WRONLY | O_CREAT | O_TRUNC, 0644);
            if (!outputStream) {
                ERRLOG(@"Failed to open output file stream");
                AEAContextDestroy(decryptionContext);
                AAByteStreamClose(decryptionStream);
                AAByteStreamClose(stream);
                return 1;
            }

            off_t processed = AAByteStreamProcess(decryptionStream, outputStream);

            if (processed < 0) {
                ERRLOG(@"Failed to process stream");
                AEAContextDestroy(decryptionContext);
                AAByteStreamClose(decryptionStream);
                AAByteStreamClose(stream);
                AAByteStreamClose(outputStream);
                return 1;
            } else {
                DBGLOG(@"Processed %lld bytes", processed);
            }

            AAByteStreamClose(outputStream);
        } else {
#if AASTUFF_STANDALONE
            if (extractAssetStandalone(config.encrypted ? decryptionStream : stream, config)) {
#else
            if (extractAsset(config.encrypted ? decryptionStream : stream, config)) {
#endif
                ERRLOG(@"Extracting asset failed");
                AEAContextDestroy(decryptionContext);
                AAByteStreamClose(decryptionStream);
                AAByteStreamClose(stream);
                return 1;
            }
        }

        AEAContextDestroy(decryptionContext);
        AAByteStreamClose(decryptionStream);
        AAByteStreamClose(stream);

        DBGLOG(@"Done!");

        return 0;
    }
}
