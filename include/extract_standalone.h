#ifndef EXTRACT_STANDALONE_H
#define EXTRACT_STANDALONE_H

#include <AppleArchive/AppleArchive.h>
#include <Foundation/Foundation.h>

int extractAssetStandalone(AAByteStream stream, NSString* outputDirectory);

#endif /* EXTRACT_STANDALONE_H */
