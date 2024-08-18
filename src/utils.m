#import "utils.h"

NSData* makeSynchronousRequest(NSURLRequest* request, NSHTTPURLResponse** response, NSError** error) {
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSData* data = nil;
    __block NSHTTPURLResponse* taskResponse = nil;
    __block NSError* taskError = nil;

    NSURLSessionDataTask* task = [[NSURLSession sharedSession]
        dataTaskWithRequest:request completionHandler:^(NSData* taskData, NSURLResponse* response, NSError* error) {
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
