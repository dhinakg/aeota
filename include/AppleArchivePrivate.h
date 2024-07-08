#ifndef APPLEARCHIVE_PRIVATE_H
#define APPLEARCHIVE_PRIVATE_H

#import <AppleArchive/AppleArchive.h>
#import <sys/types.h>

__BEGIN_DECLS

// TODO: Figure out how this is different from normal AppleArchive
typedef void* AAAssetExtractor;

AAAssetExtractor AAAssetExtractorCreate(const char* work_dir, uint64_t* maybe_offset, void* unknown);

// 102: AEA context
// 103: progress
// 104: entry message
//  - 90: start?
//  - 91: extract?
//  - 92: complete
int AAAssetExtractorSetParameterCallback(AAAssetExtractor extractor, int param, void* callback);

// 101: first arg to callbacks
// 105: input directory
// 106: output directory
int AAAssetExtractorSetParameterPtr(AAAssetExtractor extractor, int param, void* ptr);

int AAAssetExtractorWrite(AAAssetExtractor extractor, void* buffer, size_t size);
int AAAssetExtractorDestroy(AAAssetExtractor extractor, uint64_t* maybe_offset);

AAArchiveStream AAVerifyDirectoryArchiveOutputStreamOpen(const char* dir, AAFieldKeySet key_set, void* msg_data,
                                                         AAEntryMessageProc msg_proc, AAFlagSet flags, int n_threads);

// What does YOP stand for?
typedef uint32_t AAYopType;
APPLE_ARCHIVE_ENUM(AAYopTypes, uint32_t) {
    AA_YOP_TYPE_COPY = 'C',       ///< copy
    AA_YOP_TYPE_EXTRACT = 'E',    ///< extract
    AA_YOP_TYPE_SRC_CHECK = 'I',  ///< source check
    AA_YOP_TYPE_MANIFEST = 'M',   ///< manifest
    AA_YOP_TYPE_DST_FIXUP = 'O',  ///< destination fixup
    AA_YOP_TYPE_PATCH = 'P',      ///< patch
    AA_YOP_TYPE_REMOVE = 'R'      ///< remove
};

__END_DECLS

#endif /* APPLEARCHIVE_PRIVATE_H */
