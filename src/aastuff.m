#import <AppleArchive/AppleArchive.h>
#import <Foundation/Foundation.h>

#import "args.h"
#import "extract.h"
#import "extract_standalone.h"
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

        AAByteStream stream = AAFileStreamOpenWithPath(config.archivePath.UTF8String, O_RDONLY, 0644);
        if (!stream) {
            ERRLOG(@"Failed to open archive file stream");
            return 1;
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

        AEAContextDestroy(decryptionContext);
        AAByteStreamClose(decryptionStream);
        AAByteStreamClose(stream);

        DBGLOG(@"Done!");

        return 0;
    }
}
