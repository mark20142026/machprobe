#include "internal.h"
#include <mach-o/nlist.h>
#include <stdatomic.h>
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

static int trace_load=-1;
#define LOAD_TRACE(...) do{if(trace_load<0)trace_load=getenv("MP_LOAD_TRACE")!=NULL;if(trace_load){fprintf(stderr,"[load] " __VA_ARGS__);fputc('\n',stderr);}}while(0)
static _Atomic size_t live_images;
static Image *resident_images; // Same serialized-owner contract as guest calls.
int mp_fail(Image *im, const char *message) {
    snprintf(im->error, sizeof im->error, "%s", message); return 0;
}
#define fail mp_fail
static int range(Image *im, uint64_t offset, uint64_t size) {
    return offset <= im->file_size && size <= im->file_size - offset;
}
static int embedded_source(int fd, size_t file_size, const char *name,
                           uint64_t *offset, size_t *size, uint64_t *text_size, size_t *capacity,
                           struct linkedit_data_command *signature) {
    struct mach_header_64 h;
    if(!name || strlen(name)>16 || pread(fd,&h,sizeof h,0)!=sizeof h ||
       h.magic!=MH_MAGIC_64 || h.cputype!=CPU_TYPE_ARM64 || (h.filetype!=MH_EXECUTE && h.filetype!=MH_DYLIB) ||
       h.sizeofcmds>65536 || h.sizeofcmds>file_size-sizeof h || h.ncmds>h.sizeofcmds/8)return 0;
    unsigned char *commands=malloc(h.sizeofcmds);
    if(!commands)return 0;
    int valid=0;unsigned found=0,data_found=0,signatures=0;size_t cursor=0;
    struct section_64 text={0},data={0};
    if(pread(fd,commands,h.sizeofcmds,sizeof h)!=(ssize_t)h.sizeofcmds)goto done;
    for(unsigned i=0;i<h.ncmds;i++) {
        struct load_command lc;
        if(h.sizeofcmds-cursor<sizeof lc)goto done;
        memcpy(&lc,commands+cursor,sizeof lc);
        if(lc.cmdsize<8 || lc.cmdsize%8 || lc.cmdsize>h.sizeofcmds-cursor)goto done;
        if(lc.cmd==LC_CODE_SIGNATURE) {
            if(lc.cmdsize<sizeof *signature)goto done;
            memcpy(signature,commands+cursor,sizeof *signature);signatures++;
        }
        if(lc.cmd==LC_SEGMENT_64) {
            struct segment_command_64 segment;
            if(lc.cmdsize<sizeof segment)goto done;
            memcpy(&segment,commands+cursor,sizeof segment);
            if(segment.nsects>(lc.cmdsize-sizeof segment)/sizeof(struct section_64))goto done;
            int is_text=!strncmp(segment.segname,name,16),is_data=!strncmp(segment.segname,"__DATA",16);
            if(is_text || is_data)for(unsigned j=0;j<segment.nsects;j++) {
                struct section_64 section;memcpy(&section,commands+cursor+sizeof segment+j*sizeof section,sizeof section);
                if(strncmp(section.sectname,"__guest",16))continue;
                int protection=is_text?(VM_PROT_READ|VM_PROT_EXECUTE):(VM_PROT_READ|VM_PROT_WRITE);
                if(segment.initprot!=protection || (segment.maxprot&protection)!=protection ||
                   section.offset<segment.fileoff || section.offset-segment.fileoff>segment.filesize ||
                   section.size>segment.filesize-(section.offset-segment.fileoff) ||
                   section.offset>file_size || section.size>file_size-section.offset)goto done;
                if(section.addr<segment.vmaddr || section.addr-segment.vmaddr!=section.offset-segment.fileoff)goto done;
                if(is_text){text=section;*offset=section.offset;found++;}
                else {data=section;data_found++;}
            }
        }
        cursor+=lc.cmdsize;
    }
    valid=cursor==h.sizeofcmds && found==1 && data_found==1 && signatures==1 && signature->datasize &&
          text.size<=UINT64_MAX-text.addr && text.size<=UINT64_MAX-text.offset &&
          data.addr==text.addr+text.size && data.offset==text.offset+text.size &&
          text.size<=*size && data.size>=*size-text.size && data.size<=SIZE_MAX-text.size &&
          signature->dataoff<=file_size && signature->datasize<=file_size-signature->dataoff &&
          *offset<=signature->dataoff && text.size+data.size<=signature->dataoff-*offset;
    if(valid){*text_size=text.size;*capacity=(size_t)(text.size+data.size);}
done:
    free(commands);return valid;
}
static void release_mapping(Image *im) {
    if(im->resident) {
        // Restore original file layout after moving data for virtual BSS gaps.
        // dyld's executable mapping is never remapped or made writable.
        size_t start=im->resident_text_size;
        if(!mprotect(im->base+start,im->resident_capacity-start,PROT_READ|PROT_WRITE)) {
            memcpy(im->base+start,im->file+start,im->file_size-start);
            memset(im->base+im->file_size,0,im->resident_capacity-im->file_size);
        }
        close(im->resident_fd);
    } else if(im->base!=MAP_FAILED)munmap(im->base,(size_t)im->span);
}
static Image *image_map(const char *path, const char *section, void *resident, size_t guest_size, MPServices services, struct MPGroup *group, char error[256]) {
    if(error)error[0]=0;
    Image *image=calloc(1,sizeof *image);
    if(!image){if(error)snprintf(error,256,"out of memory");return NULL;}
    Image im={.low=UINT64_MAX,.base=MAP_FAILED,.services=services};
    size_t limit=services.extensions && services.extensions->max_image_bytes?
        services.extensions->max_image_bytes:MAX_IMAGE;
    if(limit>512u*1024u*1024u) {fail(&im,"image size policy exceeds 512 MiB ceiling");goto invalid;}
    if(mp_fixup_limit(&im)>1048576) {fail(&im,"fixup policy exceeds 1048576 ceiling");goto invalid;}
    if(!path) {fail(&im,"missing guest path");goto invalid;}
    int fd=open(path,O_RDONLY);
    if(fd<0) { snprintf(im.error,sizeof im.error,"open: %s",strerror(errno));goto invalid; }
    struct stat st;
    if(fstat(fd,&st) || st.st_size<(off_t)sizeof(struct mach_header_64) || (uint64_t)st.st_size>limit) {
        fail(&im,"invalid or oversized fixture file");goto done;
    }
    uint64_t source_offset=0,resident_text_size=0;size_t resident_capacity=0;
    struct linkedit_data_command container_signature={0};
    im.file_size=(size_t)st.st_size;
    long page=sysconf(_SC_PAGESIZE);
    if(page<=0) { fail(&im,"cannot determine host page size");goto done; }
    if(section)im.file_size=guest_size;
    if(section && (!embedded_source(fd,(size_t)st.st_size,section,&source_offset,&im.file_size,&resident_text_size,&resident_capacity,&container_signature) ||
                   source_offset%page || resident_text_size%page || resident_capacity>limit || im.file_size<sizeof(struct mach_header_64))) {
        fail(&im,"invalid embedded guest section");goto done;
    }
    im.file=mmap(NULL,im.file_size,PROT_READ,MAP_PRIVATE,fd,(off_t)source_offset);
    if(im.file==MAP_FAILED) { im.file=NULL;fail(&im,"cannot map fixture for inspection");goto done; }
    struct mach_header_64 h;memcpy(&h,im.file,sizeof h);
    int dylibs=group && services.extensions && services.extensions->allow_guest_dylibs;
    if(h.magic!=MH_MAGIC_64 || h.cputype!=CPU_TYPE_ARM64 || h.cpusubtype!=CPU_SUBTYPE_ARM64_ALL || (h.filetype!=MH_EXECUTE && !(dylibs && h.filetype==MH_DYLIB))) {
        fail(&im,dylibs?"requires thin ordinary ARM64 MH_EXECUTE or MH_DYLIB":"requires thin ordinary ARM64 MH_EXECUTE");goto done;
    }
    im.dylib=h.filetype==MH_DYLIB;
    if(!range(&im,sizeof h,h.sizeofcmds) || h.ncmds>h.sizeofcmds/8) { fail(&im,"bad load command region");goto done; }
    struct dyld_info_command dyld={0};
    struct linkedit_data_command signature={0},chains={0};
    unsigned chainsCount=0;
    unsigned signatureCount=0;
    uint64_t entryoff=UINT64_MAX,high=0,textStart=0,textEnd=0,textVM=UINT64_MAX;
    unsigned platform=0,mainCount=0,dyldCount=0,platformCount=0,idCount=0;
    size_t cursor=sizeof h,commandEnd=cursor+h.sizeofcmds;
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
            if((s.maxprot & ~7) || (s.initprot & ~s.maxprot) || (s.initprot & ~7) || !(s.initprot & VM_PROT_READ) || s.vmaddr%page || s.vmsize%page || s.fileoff%page || s.filesize>s.vmsize || s.vmsize>limit || s.vmaddr>UINT64_MAX-s.vmsize || !range(&im,s.fileoff,s.filesize)) {
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
                if(t==S_MOD_TERM_FUNC_POINTERS || t==S_THREAD_LOCAL_INIT_FUNCTION_POINTERS ||
                   (t>=S_THREAD_LOCAL_REGULAR && t<=S_THREAD_LOCAL_VARIABLE_POINTERS &&
                    !(services.extensions && services.extensions->allow_thread_locals))) {
                    fail(&im,"TLS/terminators unsupported");goto done;
                }
                if(section.addr<s.vmaddr || section.addr-s.vmaddr>s.vmsize || section.size>s.vmsize-(section.addr-s.vmaddr)) {fail(&im,"section outside segment");goto done;}
                if((!strncmp(section.sectname,"__objc_classlist",16) && !(services.extensions && services.extensions->allow_class_metadata)) || (!strncmp(section.sectname,"__objc_catlist",16) && !(services.extensions && services.extensions->allow_categories)) || !strncmp(section.sectname,"__objc_nlclslist",16) || !strncmp(section.sectname,"__objc_nlcatlist",16)) {fail(&im,"guest Objective-C class/category registration unsupported");goto done;}
                if((!strncmp(section.sectname,"__objc_selrefs",16) || t==S_MOD_INIT_FUNC_POINTERS) && (!(s.initprot&VM_PROT_WRITE) || section.addr%8)) {fail(&im,"metadata pointer section not writable/aligned");goto done;}
                if(im.section_count==MAX_SECTIONS) {fail(&im,"section limit");goto done;}
                im.sections[im.section_count++]=section;
                if(!strncmp(s.segname,"__TEXT",16) && !strncmp(section.sectname,"__text",16)) {
                    if(!(s.initprot&VM_PROT_EXECUTE) || section.offset>s.filesize || section.size>s.filesize-section.offset) { fail(&im,"invalid text section");goto done; }
                    textStart=section.offset;textEnd=textStart+section.size;textVM=s.vmaddr;
                }
            }
            break;
        }
        case LC_RPATH: {
            READ_COMMAND(struct rpath_command,r);
            if(!services.extensions){fail(&im,"unknown required command");goto done;}
            if(r.path.offset<sizeof r || r.path.offset>=lc.cmdsize || !memchr(im.file+cursor+r.path.offset,0,lc.cmdsize-r.path.offset)) {fail(&im,"invalid rpath string");goto done;}
            // Extended hosts currently admit absolute whitelisted dependencies;
            // no @rpath lookup is inferred from merely accepting this metadata.
            break;
        }
        case LC_BUILD_VERSION: { READ_COMMAND(struct build_version_command,b);platform=b.platform;platformCount++;break; }
        case LC_SYMTAB: { READ_COMMAND(struct symtab_command,t);im.symtab=t;break; }
        case LC_MAIN: { READ_COMMAND(struct entry_point_command,e);entryoff=e.entryoff;mainCount++;break; }
        case LC_CODE_SIGNATURE: { READ_COMMAND(struct linkedit_data_command,c);signature=c;signatureCount++;break; }
        case LC_DYLD_INFO_ONLY: { READ_COMMAND(struct dyld_info_command,d);dyld=d;dyldCount++;break; }
        case LC_LOAD_WEAK_DYLIB:
            if(!(services.extensions && services.extensions->allow_weak_imports)){fail(&im,"unsupported load command (chains/weak/encryption)");goto done;}
            /* fall through */
        case LC_LOAD_DYLIB: {
            READ_COMMAND(struct dylib_command,d);
            if(d.dylib.name.offset<sizeof d || d.dylib.name.offset>=lc.cmdsize) { fail(&im,"bad dylib name");goto done; }
            const char *name=(const char *)im.file+cursor+d.dylib.name.offset;
            if(!memchr(name,0,lc.cmdsize-d.dylib.name.offset) || im.library_count==MAX_LIBRARIES) {fail(&im,"bad or excessive libraries");goto done;}
            // Group members may name each other by @-relative install names;
            // linking later requires each such name to resolve to a member.
            if(!mp_library_allowed(name) && !(services.extensions && services.extensions->library_allowed && services.extensions->library_allowed(name)) && !(group && name[0]=='@')) {snprintf(im.error,sizeof im.error,"dependency outside framework whitelist: %s",name);goto done;}
            im.libraries[im.library_count++]=name;break;
        }
        case LC_ID_DYLIB: {
            READ_COMMAND(struct dylib_command,d);
            if(d.dylib.name.offset<sizeof d || d.dylib.name.offset>=lc.cmdsize || !memchr(im.file+cursor+d.dylib.name.offset,0,lc.cmdsize-d.dylib.name.offset)) {fail(&im,"bad dylib install name");goto done;}
            im.install_name=(const char *)im.file+cursor+d.dylib.name.offset;idCount++;break;
        }
        case LC_DYLD_CHAINED_FIXUPS: {
            if(!(services.extensions && services.extensions->allow_chained_fixups)){fail(&im,"unsupported load command (chains/weak/encryption)");goto done;}
            READ_COMMAND(struct linkedit_data_command,c);chains=c;chainsCount++;break;
        }
        case LC_DYLD_EXPORTS_TRIE: {READ_COMMAND(struct linkedit_data_command,t);im.exports_trie=t;break;}
        case LC_ENCRYPTION_INFO_64: {
            // A cryptid of 0 only records that the image is NOT encrypted
            // (Bink in Cyberpunk 2077); encrypted images stay unsupported.
            READ_COMMAND(struct encryption_info_command_64,e);
            if(e.cryptid){fail(&im,"encrypted image unsupported");goto done;}
            break;
        }
        case LC_REEXPORT_DYLIB: case LC_LOAD_UPWARD_DYLIB:
        case LC_ENCRYPTION_INFO:
            fail(&im,"unsupported load command (chains/weak/encryption)");goto done;
        default: if(lc.cmd&LC_REQ_DYLD){fail(&im,"unknown required command");goto done;} break;
        }
