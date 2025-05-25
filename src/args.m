#import "args.h"

#import <Foundation/Foundation.h>
#import <getopt.h>

#import "network.h"
#import "utils.h"

#define APPLE_ARCHIVE_MAGIC @"AA01"
#define APPLE_ENCRYPTED_ARCHIVE_MAGIC @"AEA1"

static void usage(void) {
    ERRLOG(@"Usage: %@ [options]", NAME);
    ERRLOG(@"Options:");
    ERRLOG(@"  -i, --input <archive>");
    ERRLOG(@"      Input archive to extract");
    ERRLOG(@"  -o, --output <directory or file>");
    ERRLOG(@"      Output directory for extracted files");
    ERRLOG(@"      If decrypt-only is set, output path for decrypted contents");
#if AASTUFF_STANDALONE
    ERRLOG(@"  -l, --list");
    ERRLOG(@"      List the contents of the archive instead of extracting it");
#endif
    ERRLOG(@"  -d, --decrypt-only");
    ERRLOG(@"      Only decrypt the archive, do not extract it");
    ERRLOG(@"  -h, --help");
    ERRLOG(@"      Display this help message");
    ERRLOG(@"  -v, --version");
    ERRLOG(@"      Display the version number");
#if AASTUFF_STANDALONE
    ERRLOG(@"Filter Options:");
    ERRLOG(@"  -f, --filter <pattern>");
    ERRLOG(@"      Filter files by glob pattern");
    ERRLOG(@"  -r, --regex <pattern>");
    ERRLOG(@"      Filter files by regex pattern");
    ERRLOG(@"  -e, --exit-early");
    ERRLOG(@"      Exit early after extracting the first matching file");
#endif
    ERRLOG(@"Key Options:");
    ERRLOG(@"  -k, --key <base64>");
    ERRLOG(@"      Decryption key in base64 format for encrypted archives");
    ERRLOG(@"  -K, --key-file <path>");
    ERRLOG(@"      Path to file containing raw decryption key for encrypted archives");
#if HAS_HPKE
    ERRLOG(@"  -u, --unwrap <base64>");
    ERRLOG(@"      Unwrap decryption key using private key in base64 format");
    ERRLOG(@"  -U, --unwrap-key-file <path>");
    ERRLOG(@"      Unwrap decryption key using private key at path");
    ERRLOG(@"      --unwrap-key-format <format>");
    ERRLOG(@"      Format of the private key (pem, der, x9.63/x963)");
    ERRLOG(@"      By default, each format is tried in order");
    ERRLOG(@"  -n, --network");
    ERRLOG(@"      Fetch private key using URL in auth data");
#endif
}

