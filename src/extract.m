#import "extract.h"

#import "AppleArchivePrivate.h"
#import "utils.h"

#define ALLOC_SIZE 0x100000uLL

int extractAsset(AAByteStream stream, ExtractionConfiguration* config) {
    AAAssetExtractor extractor = AAAssetExtractorCreate(config.outputDirectory.UTF8String, NULL, NULL);
    if (!extractor) {
        ERRLOG(@"Failed to create asset extractor");
        return 1;
    }

    void* allocated = valloc(ALLOC_SIZE);
    if (!allocated) {
        ERRLOG(@"Failed to allocate memory");
        AAAssetExtractorDestroy(extractor, NULL);
        return 1;
    }

    bool readAnything = false;
    while (1) {
        size_t read = AAByteStreamRead(stream, allocated, ALLOC_SIZE);
        if (read == 0) {
            if (!readAnything) {
                ERRLOG(@"Warning: No data read");
            }
            break;
        }

        readAnything = true;
        DBGLOG(@"Read %zu bytes", read);

        size_t written = AAAssetExtractorWrite(extractor, allocated, read);
        if (written != read) {
            ERRLOG(@"Data write mismatch: expected %zu, got %zu", read, written);

            AAAssetExtractorDestroy(extractor, NULL);
            free(allocated);
            return 1;
        }
    }

    AAAssetExtractorDestroy(extractor, NULL);
    free(allocated);
    return 0;
}
