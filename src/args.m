#import "args.h"

#import <Foundation/Foundation.h>
#import <getopt.h>

#import "utils.h"

#define APPLE_ARCHIVE_MAGIC @"AA01"
#define APPLE_ENCRYPTED_ARCHIVE_MAGIC @"AEA1"

/*
Options:
-l, --list
    List the contents of the archive instead of extracting it
-i, --input <archive>
    Input archive to extract
-o, --output <directory>
    Output directory for extracted files
-k, --key <base64>
    Key in base64 format for encrypted archives
-h, --help
    Display this help message
-v, --version
    Display the version number
-f, --filter <pattern>
    Filter files by pattern
-r, --regex <pattern>
    Filter files by regex pattern
*/

static void usage(void) {
    ERRLOG(@"Usage: %@ [options]", NAME);
    ERRLOG(@"Options:");
#if AASTUFF_STANDALONE
    ERRLOG(@"  -l, --list");
    ERRLOG(@"      List the contents of the archive instead of extracting it");
#endif
    ERRLOG(@"  -i, --input <archive>");
    ERRLOG(@"      Input archive to extract");
    ERRLOG(@"  -o, --output <directory>");
    ERRLOG(@"      Output directory for extracted files");
    ERRLOG(@"  -k, --key <base64>");
    ERRLOG(@"      Key in base64 format for encrypted archives");
    ERRLOG(@"  -h, --help");
    ERRLOG(@"      Display this help message");
    ERRLOG(@"  -v, --version");
    ERRLOG(@"      Display the version number");
#if AASTUFF_STANDALONE
    ERRLOG(@"  -f, --filter <pattern>");
    ERRLOG(@"      Filter files by glob pattern");
    ERRLOG(@"  -r, --regex <pattern>");
    ERRLOG(@"      Filter files by regex pattern");
#endif
}

ExtractionConfiguration* parseArgs(int argc, char** argv, int* returnCode) {
    // clang-format off
    static struct option long_options[] = {
        #if AASTUFF_STANDALONE
        {"list", no_argument, 0, 'l'},
        #endif
        {"input", required_argument, 0, 'i'},
        {"output", required_argument, 0, 'o'},
        {"key", required_argument, 0, 'k'},
        {"help", no_argument, 0, 'h'},
        {"version", no_argument, 0, 'v'},
        #if AASTUFF_STANDALONE
        {"filter", required_argument, 0, 'f'},
        {"regex", required_argument, 0, 'r'},
        #endif
        {0, 0, 0, 0},
    };
    // clang-format on

    int option_index = 0;
    int c;

    bool list = false;
    NSString* archivePath = nil;
    NSString* outputDirectory = nil;
    NSString* keyBase64 = nil;
    NSString* filter = nil;
    NSString* regexString = nil;

    while ((c = getopt_long(argc, argv, "-li:o:k:hvf:r:", long_options, &option_index)) != -1) {
        switch (c) {
#if AASTUFF_STANDALONE
            case 'l':
                list = true;
                break;
#endif
            case 'i':
                archivePath = [NSString stringWithUTF8String:optarg];
                break;
            case 'o':
                outputDirectory = [NSString stringWithUTF8String:optarg];
                break;
            case 'k':
                keyBase64 = [NSString stringWithUTF8String:optarg];
                break;
            case 'h':
                usage();
                *returnCode = 0;
                return nil;
            case 'v':
                LOG(@"%@ %@", NAME, VERSION);
                *returnCode = 0;
                return nil;
#if AASTUFF_STANDALONE
            case 'f':
                filter = [NSString stringWithUTF8String:optarg];
                break;
            case 'r':
                regexString = [NSString stringWithUTF8String:optarg];
                break;
#endif
            default:
                ERRLOG(@"Unknown option");
                usage();
                *returnCode = 1;
                return nil;
        }
    }

    if (!archivePath) {
        ERRLOG(@"Input archive is required");
        usage();
        *returnCode = 1;
        return nil;
    }

    if (!list && !outputDirectory) {
        ERRLOG(@"Output directory is required");
        usage();
        *returnCode = 1;
        return nil;
    }

    if (filter && regexString) {
        ERRLOG(@"Cannot use both filter and regex options");
        usage();
        *returnCode = 1;
        return nil;
    }

    NSData* key = nil;
    if (keyBase64) {
        key = [[NSData alloc] initWithBase64EncodedString:keyBase64 options:0];
        if (!key) {
            ERRLOG(@"Failed to decode key from base64");
            *returnCode = 1;
            return nil;
        }
    }

    NSRegularExpression* regex = nil;
    if (regexString) {
        NSError* error = nil;
        regex = [NSRegularExpression regularExpressionWithPattern:regexString options:0 error:&error];
        if (error) {
            ERRLOG(@"Failed to compile regex: %@", error);
            *returnCode = 1;
            return nil;
        }
    }

    ExtractionConfiguration* config = [[ExtractionConfiguration alloc] init];
    config.list = list;
    config.archivePath = archivePath;
    config.outputDirectory = outputDirectory;
    config.key = key;
    config.filter = filter;
    config.regex = regex;

    return config;
}

int validateArgs(ExtractionConfiguration* config) {
    NSError* error = nil;
    NSFileManager* fileManager = [NSFileManager defaultManager];

    if (![fileManager fileExistsAtPath:config.archivePath]) {
        ERRLOG(@"Archive does not exist");
        return 1;
    }

    if (!config.list) {
        BOOL isDirectory = false;
        if (![fileManager fileExistsAtPath:config.outputDirectory isDirectory:&isDirectory]) {
            if (![fileManager createDirectoryAtPath:config.outputDirectory withIntermediateDirectories:NO attributes:nil error:&error]) {
                ERRLOG(@"Failed to create directory: %@", error);
                return 1;
            }
        } else {
            if (!isDirectory) {
                ERRLOG(@"Output path is not a directory");
                return 1;
            }
        }
    } else {
        // We need an output directory for processing to work. However, we will not mutate it
        config.outputDirectory = NSTemporaryDirectory();
    }

    NSFileHandle* handle = [NSFileHandle fileHandleForReadingAtPath:config.archivePath];
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

    NSString* magicStr = [[NSString alloc] initWithData:magic encoding:NSUTF8StringEncoding];
    if ([magicStr isEqualToString:APPLE_ENCRYPTED_ARCHIVE_MAGIC]) {
        config.encrypted = true;
    } else if ([magicStr isEqualToString:APPLE_ARCHIVE_MAGIC]) {
        config.encrypted = false;
    } else {
        ERRLOG(@"Unknown magic: %@", magicStr);
        return 1;
    }

    if (config.encrypted && !config.key) {
        ERRLOG(@"Encrypted archive requires key");
        return 1;
    }

    return 0;
}

@implementation ExtractionConfiguration

- (nonnull id)copyWithZone:(nullable NSZone*)zone {
    ExtractionConfiguration* copy = [[ExtractionConfiguration alloc] init];
    copy.list = self.list;
    copy.filter = self.filter;
    copy.regex = self.regex;

    copy.function = self.function;
    return copy;
}

- (instancetype)copyWithFunction:(NSString*)function {
    ExtractionConfiguration* copy = [self copy];
    copy.function = function;
    return copy;
}

@end
