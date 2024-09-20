#import "utils.h"

NSData* makeSynchronousRequestWithSession(NSURLSession* session, NSURLRequest* request, NSHTTPURLResponse** response, NSError** error) {
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSData* data = nil;
    __block NSHTTPURLResponse* taskResponse = nil;
    __block NSError* taskError = nil;

    NSURLSessionDataTask* task = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData* taskData, NSURLResponse* response, NSError* error) {
                                                data = taskData;

                                                if (response) {
                                                    assert([response isKindOfClass:[NSHTTPURLResponse class]]);
                                                }
                                                taskResponse = (NSHTTPURLResponse*)response;

                                                taskError = error;
                                                dispatch_semaphore_signal(semaphore);
                                            }];
    [task resume];

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

    if (response) {
        *response = taskResponse;
    }

    if (error) {
        *error = taskError;
    }

    return data;
}

NSData* makeSynchronousRequest(NSURLRequest* request, NSHTTPURLResponse** response, NSError** error) {
    return makeSynchronousRequestWithSession([NSURLSession sharedSession], request, response, error);
}

NSData* getRange(NSString* url, NSRange range, NSError** error) {
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    [request setValue:[NSString stringWithFormat:@"bytes=%lu-%lu", (unsigned long)range.location, (unsigned long)NSMaxRange(range) - 1]
        forHTTPHeaderField:@"Range"];

    return makeSynchronousRequest(request, nil, error);
}