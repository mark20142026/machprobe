#import "signature_probe.h"
#include <mach-o/loader.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>

NSDictionary *mp_signature_probe(NSString *path) {
    NSMutableDictionary *result=[NSMutableDictionary dictionary];
    int fd=open(path.fileSystemRepresentation,O_RDONLY);
    if(fd<0)return @{@"open_errno":@(errno)};
    struct mach_header_64 header;
    if(pread(fd,&header,sizeof header,0)!=sizeof header || header.magic!=MH_MAGIC_64 || header.sizeofcmds>1024*1024) {
        close(fd);return @{@"error":@"Invalid control header"};
    }
    off_t cursor=sizeof header,end=cursor+header.sizeofcmds;
    struct linkedit_data_command signature={0};
    for(uint32_t i=0;i<header.ncmds;i++) {
        struct load_command command;
        if(end-cursor<(off_t)sizeof command || pread(fd,&command,sizeof command,cursor)!=sizeof command || command.cmdsize<sizeof command || command.cmdsize>end-cursor)break;
        if(command.cmd==LC_CODE_SIGNATURE && command.cmdsize>=sizeof signature) {
            if(pread(fd,&signature,sizeof signature,cursor)!=sizeof signature)signature.datasize=0;
        }
        if(command.cmd==LC_BUILD_VERSION && command.cmdsize>=sizeof(struct build_version_command)) {
            struct build_version_command build;
            if(pread(fd,&build,sizeof build,cursor)==sizeof build)result[@"platform"]=@(build.platform);
        }
        cursor+=command.cmdsize;
    }
    if(!signature.datasize){close(fd);return @{@"error":@"No embedded signature"};}
    fsignatures_t info={.fs_file_start=0,.fs_blob_start=(void *)(uintptr_t)signature.dataoff,.fs_blob_size=signature.datasize};
    errno=0;int rc=fcntl(fd,F_ADDFILESIGS_RETURN,&info);int code=errno;
    result[@"registration_rc"]=@(rc);result[@"registration_errno"]=@(code);
    if(rc<0)result[@"registration_error"]=[NSString stringWithUTF8String:strerror(code)];
    else {
        result[@"covered_bytes"]=@(info.fs_file_start);
        char message[256]={0};fchecklv_t check={.lv_file_start=0,.lv_error_message_size=sizeof message,.lv_error_message=message};
        errno=0;rc=fcntl(fd,F_CHECK_LV,&check);code=errno;
        result[@"validation_rc"]=@(rc);result[@"validation_errno"]=@(code);
        result[@"validation_message"]=[NSString stringWithUTF8String:message]?:@"";
    }
    close(fd);return result;
}