#undef READ_COMMAND
        cursor+=lc.cmdsize;
    }
    if(dyld.weak_bind_size && !(services.extensions && services.extensions->allow_weak_coalescing)) {
        fail(&im,"weak-definition coalescing unsupported");goto done;
    }
    int entryValid=im.dylib?(mainCount==0 && idCount==1):(mainCount==1 && idCount==0 && !(entryoff%4) && entryoff>=textStart && entryoff<textEnd);
    if(cursor!=commandEnd || textVM!=im.low || platform!=PLATFORM_MACOS || platformCount!=1 || !entryValid || dyldCount+chainsCount!=1 || high<=im.low || high-im.low>limit) {
        fail(&im,"image does not match supported macOS executable contract");goto done;
    }
    if(!range(&im,im.symtab.symoff,(uint64_t)im.symtab.nsyms*sizeof(struct nlist_64)) || !range(&im,im.symtab.stroff,im.symtab.strsize)) {fail(&im,"bad symbol table bounds");goto done;}
    if(signatureCount!=1 || !signature.datasize || !range(&im,signature.dataoff,signature.datasize)) {
        fail(&im,"requires existing embedded code signature");goto done;
    }
    // A freshly copied signed file may lack the kernel's cached signature state.
    // Register its EXISTING on-disk signature and honor the kernel's LV decision,
    // as dyld does. Neither signature bytes nor host security policy are changed.
    // Embedded mode admits the iOS container; the nested macOS signature is
    // preserved as evidence. dyld has already mapped the container's RX/RW pages.
    struct linkedit_data_command admission=section?container_signature:signature;
    fsignatures_t siginfo={.fs_file_start=0,.fs_blob_start=(void *)(uintptr_t)admission.dataoff,.fs_blob_size=admission.datasize};
    if(fcntl(fd,F_ADDFILESIGS_RETURN,&siginfo)<0) {
        int code=errno;
        snprintf(im.error,sizeof im.error,"signature registration: %s (errno=%d)",strerror(code),code);goto done;
    }
    if(siginfo.fs_file_start<(off_t)admission.dataoff) { fail(&im,"signature does not cover the image");goto done; }
    im.stats.signature_registered=1;
    char lv_message[160]={0};
    fchecklv_t check={.lv_file_start=0,.lv_error_message_size=sizeof lv_message,.lv_error_message=lv_message};
    if(fcntl(fd,F_CHECK_LV,&check)<0) {
        snprintf(im.error,sizeof im.error,"library validation: %s (%s)",lv_message,strerror(errno));goto done;
    }
    im.stats.library_validation_passed=1;
    im.span=high-im.low;
    if(resident) {
        for(Image *other=resident_images;other;other=other->next_resident)if(other->base==resident) {
            fail(&im,"resident guest already active");goto done;
        }
        resident_capacity=(resident_capacity+page-1)/(size_t)page*(size_t)page;
        if((uintptr_t)resident%page || im.span>resident_capacity) {
            fail(&im,"invalid resident guest range");goto done;
        }
        for(unsigned i=0;i<im.count;i++) {
            struct segment_command_64 *s=&im.segments[i];
            if(!strncmp(s->segname,"__PAGEZERO",16))continue;
            if(((s->initprot&VM_PROT_EXECUTE) && (s->vmaddr!=im.low || s->fileoff || s->filesize!=resident_text_size)) ||
               (!(s->initprot&VM_PROT_EXECUTE) && (s->vmaddr-im.low<resident_text_size ||
                 s->vmaddr-im.low>resident_capacity || s->vmsize>resident_capacity-(s->vmaddr-im.low)))) {
                fail(&im,"resident segment layout unsupported");goto done;
            }
        }
        im.resident_fd=dup(fd);
        if(im.resident_fd<0){fail(&im,"cannot retain resident backing file");goto done;}
        im.resident=1;im.source_offset=source_offset;im.base=resident;
        im.resident_capacity=resident_capacity;im.resident_text_size=(size_t)resident_text_size;
    } else im.base=mmap(NULL,(size_t)im.span,PROT_NONE,MAP_PRIVATE|MAP_ANON,-1,0);
    if(im.base==MAP_FAILED) { fail(&im,"cannot reserve image address range");goto done; }
    for(unsigned i=0;i<im.count;++i) {
        struct segment_command_64 *s=&im.segments[i];
        if(!strncmp(s->segname,"__PAGEZERO",16) || !s->vmsize)continue;
        unsigned char *address=im.base+(s->vmaddr-im.low);
        if(im.resident) {
            if(s->initprot&VM_PROT_EXECUTE)continue;
            if(mprotect(address,(size_t)s->vmsize,PROT_READ|PROT_WRITE)) {
                snprintf(im.error,sizeof im.error,"resident data protection: %s (errno=%d)",strerror(errno),errno);goto done;
            }
            memcpy(address,im.file+s->fileoff,(size_t)s->filesize);
            memset(address+s->filesize,0,(size_t)(s->vmsize-s->filesize));im.stats.segments++;continue;
        }
        size_t filePages=(size_t)((s->filesize+page-1)/page*page);
        // Executable pages come directly from the signed file, never a RWX buffer.
        if(filePages && mmap(address,filePages,s->initprot,MAP_PRIVATE|MAP_FIXED,fd,(off_t)(source_offset+s->fileoff))==MAP_FAILED) {
            snprintf(im.error,sizeof im.error,"map %.16s prot=%d: %s",s->segname,s->initprot,strerror(errno));goto done;
        }
        if(s->vmsize>filePages && mmap(address+filePages,(size_t)s->vmsize-filePages,s->initprot,MAP_PRIVATE|MAP_ANON|MAP_FIXED,-1,0)==MAP_FAILED) {
            fail(&im,"cannot map zero-fill tail");goto done;
        }
        im.stats.segments++;
    }
    im.dyld=dyld;im.chains=chains;im.chains_count=chainsCount;im.entryoff=entryoff;im.group=group;
    *image=im;
    close(fd);
    return image;
