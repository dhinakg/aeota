#import "extract_standalone.h"
#import "AppleArchivePrivate.h"
#import "utils.h"

// TODO: Cleanup
// TODO: Work on filtering

typedef struct nested_archive_data {
    AAArchiveStream stream;
    uint64_t size;
}* nested_archive_data;

AAByteStream nested_archive_open(AAArchiveStream stream, uint64_t size);
int nested_archive_close(void* stream);
ssize_t nested_archive_read(void* stream, void* buf, size_t nbyte);

AAByteStream nested_archive_open(AAArchiveStream stream, uint64_t size) {
    nested_archive_data data = malloc(sizeof(struct nested_archive_data));
    if (!data) {
        return NULL;
    }

    data->stream = stream;
    data->size = size;

    AAByteStream byteStream = AACustomByteStreamOpen();
    if (!byteStream) {
        free(data);
        return NULL;
    }

    AACustomByteStreamSetCloseProc(byteStream, nested_archive_close);
    AACustomByteStreamSetReadProc(byteStream, nested_archive_read);
    AACustomByteStreamSetData(byteStream, data);

    return byteStream;
}

int nested_archive_close(void* stream) {
    nested_archive_data data = stream;

    if (data) {
        free(data);
    }
    return 0;
}

ssize_t nested_archive_read(void* stream, void* buf, size_t nbyte) {
    nested_archive_data data = stream;

    size_t size = MIN(nbyte, data->size);
    if (!size) {
        return 0;
    }
    if (AAArchiveStreamReadBlob(data->stream, AA_FIELD_DAT, buf, size) != 0) {
        return -1;
    }
    data->size -= size;
    return size;
}

int extractAssetStandalone(AAByteStream byteStream, NSString* outputDirectory) {
    AAArchiveStream decodeStream = AADecodeArchiveInputStreamOpen(byteStream, NULL, NULL, 0, 0);
    if (!decodeStream) {
        ERRLOG(@"Failed to open archive decode stream");
        AAByteStreamClose(byteStream);
        return 1;
    }

    while (true) {
        AAHeader header = NULL;
        if (AAArchiveStreamReadHeader(decodeStream, &header) != 1) {
            DBGLOG(@"Failed to read archive header");
            break;
        }

#if DEBUG
        size_t encodedSize = AAHeaderGetEncodedSize(header);
        DBGLOG(@"Found new header, with %d keys, encoded %zu", AAHeaderGetFieldCount(header), encodedSize);
        NSData* encoded = [NSData dataWithBytes:AAHeaderGetEncodedData(header) length:encodedSize];
        DBGLOG(@"Encoded: %@", encoded);
#endif

        int typeIndex = AAHeaderGetKeyIndex(header, AA_FIELD_TYP);
        if (typeIndex == -1) {
            ERRLOG(@"Failed to find type key index");
            continue;
        }

        uint64_t type = -1;
        if (AAHeaderGetFieldUInt(header, typeIndex, &type) != 0) {
            ERRLOG(@"Failed to get type");
            continue;
        }

        if (type != AA_ENTRY_TYPE_METADATA) {
            DBGLOG(@"Skipping non-metadata entry");
            continue;
        }

        int yopIndex = AAHeaderGetKeyIndex(header, AA_FIELD_C("YOP"));
        if (yopIndex == -1) {
            ERRLOG(@"Failed to find YOP key index");
            continue;
        }

        uint64_t yop = -1;
        if (AAHeaderGetFieldUInt(header, yopIndex, &yop) != 0) {
            ERRLOG(@"Failed to get YOP");
            continue;
        }

        // maybe label?
        int lblIndex = AAHeaderGetKeyIndex(header, AA_FIELD_C("LBL"));
        if (lblIndex == -1) {
            ERRLOG(@"Failed to find LBL key index");
            continue;
        }

        char lbl[200];
        size_t lblSize = -1;
        if (AAHeaderGetFieldString(header, lblIndex, sizeof(lbl), lbl, &lblSize) != 0) {
            ERRLOG(@"Failed to get LBL");
            continue;
        }

        if (strncmp(lbl, "main", 4) != 0) {
            ERRLOG(@"Skipping non-main entry");
            continue;
        }

        DBGLOG(@"Processing %c entry", (char)yop);

        if (yop == AA_YOP_TYPE_EXTRACT || yop == AA_YOP_TYPE_DST_FIXUP) {
            // TODO: Maybe extract this into a function
            AAFieldKeySet keySet = AAFieldKeySetCreate();

            int datIndex = AAHeaderGetKeyIndex(header, AA_FIELD_DAT);
            if (datIndex == -1) {
                ERRLOG(@"Failed to find DAT key index");
                continue;
            }

            uint64_t datSize = -1;
            uint64_t datOffset = -1;
            if (AAHeaderGetFieldBlob(header, datIndex, &datSize, &datOffset) != 0) {
                ERRLOG(@"Failed to get DAT");
                continue;
            }

            AAByteStream datStream = nested_archive_open(decodeStream, datSize);
            if (!datStream) {
                ERRLOG(@"Failed to open DAT stream");
                break;
            }

            AAByteStream decompressStream = AADecompressionInputStreamOpen(datStream, 0, 0);
            if (!decompressStream) {
                ERRLOG(@"Failed to open decompress stream");
                AAByteStreamClose(datStream);
                break;
            }

            AAArchiveStream innerDecodeStream = AADecodeArchiveInputStreamOpen(decompressStream, NULL, NULL, 0, 1);
            if (!innerDecodeStream) {
                ERRLOG(@"Failed to open inner decode stream");
                AAByteStreamClose(decompressStream);
                AAByteStreamClose(datStream);
                break;
            }

            // TODO: What is the difference between these two?
            AAArchiveStream extractStream =
                yop == AA_YOP_TYPE_DST_FIXUP
                    ? AAVerifyDirectoryArchiveOutputStreamOpen(outputDirectory.UTF8String, keySet, NULL, NULL, UINT64_C(1) << 53, 0)
                    : AAExtractArchiveOutputStreamOpen(outputDirectory.UTF8String, NULL, NULL, 0, 0);
            if (!extractStream) {
                ERRLOG(@"Failed to open extract stream");
                AAArchiveStreamClose(innerDecodeStream);
                AAByteStreamClose(decompressStream);
                AAByteStreamClose(datStream);
                break;
            }

            if (AAArchiveStreamProcess(innerDecodeStream, extractStream, NULL, NULL, 0, 0) < 0) {
                ERRLOG(@"Failed to process archive stream");
                AAArchiveStreamClose(extractStream);
                AAArchiveStreamClose(innerDecodeStream);
                AAByteStreamClose(decompressStream);
                AAByteStreamClose(datStream);
                break;
            }

            AAArchiveStreamClose(extractStream);
            AAArchiveStreamClose(innerDecodeStream);
            AAByteStreamClose(decompressStream);
            AAByteStreamClose(datStream);
            AAFieldKeySetDestroy(keySet);
        } else {
            ERRLOG(@"Unknown YOP: %llx", yop);
#if DEBUG
            abort();
#endif
            break;
        }

        DBGLOG(@"Block processed");
    }

    AAArchiveStreamClose(decodeStream);

    return 0;
}
