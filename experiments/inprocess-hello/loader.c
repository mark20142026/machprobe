#include "loader.h"
#include <mach-o/loader.h>
#include <mach/machine.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <limits.h>

#define MAX_SEGMENTS 12
#define MAX_IMAGE (64u * 1024u * 1024u)
typedef struct {
    const unsigned char *file;
    size_t file_size;
    struct segment_command_64 segments[MAX_SEGMENTS];
    unsigned count, puts_bound, binder_bound;
    uint64_t low, span;
    unsigned char *base;
    MPHelloResult *result;
} Image;

// The harness is deliberately single-threaded. No arbitrary runtime calls are
// exposed to the image: its one application import is bridged to this service.
static MPHelloResult *active_result;
static int bridged_puts(const char *text) {
    if (!active_result) abort();
    size_t used = strlen(active_result->output);
    size_t available = sizeof active_result->output - used;
    int n = snprintf(active_result->output + used, available, "%s\n", text);
    active_result->puts_calls++;
    return n < 0 || (size_t)n >= available ? EOF : n;
}
static void forbidden_lazy_binder(void) {
    // Every lazy import is eagerly bound. Reaching this means a loader bug.
    abort();
}
static int fail(Image *im, const char *message) {
    snprintf(im->result->error, sizeof im->result->error, "%s", message);
    return 0;
}
static int range(Image *im, uint64_t offset, uint64_t size) {
    return offset <= im->file_size && size <= im->file_size - offset;
}
static int uleb(Image *im, const unsigned char **cursor, const unsigned char *end, uint64_t *value) {
    *value = 0;
    for (unsigned i=0; i<10; ++i) {
        if (*cursor == end) return fail(im,"truncated dyld ULEB128");
        unsigned char c=*(*cursor)++;
        if (i==9 && (c&0xfe)) return fail(im,"overflowing dyld ULEB128");
        *value |= (uint64_t)(c&127) << (i*7);
        if (!(c&128)) return 1;
    }
    return fail(im,"overflowing dyld ULEB128");
}
static uintptr_t *slot(Image *im, unsigned segment, uint64_t offset) {
    if (segment >= im->count) { fail(im,"fixup segment out of range"); return NULL; }
    struct segment_command_64 *s=&im->segments[segment];
    if (!(s->initprot & VM_PROT_WRITE) || (s->initprot & VM_PROT_EXECUTE) ||
        s->vmaddr < im->low || offset>s->vmsize || sizeof(uintptr_t)>s->vmsize-offset || offset%8) {
        fail(im,"fixup is not an aligned writable data pointer"); return NULL;
    }
    return (uintptr_t *)(im->base+(s->vmaddr-im->low)+offset);
}
static int apply_rebase(Image *im, uint32_t offset, uint32_t size) {
    if (!range(im,offset,size)) return fail(im,"rebase stream outside file");
    const unsigned char *p=im->file+offset,*end=p+size;
    unsigned segment=UINT_MAX, type=0;
    uint64_t address=0;
    while (p<end) {
        unsigned char byte=*p++,op=byte&REBASE_OPCODE_MASK,imm=byte&REBASE_IMMEDIATE_MASK;
        uint64_t count=0;
        switch(op) {
        case REBASE_OPCODE_DONE:
            while(p<end) if(*p++) return fail(im,"nonzero rebase padding");
            return 1;
        case REBASE_OPCODE_SET_TYPE_IMM: type=imm; break;
        case REBASE_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB:
            segment=imm; if(!uleb(im,&p,end,&address))return 0; break;
        case REBASE_OPCODE_DO_REBASE_IMM_TIMES:
            count=imm;
            if(type!=REBASE_TYPE_POINTER)return fail(im,"unsupported rebase type");
            while(count--) {
                if(im->result->rebases>=256)return fail(im,"rebase limit");
                uintptr_t *where=slot(im,segment,address); if(!where)return 0;
                if(*where<im->low || *where-im->low>=im->span)return fail(im,"rebase target outside image");
                *where=(uintptr_t)im->base+(*where-im->low);
                im->result->rebases++; address+=sizeof(uintptr_t);
            }
            break;
        default: return fail(im,"rebase opcode outside controlled hello subset");
        }
    }
    return fail(im,"rebase stream missing DONE");
}
static int apply_bind(Image *im, uint32_t offset, uint32_t size, int lazy) {
    if (!range(im,offset,size)) return fail(im,"bind stream outside file");
    const unsigned char *p=im->file+offset,*end=p+size;
    unsigned segment=UINT_MAX,type=BIND_TYPE_POINTER,ordinal=0;
    uint64_t address=0;
    const char *symbol=NULL;
    while(p<end) {
        unsigned char byte=*p++,op=byte&BIND_OPCODE_MASK,imm=byte&BIND_IMMEDIATE_MASK;
        switch(op) {
        case BIND_OPCODE_DONE:
            if(lazy) { segment=UINT_MAX; address=0; ordinal=0; symbol=NULL; type=BIND_TYPE_POINTER; break; }
            while(p<end)if(*p++)return fail(im,"nonzero bind padding");
            return 1;
        case BIND_OPCODE_SET_DYLIB_ORDINAL_IMM: ordinal=imm; break;
        case BIND_OPCODE_SET_TYPE_IMM: type=imm; break;
        case BIND_OPCODE_SET_SYMBOL_TRAILING_FLAGS_IMM: {
            if(imm)return fail(im,"unsupported symbol flags");
            const unsigned char *zero=memchr(p,0,(size_t)(end-p));
            if(!zero)return fail(im,"unterminated bind symbol");
            symbol=(const char *)p;p=zero+1;break;
        }
        case BIND_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB:
            segment=imm;if(!uleb(im,&p,end,&address))return 0;break;
        case BIND_OPCODE_DO_BIND: {
            if(type!=BIND_TYPE_POINTER || ordinal!=1 || !symbol)return fail(im,"unsupported bind state");
            if(im->result->binds>=256)return fail(im,"bind limit");
            uintptr_t *where=slot(im,segment,address);if(!where)return 0;
            if(!strcmp(symbol,"_puts")) { *where=(uintptr_t)&bridged_puts;im->puts_bound++; }
            else if(!strcmp(symbol,"dyld_stub_binder")) { *where=(uintptr_t)&forbidden_lazy_binder;im->binder_bound++; }
            else return fail(im,"import outside hello whitelist");
            im->result->binds++;address+=sizeof(uintptr_t);break;
        }
        default:return fail(im,"bind opcode outside controlled hello subset");
        }
    }
    return lazy?1:fail(im,"bind stream missing DONE");
}

