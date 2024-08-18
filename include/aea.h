#ifndef AEA_H
#define AEA_H

#import <AppleArchive/AppleArchive.h>
#import <Foundation/Foundation.h>

#import "args.h"

#if HAS_HPKE

int fetchKey(AEAContext stream, ExtractionConfiguration* config);

#endif

#endif /* AEA_H */
