#ifndef EXTRACT_STANDALONE_H
#define EXTRACT_STANDALONE_H

#import <AppleArchive/AppleArchive.h>
#import <Foundation/Foundation.h>

#import "args.h"

int extractAssetStandalone(AAByteStream stream, ExtractionConfiguration* config);

#endif /* EXTRACT_STANDALONE_H */
