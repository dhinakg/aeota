#ifndef ARGS_H
#define ARGS_H

#import <Foundation/Foundation.h>

// This needs to be manually synced with the enum in hpke.swift
typedef NS_ENUM(NSInteger, PrivateKeyFormat) {
    PrivateKeyFormatAll,
    PrivateKeyFormatPEM,
    PrivateKeyFormatDER,
    PrivateKeyFormatX963,
};

@interface ExtractionConfiguration : NSObject <NSCopying>

@property(nonatomic, assign) bool encrypted;
@property(nonatomic, assign) bool list;
@property(nonatomic, assign) bool remote;
@property(nonatomic, strong) NSString* archivePath;
@property(nonatomic, strong) NSString* outputPath;
@property(nonatomic, assign) bool decryptOnly;
@property(nonatomic, assign) bool exitEarly;
@property(nonatomic, strong) NSData* key;
@property(nonatomic, strong) NSString* filter;
@property(nonatomic, strong) NSRegularExpression* regex;
@property(nonatomic, assign) bool network;
@property(nonatomic, strong) NSData* unwrapKey;
@property(nonatomic, assign) PrivateKeyFormat unwrapKeyFormat;

@property(nonatomic, strong) NSString* function;

- (instancetype)copyWithFunction:(NSString*)function;

@end

ExtractionConfiguration* parseArgs(int argc, char** argv, int* returnCode);
int validateArgs(ExtractionConfiguration* config);

#endif /* ARGS_H */
