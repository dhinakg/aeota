#ifndef ARGS_H
#define ARGS_H

#import <Foundation/Foundation.h>

@interface ExtractionConfiguration : NSObject <NSCopying>

@property(nonatomic, assign) bool encrypted;
@property(nonatomic, assign) bool list;
@property(nonatomic, strong) NSString* archivePath;
@property(nonatomic, strong) NSString* outputDirectory;
@property(nonatomic, strong) NSData* key;
@property(nonatomic, strong) NSString* filter;
@property(nonatomic, strong) NSRegularExpression* regex;

@property(nonatomic, strong) NSString* function;

- (instancetype)copyWithFunction:(NSString*)function;

@end

ExtractionConfiguration* parseArgs(int argc, char** argv, int* returnCode);
int validateArgs(ExtractionConfiguration* config);

#endif /* ARGS_H */
