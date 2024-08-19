#import "extract_standalone.h"

#import <fnmatch.h>

#import "AppleArchivePrivate.h"
#import "args.h"
#import "utils.h"

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

#if DEBUG
static inline NSString* messageToString(AAEntryMessage message) {
    NSDictionary* map = @{
        @(AA_ENTRY_MESSAGE_SEARCH_PRUNE_DIR): @"SEARCH_PRUNE_DIR",
        @(AA_ENTRY_MESSAGE_SEARCH_EXCLUDE): @"SEARCH_EXCLUDE",
        @(AA_ENTRY_MESSAGE_SEARCH_FAIL): @"SEARCH_FAIL",
        @(AA_ENTRY_MESSAGE_EXTRACT_BEGIN): @"EXTRACT_BEGIN",
        @(AA_ENTRY_MESSAGE_EXTRACT_END): @"EXTRACT_END",
        @(AA_ENTRY_MESSAGE_EXTRACT_FAIL): @"EXTRACT_FAIL",
        @(AA_ENTRY_MESSAGE_EXTRACT_ATTRIBUTES): @"EXTRACT_ATTRIBUTES",
        @(AA_ENTRY_MESSAGE_EXTRACT_XAT): @"EXTRACT_XAT",
        @(AA_ENTRY_MESSAGE_EXTRACT_ACL): @"EXTRACT_ACL",
        @(AA_ENTRY_MESSAGE_ENCODE_SCANNING): @"ENCODE_SCANNING",
        @(AA_ENTRY_MESSAGE_ENCODE_WRITING): @"ENCODE_WRITING",
        @(AA_ENTRY_MESSAGE_CONVERT_EXCLUDE): @"CONVERT_EXCLUDE",
        @(AA_ENTRY_MESSAGE_PROCESS_EXCLUDE): @"PROCESS_EXCLUDE",
        @(AA_ENTRY_MESSAGE_DECODE_READING): @"DECODE_READING"
    };

    return map[@(message)] ? map[@(message)] : @"Unknown";
}
#endif

static int aa_callback(void* arg, AAEntryMessage message, const char* path, void* data) {
    ExtractionConfiguration* config = (__bridge ExtractionConfiguration*)arg;

    DBGLOG(@"[%@] Message: %@ (%d), Path: %s", config.function, messageToString(message), message, path);

    if (config.regex) {
        NSUInteger ret = [config.regex numberOfMatchesInString:[NSString stringWithUTF8String:path] options:0
                                                         range:NSMakeRange(0, strlen(path))];
        DBGLOG(@"[%@] Path: %s, Regex: %@, Ret: %@", config.function, path, config.regex, ret != 0 ? @"Match" : @"No match");
        if (ret == 0 && message == AA_ENTRY_MESSAGE_EXTRACT_BEGIN) {
            return 1;
        }
    } else if (config.filter) {
        int ret = fnmatch(config.filter.UTF8String, path, 0);
        DBGLOG(@"[%@] Path: %s, Filter: %@, Ret: %@", config.function, path, config.filter,
               ret == 0 ? @"Match" : (ret == FNM_NOMATCH ? @"No match" : @"Error"));
        if (ret != 0 && message == AA_ENTRY_MESSAGE_EXTRACT_BEGIN) {
            return 1;
        }
    }

    if (config.list) {
        if (message == AA_ENTRY_MESSAGE_EXTRACT_BEGIN) {
            // Do not continue extraction
            LOG(@"%s", path);
            return 1;
        } else if (message == AA_ENTRY_MESSAGE_PROCESS_EXCLUDE) {
            // This occurs before extraction begins, so we want this to continue
            return 0;
        } else {
            // Skip all other steps of extraction
            return 1;
        }
    }

    // Continue
    return 0;
}

int extractAssetStandalone(AAByteStream byteStream, ExtractionConfiguration* config) {
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
            DBGLOG(@"Failed to find LBL key index");
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
            if (config.list && yop == AA_YOP_TYPE_DST_FIXUP) {
                DBGLOG(@"Skipping DST_FIXUP entry as we are listing only");
            } else {
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

                CFTypeRef configCopy = CFBridgingRetain([config copyWithFunction:(yop == AA_YOP_TYPE_DST_FIXUP ? @"VERIFY" : @"EXTRACT")]);

                // TODO: What is the difference between these two?
                // TODO: Magic constant
                AAArchiveStream extractStream =
                    yop == AA_YOP_TYPE_DST_FIXUP
                        ? AAVerifyDirectoryArchiveOutputStreamOpen(config.outputPath.UTF8String, keySet, (void*)configCopy, aa_callback,
                                                                   UINT64_C(1) << 53, 0)
                        : AAExtractArchiveOutputStreamOpen(config.outputPath.UTF8String, (void*)configCopy, aa_callback, 0, 0);
                if (!extractStream) {
                    ERRLOG(@"Failed to open extract stream");
                    CFRelease(configCopy);
                    AAArchiveStreamClose(innerDecodeStream);
                    AAByteStreamClose(decompressStream);
                    AAByteStreamClose(datStream);
                    break;
                }

                if (AAArchiveStreamProcess(innerDecodeStream, extractStream, (void*)CFBridgingRetain([config copyWithFunction:@"PROCESS"]),
                                           aa_callback, 0, 0) < 0) {
                    ERRLOG(@"Failed to process archive stream");
                    AAArchiveStreamClose(extractStream);
                    CFRelease(configCopy);
                    AAArchiveStreamClose(innerDecodeStream);
                    AAByteStreamClose(decompressStream);
                    AAByteStreamClose(datStream);
                    break;
                }

                AAArchiveStreamClose(extractStream);
                CFRelease(configCopy);
                AAArchiveStreamClose(innerDecodeStream);
                AAByteStreamClose(decompressStream);
                AAByteStreamClose(datStream);
                AAFieldKeySetDestroy(keySet);
            }
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