int mp_run_hello(const char *path, MPHelloResult *result) {
    if (!result) return 1;
    memset(result,0,sizeof *result);
    Image im={.low=UINT64_MAX,.base=MAP_FAILED,.result=result};
    if(!path) { fail(&im,"missing fixture path");return 1; }
    if(active_result) { fail(&im,"loader is not reentrant");return 1; }
    int fd=open(path,O_RDONLY), ok=0;
    if(fd<0) { snprintf(result->error,sizeof result->error,"open: %s",strerror(errno));return 1; }
    struct stat st;
    if(fstat(fd,&st) || st.st_size<(off_t)sizeof(struct mach_header_64) || st.st_size>MAX_IMAGE) {
        fail(&im,"invalid or oversized fixture file");goto done;
    }
    im.file_size=(size_t)st.st_size;
    im.file=mmap(NULL,im.file_size,PROT_READ,MAP_PRIVATE,fd,0);
    if(im.file==MAP_FAILED) { im.file=NULL;fail(&im,"cannot map fixture for inspection");goto done; }
    struct mach_header_64 h;memcpy(&h,im.file,sizeof h);
    if(h.magic!=MH_MAGIC_64 || h.cputype!=CPU_TYPE_ARM64 || h.cpusubtype!=CPU_SUBTYPE_ARM64_ALL || h.filetype!=MH_EXECUTE) {
        fail(&im,"requires thin ordinary ARM64 MH_EXECUTE");goto done;
    }
    if(!range(&im,sizeof h,h.sizeofcmds) || h.ncmds>h.sizeofcmds/8) { fail(&im,"bad load command region");goto done; }
    struct dyld_info_command dyld={0};
    struct linkedit_data_command signature={0};
    unsigned signatureCount=0;
    uint64_t entryoff=UINT64_MAX,high=0,textStart=0,textEnd=0,textVM=UINT64_MAX;
    unsigned libCount=0,platform=0,mainCount=0,dyldCount=0;
    size_t cursor=sizeof h,commandEnd=cursor+h.sizeofcmds;
    long page=sysconf(_SC_PAGESIZE);
    if(page<=0) { fail(&im,"cannot determine host page size");goto done; }
    for(unsigned i=0;i<h.ncmds;++i) {
        struct load_command lc;
        if(commandEnd-cursor<sizeof lc) { fail(&im,"truncated command");goto done; }
        memcpy(&lc,im.file+cursor,sizeof lc);
        if(lc.cmdsize<8 || lc.cmdsize%8 || lc.cmdsize>commandEnd-cursor) { fail(&im,"bad command size");goto done; }
#define READ_COMMAND(type, name) type name; if(lc.cmdsize<sizeof name){fail(&im,"short known command");goto done;} memcpy(&name,im.file+cursor,sizeof name)
        switch(lc.cmd) {
        case LC_SEGMENT_64: {
            READ_COMMAND(struct segment_command_64,s);
            if(im.count==MAX_SEGMENTS || s.nsects>(lc.cmdsize-sizeof s)/sizeof(struct section_64)) { fail(&im,"segment/section limit");goto done; }
            im.segments[im.count++]=s;
            if(!strncmp(s.segname,"__PAGEZERO",16)) {
                if(s.filesize || s.initprot || s.nsects) { fail(&im,"invalid PAGEZERO");goto done; }
                break;
            }
            if(s.vmaddr%page || s.vmsize%page || s.fileoff%page || s.filesize>s.vmsize || s.vmsize>MAX_IMAGE || s.vmaddr>UINT64_MAX-s.vmsize || !range(&im,s.fileoff,s.filesize)) {
                fail(&im,"invalid segment bounds/alignment");goto done;
            }
            if(s.initprot&VM_PROT_EXECUTE) {
                if(strncmp(s.segname,"__TEXT",16) || s.initprot&VM_PROT_WRITE || s.fileoff || s.filesize!=s.vmsize) { fail(&im,"unsupported executable segment");goto done; }
            }
            for(unsigned j=0;j+1<im.count;++j) {
                struct segment_command_64 *other=&im.segments[j];
                if(!strncmp(other->segname,"__PAGEZERO",16))continue;
                if(s.vmaddr<other->vmaddr+other->vmsize && other->vmaddr<s.vmaddr+s.vmsize) { fail(&im,"overlapping segments");goto done; }
            }
            if(s.vmaddr<im.low)im.low=s.vmaddr;
            if(s.vmaddr+s.vmsize>high)high=s.vmaddr+s.vmsize;
            for(unsigned j=0;j<s.nsects;++j) {
                struct section_64 section;memcpy(&section,im.file+cursor+sizeof s+j*sizeof section,sizeof section);
                unsigned t=section.flags&SECTION_TYPE;
                if(t==S_MOD_INIT_FUNC_POINTERS || t==S_MOD_TERM_FUNC_POINTERS || t>=S_THREAD_LOCAL_REGULAR) {
                    fail(&im,"initializers/TLS outside hello subset");goto done;
                }
                if(!strncmp(s.segname,"__TEXT",16) && !strncmp(section.sectname,"__text",16)) {
                    if(section.offset>s.filesize || section.size>s.filesize-section.offset) { fail(&im,"invalid text section");goto done; }
                    textStart=section.offset;textEnd=textStart+section.size;textVM=s.vmaddr;
                }
            }
            break;
        }
        case LC_BUILD_VERSION: { READ_COMMAND(struct build_version_command,b);platform=b.platform;break; }
        case LC_MAIN: { READ_COMMAND(struct entry_point_command,e);entryoff=e.entryoff;mainCount++;break; }
        case LC_CODE_SIGNATURE: { READ_COMMAND(struct linkedit_data_command,c);signature=c;signatureCount++;break; }
        case LC_DYLD_INFO_ONLY: { READ_COMMAND(struct dyld_info_command,d);dyld=d;dyldCount++;break; }
        case LC_LOAD_DYLIB: {
            READ_COMMAND(struct dylib_command,d);
            if(d.dylib.name.offset<sizeof d || d.dylib.name.offset>=lc.cmdsize) { fail(&im,"bad dylib name");goto done; }
            const char *name=(const char *)im.file+cursor+d.dylib.name.offset;
            if(!memchr(name,0,lc.cmdsize-d.dylib.name.offset) || strcmp(name,"/usr/lib/libSystem.B.dylib")) { fail(&im,"only libSystem fixture supported");goto done; }
            libCount++;break;
        }
        case LC_DYLD_CHAINED_FIXUPS: case LC_LOAD_WEAK_DYLIB: case LC_REEXPORT_DYLIB: case LC_LOAD_UPWARD_DYLIB:
        case LC_ENCRYPTION_INFO: case LC_ENCRYPTION_INFO_64:
            fail(&im,"load command outside hello runtime subset");goto done;
        default: break;
        }
#undef READ_COMMAND
        cursor+=lc.cmdsize;
    }
    if(cursor!=commandEnd || textVM!=im.low || platform!=PLATFORM_MACOS || libCount!=1 || mainCount!=1 || dyldCount!=1 || dyld.weak_bind_size || entryoff<textStart || entryoff>=textEnd || high<=im.low || high-im.low>MAX_IMAGE) {
        fail(&im,"image does not match controlled macOS hello contract");goto done;
    }
    if(signatureCount!=1 || !signature.datasize || !range(&im,signature.dataoff,signature.datasize)) {
        fail(&im,"requires existing embedded code signature");goto done;
    }
    // A freshly copied signed file may lack the kernel's cached signature state.
    // Register its EXISTING on-disk signature and honor the kernel's LV decision,
    // as dyld does. Neither signature bytes nor host security policy are changed.
    fsignatures_t siginfo={.fs_file_start=0,.fs_blob_start=(void *)(uintptr_t)signature.dataoff,.fs_blob_size=signature.datasize};
    if(fcntl(fd,F_ADDFILESIGS_RETURN,&siginfo)<0) {
        snprintf(result->error,sizeof result->error,"signature registration: %s",strerror(errno));goto done;
    }
    if(siginfo.fs_file_start<(off_t)signature.dataoff) { fail(&im,"signature does not cover the image");goto done; }
    result->signature_registered=1;
    char lv_message[160]={0};
    fchecklv_t check={.lv_file_start=0,.lv_error_message_size=sizeof lv_message,.lv_error_message=lv_message};
    if(fcntl(fd,F_CHECK_LV,&check)<0) {
        snprintf(result->error,sizeof result->error,"library validation: %s (%s)",lv_message,strerror(errno));goto done;
    }
    result->library_validation_passed=1;
    im.span=high-im.low;
    im.base=mmap(NULL,(size_t)im.span,PROT_NONE,MAP_PRIVATE|MAP_ANON,-1,0);
    if(im.base==MAP_FAILED) { fail(&im,"cannot reserve image address range");goto done; }
    for(unsigned i=0;i<im.count;++i) {
        struct segment_command_64 *s=&im.segments[i];
        if(!strncmp(s->segname,"__PAGEZERO",16) || !s->vmsize)continue;
        unsigned char *address=im.base+(s->vmaddr-im.low);
        size_t filePages=(size_t)((s->filesize+page-1)/page*page);
        // Executable pages come directly from the signed file, never a RWX buffer.
        if(filePages && mmap(address,filePages,s->initprot,MAP_PRIVATE|MAP_FIXED,fd,(off_t)s->fileoff)==MAP_FAILED) {
            snprintf(result->error,sizeof result->error,"map %.16s prot=%d: %s",s->segname,s->initprot,strerror(errno));goto done;
        }
        if(s->vmsize>filePages && mmap(address+filePages,(size_t)s->vmsize-filePages,s->initprot,MAP_PRIVATE|MAP_ANON|MAP_FIXED,-1,0)==MAP_FAILED) {
            fail(&im,"cannot map zero-fill tail");goto done;
        }
        result->mapped_segments++;
    }
    if(!apply_rebase(&im,dyld.rebase_off,dyld.rebase_size) ||
       !apply_bind(&im,dyld.bind_off,dyld.bind_size,0) ||
       !apply_bind(&im,dyld.lazy_bind_off,dyld.lazy_bind_size,1))goto done;
    if(im.puts_bound!=1 || im.binder_bound!=1 || result->rebases!=1) { fail(&im,"unexpected hello fixup counts");goto done; }
    for(unsigned i=0;i<im.count;++i) {
        struct segment_command_64 *s=&im.segments[i];
        if(!strncmp(s->segname,"__DATA_CONST",16) && mprotect(im.base+(s->vmaddr-im.low),(size_t)s->vmsize,PROT_READ)) { fail(&im,"cannot protect constant data");goto done; }
    }
    result->entry_address=(uintptr_t)im.base+entryoff;
    int (*entry)(void);memcpy(&entry,&result->entry_address,sizeof entry);
    active_result=result;
    result->target_return=entry();
    active_result=NULL;
    ok=1;
done:
    if(im.base!=MAP_FAILED)munmap(im.base,(size_t)im.span);
    if(im.file)munmap((void *)im.file,im.file_size);
    close(fd);
    return ok?0:1;
}

int mp_mapping_errno(const char *path, int executable) {
    if (!path) return EINVAL;
    int fd=open(path,O_RDONLY);
    if(fd<0)return errno;
    long page=sysconf(_SC_PAGESIZE);
    if(page<=0){close(fd);return EINVAL;}
    void *p=mmap(NULL,(size_t)page,PROT_READ|(executable?PROT_EXEC:0),MAP_PRIVATE,fd,0);
    int error=p==MAP_FAILED?errno:0;
    if(p!=MAP_FAILED)munmap(p,(size_t)page);
    close(fd);return error;
}
