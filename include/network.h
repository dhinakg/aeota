#ifndef NETWORK_H
#define NETWORK_H

#import <AppleArchive/AppleArchive.h>
#import <Foundation/Foundation.h>

bool checkAlive(NSString* url, NSError** error);

AAByteStream remote_archive_open(NSString* url);
int remote_archive_close(void* stream);
ssize_t remote_archive_read(void* stream, void* buf, size_t nbyte);
off_t remote_archive_seek(void* stream, off_t offset, int whence);

#endif /* NETWORK_H */