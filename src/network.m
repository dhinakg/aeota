#import "network.h"

#import <AppleArchive/AppleArchive.h>

#import "utils.h"

bool checkAlive(NSString* url, NSError** error) {
    NSURL* URL = [NSURL URLWithString:url];
    if (!URL) {
        return NO;
    }

    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:URL];
    request.HTTPMethod = @"HEAD";

    NSHTTPURLResponse* response = nil;
    makeSynchronousRequest(request, &response, error);

    return response && response.statusCode == 200;
}

// TODO: Add minimum request size and cache any unused data
typedef struct remote_archive_data {
    NSURL* url;
    NSURLSession* session;
    uint64_t position;
}* remote_archive_data;

AAByteStream remote_archive_open(NSString* url) {
    remote_archive_data data = malloc(sizeof(struct remote_archive_data));
    if (!data) {
        return NULL;
    }

    data->url = [NSURL URLWithString:url];
    if (!data->url) {
        free(data);
        return NULL;
    }
    data->session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.defaultSessionConfiguration];
    data->position = 0;

    AAByteStream byteStream = AACustomByteStreamOpen();
    if (!byteStream) {
        free(data);
        return NULL;
    }

    AACustomByteStreamSetCloseProc(byteStream, remote_archive_close);
    AACustomByteStreamSetReadProc(byteStream, remote_archive_read);
    // AACustomByteStreamSetPReadProc(byteStream, remote_archive_pread);
    AACustomByteStreamSetSeekProc(byteStream, remote_archive_seek);
    AACustomByteStreamSetData(byteStream, data);

    return byteStream;
}

int remote_archive_close(void* stream) {
    remote_archive_data data = stream;

    if (data) {
        [data->session invalidateAndCancel];
        free(data);
    }
    return 0;
}

ssize_t remote_archive_read(void* stream, void* buf, size_t nbyte) {
    remote_archive_data data = stream;

    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:data->url];
    [request setValue:[NSString stringWithFormat:@"bytes=%llu-%llu", data->position, data->position + nbyte - 1]
        forHTTPHeaderField:@"Range"];

    DBGLOG(@"Requesting %zu bytes from %llu", nbyte, data->position);

    @autoreleasepool {
        NSHTTPURLResponse* response = nil;
        NSError* error = nil;
        NSData* responseData = makeSynchronousRequestWithSession(data->session, request, &response, &error);
        if (!responseData) {
            ERRLOG(@"Failed to fetch data: %@", error);
            return -1;
        }

        if (response.statusCode != 206) {
            ERRLOG(@"Failed to fetch data: %ld", response.statusCode);
            return -1;
        }

        size_t size = MIN(nbyte, responseData.length);
        memcpy(buf, responseData.bytes, size);
        data->position += size;

        DBGLOG(@"Read %zu bytes (%@)", size, responseData);

        return size;
    }
}

off_t remote_archive_seek(void* stream, off_t offset, int whence) {
    remote_archive_data data = stream;

    DBGLOG(@"Seeking to %lld (whence: %d)", offset, whence);

    switch (whence) {
        case SEEK_SET:
            data->position = offset;
            break;
        case SEEK_CUR:
            data->position += offset;
            break;
        case SEEK_END:
            assert(0 && "SEEK_END not supported");
            break;
        default:
            assert(0 && "Invalid whence");
            break;
    }

    DBGLOG(@"New position: %llu", data->position);

    return data->position;
}
