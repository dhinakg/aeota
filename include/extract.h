#ifndef EXTRACT_H
#define EXTRACT_H

#import <AppleArchive/AppleArchive.h>
#import <Foundation/Foundation.h>

#import "args.h"

int extractAsset(AAByteStream stream, ExtractionConfiguration* config);

#endif /* EXTRACT_H */
