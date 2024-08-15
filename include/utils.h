#ifndef UTILS_H
#define UTILS_H

#import <Foundation/Foundation.h>
#import <objc/NSObjCRuntime.h>
#import <stdio.h>

#define LOG(format, ...) printf("%s\n", [[NSString stringWithFormat:format, ##__VA_ARGS__] UTF8String])
#define ERRLOG(format, ...) fprintf(stderr, "%s\n", [[NSString stringWithFormat:format, ##__VA_ARGS__] UTF8String])

#if DEBUG
    #define DBGLOG(x, ...) ERRLOG(x, ##__VA_ARGS__)
#else
    #define DBGLOG(x, ...)
#endif

#if AASTUFF_STANDALONE
    #define NAME @"aastuff_standalone"
#else
    #define NAME @"aastuff"
#endif

#define VERSION @"1.0.0"

#endif /* UTILS_H */