done:
    if(!mp_release_tls(&im)) {
        // A constructor may have published TLS/destructors before a later
        // constructor failed. Keep their code and template alive until exit.
        *image=im;image->pinned=1;
        if(error)snprintf(error,256,"%s",im.error);
        close(fd);return NULL;
    }
    release_mapping(&im);
    if(im.file)munmap((void *)im.file,im.file_size);
    close(fd);
invalid:
    if(error)snprintf(error,256,"%s",im.error);
    free(image);
    return NULL;
}

// Phase 2: fixups, TLS and selectors, then constant-data protection. Group
// members bind against each other's immutable symbol tables, so the order in
// which members are linked does not matter.
static int image_link(Image *im) {
    struct dyld_info_command *d=&im->dyld;
    if((im->chains_count && !mp_apply_chains(im,im->chains.dataoff,im->chains.datasize)) ||
       !mp_apply_rebase(im,d->rebase_off,d->rebase_size) ||
       !mp_apply_bind(im,d->bind_off,d->bind_size,0) ||
       !mp_apply_bind(im,d->weak_bind_off,d->weak_bind_size,2) ||
       !mp_apply_bind(im,d->lazy_bind_off,d->lazy_bind_size,1))return 0;
    if(!mp_prepare_tls(im) || !mp_prepare_objc(im))return 0;
    for(unsigned i=0;i<im->count;++i) {
        struct segment_command_64 *s=&im->segments[i];
        if((!strncmp(s->segname,"__DATA_CONST",16) || (im->resident && !(s->initprot&VM_PROT_WRITE) && !(s->initprot&VM_PROT_EXECUTE) && s->initprot)) && mprotect(im->base+(s->vmaddr-im->low),(size_t)s->vmsize,PROT_READ))return fail(im,"cannot protect constant data");
    }
    if(!im->dylib)im->entry=(uintptr_t)im->base+im->entryoff;
    mp_register_unwind_image(im);
    return 1;
}
// Phase 3: initializers, then the image counts as live.
static int image_start(Image *im) {
    if(!mp_initialize(im))return 0;
    if(im->resident){im->next_resident=resident_images;resident_images=im;}
    live_images++;return 1;
}
// Undo a mapped image that never started. TLS published by a constructor
// keeps the image pinned for process lifetime instead of dangling.
static void image_discard(Image *im) {
    if(!mp_release_tls(im)){im->pinned=1;return;}
    mp_unregister_unwind_image(im);
    release_mapping(im);if(im->file)munmap((void *)im->file,im->file_size);
    free(im);
}
static MPImage *image_open(const char *path, const char *section, void *resident, size_t guest_size, MPServices services, char error[256]) {
    Image *im=image_map(path,section,resident,guest_size,services,NULL,error);
    if(!im)return NULL;
    if(!image_link(im) || !image_start(im)) {
        if(error)snprintf(error,256,"%s",im->error);
        image_discard(im);return NULL;
    }
    return im;
}
MPImage *mp_image_open(const char *path, MPServices services, char error[256]) {
    return image_open(path,NULL,NULL,0,services,error);
}
MPImage *mp_image_open_embedded(const char *path, const char *section, void *resident, size_t size, MPServices services, char error[256]) {
    if(!section || !resident){if(error)snprintf(error,256,"missing embedded section/address");return NULL;}
    return image_open(path,section,resident,size,services,error);
}

