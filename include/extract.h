#ifndef EXTRACT_H
#define EXTRACT_H

#include <AppleArchive/AppleArchive.h>
#include <Foundation/Foundation.h>

int extractAsset(AAByteStream stream, NSString* outputDirectory);

#endif /* EXTRACT_H */