ExtractionConfiguration* parseArgs(int argc, char** argv, int* returnCode) {
    // clang-format off
    static struct option long_options[] = {
        {"input", required_argument, 0, 'i'},
        {"output", required_argument, 0, 'o'},
        #if AASTUFF_STANDALONE
        {"list", no_argument, 0, 'l'},
        #endif
        {"decrypt-only", no_argument, 0, 'd'},
        {"help", no_argument, 0, 'h'},
        {"version", no_argument, 0, 'v'},
        #if AASTUFF_STANDALONE
        {"filter", required_argument, 0, 'f'},
        {"regex", required_argument, 0, 'r'},
        {"exit-early", no_argument, 0, 'e'},
        #endif
        {"key", required_argument, 0, 'k'},
        {"key-file", required_argument, 0, 'K'},
        #if HAS_HPKE
        {"unwrap", required_argument, 0, 'u'},
        {"unwrap-key-file", required_argument, 0, 'U'},
        {"unwrap-key-format", required_argument, 0, 'F'},
        {"network", no_argument, 0, 'n'},
        #endif
        {0, 0, 0, 0},
    };
    // clang-format on

    int option_index = 0;
    int c;

    bool list = false;
    bool remote = false;
    NSString* archivePath = nil;
    NSString* outputPath = nil;
    bool decryptOnly = false;
    NSString* keyBase64 = nil;
    NSString* keyPath = nil;
    NSString* filter = nil;
    NSString* regexString = nil;
    bool exitEarly = false;
    bool network = false;
    NSString* unwrapKeyBase64 = nil;
    NSString* unwrapKeyPath = nil;
    NSString* unwrapKeyFormatString = nil;

    while ((c = getopt_long(argc, argv, "-i:o:ldhvf:r:ek:K:u:U:n", long_options, &option_index)) != -1) {
        switch (c) {
            case 'i':
                archivePath = [NSString stringWithUTF8String:optarg];
                break;
            case 'o':
                outputPath = [NSString stringWithUTF8String:optarg];
                break;
#if AASTUFF_STANDALONE
            case 'l':
                list = true;
                break;
#endif
            case 'd':
                decryptOnly = true;
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
            case 'e':
                exitEarly = true;
                break;
#endif
            case 'k':
                keyBase64 = [NSString stringWithUTF8String:optarg];
                break;
            case 'K':
                keyPath = [NSString stringWithUTF8String:optarg];
                break;
#if HAS_HPKE
            case 'u':
                unwrapKeyBase64 = [NSString stringWithUTF8String:optarg];
                break;
            case 'U':
                unwrapKeyPath = [NSString stringWithUTF8String:optarg];
                break;
            case 'F':
                unwrapKeyFormatString = [NSString stringWithUTF8String:optarg];
                break;
            case 'n':
                network = true;
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

    if ([@[@"http", @"https"] containsObject:[NSURL URLWithString:archivePath].scheme]) {
        remote = true;
    }

    if (!list && !outputPath) {
        ERRLOG(@"Output %@ is required", decryptOnly ? @"file path" : @"directory");
        usage();
        *returnCode = 1;
        return nil;
    }

    if (decryptOnly && list) {
        ERRLOG(@"Cannot use both decrypt-only and list options");
        usage();
        *returnCode = 1;
        return nil;
    }

    if (decryptOnly && (filter || regexString)) {
        ERRLOG(@"Cannot use both decrypt-only and filter options");
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

    if (keyPath && keyBase64) {
        ERRLOG(@"Cannot use both key and key file options");
        usage();
        *returnCode = 1;
        return nil;
    }

    if (unwrapKeyPath && unwrapKeyBase64) {
        ERRLOG(@"Cannot use both unwrap key and unwrap key file options");
        usage();
        *returnCode = 1;
        return nil;
    }

    if ((keyBase64 || keyPath) && (unwrapKeyBase64 || unwrapKeyPath)) {
        ERRLOG(@"Cannot use both key and unwrap key options");
        usage();
        *returnCode = 1;
        return nil;
    }

    if ((keyBase64 || keyPath) && network) {
        ERRLOG(@"Cannot use both key and network options");
        usage();
        *returnCode = 1;
        return nil;
    }

    if (network && (unwrapKeyBase64 || unwrapKeyPath)) {
        ERRLOG(@"Cannot use both network and unwrap options");
        usage();
        *returnCode = 1;
        return nil;
    }

    PrivateKeyFormat unwrapKeyFormat = PrivateKeyFormatAll;
    if (unwrapKeyFormatString) {
        NSDictionary* formatStringToNumber = @{
            @"pem": @(PrivateKeyFormatPEM),
            @"der": @(PrivateKeyFormatDER),
            @"x963": @(PrivateKeyFormatX963),
            @"x9.63": @(PrivateKeyFormatX963),
        };
        NSNumber* formatNumber = formatStringToNumber[unwrapKeyFormatString.lowercaseString];
        if (!formatNumber) {
            ERRLOG(@"Invalid unwrap key format");
            usage();
            *returnCode = 1;
            return nil;
        }

        unwrapKeyFormat = [formatNumber intValue];
    }

    NSData* key = nil;
    if (keyPath) {
        NSError* error = nil;
        key = [[NSData alloc] initWithContentsOfFile:keyPath options:0 error:&error];
        if (!key) {
            ERRLOG(@"Failed to read key file: %@", error);
            *returnCode = 1;
            return nil;
        }
    } else if (keyBase64) {
        key = [[NSData alloc] initWithBase64EncodedString:keyBase64 options:0];
        if (!key) {
            ERRLOG(@"Failed to decode key from base64");
            *returnCode = 1;
            return nil;
        }
    }

    NSData* unwrapKey = nil;
    if (unwrapKeyPath) {
        NSError* error = nil;
        unwrapKey = [[NSData alloc] initWithContentsOfFile:unwrapKeyPath options:0 error:&error];
        if (!unwrapKey) {
            ERRLOG(@"Failed to read unwrap key file: %@", error);
            *returnCode = 1;
            return nil;
        }
    } else if (unwrapKeyBase64) {
        unwrapKey = [[NSData alloc] initWithBase64EncodedString:unwrapKeyBase64 options:0];
        if (!unwrapKey) {
            ERRLOG(@"Failed to decode unwrap key from base64");
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
    config.remote = remote;
    config.archivePath = archivePath;
    config.outputPath = outputPath;
    config.decryptOnly = decryptOnly;
    config.exitEarly = exitEarly;
    config.key = key;
    config.filter = filter;
    config.regex = regex;
    config.network = network;
    config.unwrapKey = unwrapKey;
    config.unwrapKeyFormat = unwrapKeyFormat;

    return config;
}

int validateArgs(ExtractionConfiguration* config) {
    NSError* error = nil;
    NSFileManager* fileManager = [NSFileManager defaultManager];

    if (config.remote) {
        if (!checkAlive(config.archivePath, &error)) {
            ERRLOG(@"Failed to connect to server: %@", error);
            return 1;
        }
    } else {
        if (![fileManager fileExistsAtPath:config.archivePath]) {
            ERRLOG(@"Archive does not exist");
            return 1;
        }
    }

    if (config.list) {
        // We need an output directory for processing to work. However, we will not mutate it
        config.outputPath = NSTemporaryDirectory();
    } else {
        BOOL isDirectory = false;
        BOOL exists = [fileManager fileExistsAtPath:config.outputPath isDirectory:&isDirectory];
        if (config.decryptOnly) {
            if (exists) {
                ERRLOG(@"Output path already exists");
                return 1;
            }
        } else if (!exists) {
            if (![fileManager createDirectoryAtPath:config.outputPath withIntermediateDirectories:NO attributes:nil error:&error]) {
                ERRLOG(@"Failed to create directory: %@", error);
                return 1;
            }
        } else {
            if (!isDirectory) {
                ERRLOG(@"Output path is not a directory");
                return 1;
            }
        }
    }

    NSData* magic = nil;

    if (config.remote) {
        magic = getRange(config.archivePath, NSMakeRange(0, 4), &error);
    } else {
        NSFileHandle* handle = [NSFileHandle fileHandleForReadingAtPath:config.archivePath];
        if (!handle) {
            ERRLOG(@"Failed to open archive file");
            return 1;
        }

        magic = [handle readDataUpToLength:4 error:&error];
        // If this fails, can't do anything about it, so just ignore the error
        [handle closeAndReturnError:nil];
    }

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

    if (!config.encrypted && config.decryptOnly) {
        ERRLOG(@"Cannot decrypt unencrypted archive");
        return 1;
    }

    if (config.encrypted && !(config.key || config.unwrapKey || config.network)) {
        ERRLOG(@"Encrypted archive requires key, unwrap key, or network option");
        return 1;
    }

    if (config.unwrapKey && config.unwrapKeyFormat == PrivateKeyFormatPEM) {
        if (![[NSString alloc] initWithData:config.unwrapKey encoding:NSUTF8StringEncoding]) {
            ERRLOG(@"Invalid PEM key");
            return 1;
        }
    }

    return 0;
}

@implementation ExtractionConfiguration

- (nonnull id)copyWithZone:(nullable NSZone*)zone {
    ExtractionConfiguration* copy = [[ExtractionConfiguration alloc] init];
    copy.encrypted = self.encrypted;
    copy.list = self.list;
    copy.remote = self.remote;
    copy.archivePath = self.archivePath;
    copy.outputPath = self.outputPath;
    copy.decryptOnly = self.decryptOnly;
    copy.exitEarly = self.exitEarly;
    copy.key = self.key;
    copy.filter = self.filter;
    copy.regex = self.regex;
    copy.network = self.network;
    copy.unwrapKey = self.unwrapKey;
    copy.unwrapKeyFormat = self.unwrapKeyFormat;

    copy.function = self.function;
    return copy;
}

- (instancetype)copyWithFunction:(NSString*)function {
    ExtractionConfiguration* copy = [self copy];
    copy.function = function;
    return copy;
}

@end