void *mp_image_symbol(MPImage *im,const char *name) {
    if(!im || !name)return NULL;
    int weak;void *p=mp_export(im,name,&weak);
    if(!p && !im->error[0])fail(im,"export not found");
    return p;
}
int mp_image_main(MPImage *im,int argc,char **argv,int *result) {
    if(!im || !result || argc<0 || (argc && !argv))return -1;
    Image *previous=mp_active;mp_active=im;
    int (*entry)(int,char **);memcpy(&entry,&im->entry,sizeof entry);
    *result=entry(argc,argv);
    mp_active=previous;return 0;
}
void mp_image_close(MPImage *im) {
    if(!im || im->pinned)return;
    if(!mp_release_tls(im)){im->pinned=1;return;}
    if(im->resident) {
        Image **link=&resident_images;
        while(*link && *link!=im)link=&(*link)->next_resident;
        if(*link)*link=im->next_resident;
    }
    mp_unregister_unwind_image(im);
    release_mapping(im);munmap((void *)im->file,im->file_size);
    free(im);live_images--;
}
MPStats mp_image_stats(const MPImage *im) {return im?im->stats:(MPStats){0};}
const char *mp_image_error(const MPImage *im) {return im?im->error:"no image";}
size_t mp_live_images(void) {return live_images;}

void mp_image_pin(MPImage *im) {if(im)im->pinned=1;}
void *mp_image_section(MPImage *im,const char *name,size_t *size) {
    if(size)*size=0;if(!im || !name || !size)return NULL;
    for(unsigned i=0;i<im->section_count;i++) {
        struct section_64 *s=&im->sections[i];
        if(!strncmp(s->sectname,name,16)) {
            if(s->addr<im->low || s->addr-im->low>im->span || s->size>im->span-(s->addr-im->low))return NULL;
            *size=(size_t)s->size;return im->base+(s->addr-im->low);
        }
    }
    return NULL;
}

const char *mp_image_install_name(const MPImage *im) {return im?im->install_name:NULL;}
// ---- Groups ---------------------------------------------------------------
unsigned mp_group_count(const MPGroup *g) {return g?g->count:0;}
MPImage *mp_group_image(MPGroup *g,unsigned i) {return g && i<g->count?g->images[i]:NULL;}
// Guest address ranges for crash reports (read from a signal handler).
static struct Located {uintptr_t base;uint64_t span;const char *name;} locate[MAX_GROUP];static unsigned located;
uintptr_t mp_guest_base(unsigned i){return i<located?locate[i].base:0;} // Group member i (0: main executable).
const char *mp_locate(uintptr_t address,uintptr_t *offset) {
    for(unsigned i=0;i<located;i++)if(address-locate[i].base<locate[i].span){*offset=address-locate[i].base;return locate[i].name;}
    return NULL;
}
static const char *base_name(const char *path) {const char *slash=strrchr(path,'/');return slash?slash+1:path;}
Image *mp_group_find(struct MPGroup *g,const char *name) {
    if(!g || !name)return NULL;
    for(unsigned i=0;i<g->count;i++)if(g->images[i]->install_name && !strcmp(g->images[i]->install_name,name))return g->images[i];
    // @executable_path/@loader_path/@rpath spellings differ between the
    // importer and the dylib's own ID (SDL dlopens @executable_path/../libs/
    // libMoltenVK.dylib whose ID is @rpath/libMoltenVK.dylib). Match those by
    // file name; absolute paths never match a guest.
    if(name[0]!='@')return NULL;
    for(unsigned i=1;i<g->count;i++) {
        const char *id=g->images[i]->install_name;
        if(id && !strcmp(base_name(id),base_name(name)))return g->images[i];
    }
    return NULL;
}
static int visit(Image *im,unsigned char *state,struct MPGroup *g,char error[256]) {
    unsigned index=0;while(g->images[index]!=im)index++;
    if(state[index]==2)return 1;
    if(state[index]==1)return 1; // Cycle: dyld also tolerates these; already in progress.
    state[index]=1;
    for(unsigned i=0;i<im->library_count;i++)if(im->dependencies[i] && !visit(im->dependencies[i],state,g,error))return 0;
    LOAD_TRACE("start %s",base_name(im->install_name?im->install_name:"main"));
    if(!image_start(im)){snprintf(error,256,"%s: %s",base_name(im->install_name?im->install_name:"main"),im->error);return 0;}
    state[index]=2;return 1;
}
MPGroup *mp_group_open(const MPGuestSource *sources,unsigned count,MPServices services,char error[256]) {
    if(error)error[0]=0;LOAD_TRACE("group of %u",count);
    if(!sources || !count || count>MAX_GROUP){if(error)snprintf(error,256,"group needs 1..%d members",MAX_GROUP);return NULL;}
    struct MPGroup *g=calloc(1,sizeof *g);
    if(!g){if(error)snprintf(error,256,"out of memory");return NULL;}
    char local[256];
    for(unsigned i=0;i<count;i++) {
        const MPGuestSource *s=&sources[i];
        Image *im=s->section?image_map(s->path,s->section,s->resident,s->size,services,g,local):image_map(s->path,NULL,NULL,0,services,g,local);
        if(!im){if(error)snprintf(error,256,"%s: %s",base_name(s->path),local);goto fail;}
        if((i==0)==im->dylib){if(error)snprintf(error,256,"%s: member 0 must be the executable, others dylibs",base_name(s->path));image_discard(im);goto fail;}
        g->images[g->count++]=im;LOAD_TRACE("mapped %s base=%p span=0x%llx",base_name(s->path),(void *)im->base,(unsigned long long)im->span);
        if(located<MAX_GROUP)locate[located++]=(struct Located){(uintptr_t)im->base,im->span,base_name(s->path)};
    }
    for(unsigned i=0;i<g->count;i++) {
        Image *im=g->images[i];
        for(unsigned j=0;j<im->library_count;j++) {
            im->dependencies[j]=mp_group_find(g,im->libraries[j]);
            if(!im->dependencies[j] && im->libraries[j][0]=='@') {
                if(error)snprintf(error,256,"%s: guest dependency not provided: %s",base_name(sources[i].path),im->libraries[j]);
                goto fail;
            }
        }
    }
    for(unsigned i=0;i<g->count;i++)if((trace_load>0?fprintf(stderr,"[load] link %u\n",i):0),!image_link(g->images[i])) {
        if(error)snprintf(error,256,"%s: %s",base_name(sources[i].path),g->images[i]->error);goto fail;
    }
    if(services.extensions && services.extensions->unresolved){if(error)snprintf(error,256,"import probe complete (no guest code ran)");goto fail;}
    LOAD_TRACE("linked all");
    mp_group_activate(g); // Initializers may already dlopen/dlsym members.
    if(services.extensions && services.extensions->register_metadata)
        for(unsigned i=g->count;i-->0;)if(!services.extensions->register_metadata(g->images[i],local)) {
            if(error)snprintf(error,256,"%s: metadata: %s",base_name(sources[i].path),local);goto fail;
        }
    {
        unsigned char state[MAX_GROUP]={0};
        // Every dylib (with its dependencies first) starts before the main
        // executable. Members nothing links, such as a dlopened MoltenVK,
        // start here too: before guest entry, not lazily at dlopen.
        for(unsigned i=1;i<g->count;i++)if(!visit(g->images[i],state,g,error))goto fail;
        if(!visit(g->images[0],state,g,error))goto fail;
    }
    return g;
fail:
    // Members may already have run constructors or published metadata;
    // keep every mapping for process lifetime rather than unmapping live code.
    for(unsigned i=0;i<g->count;i++)g->images[i]->pinned=1;
    return NULL;
}
