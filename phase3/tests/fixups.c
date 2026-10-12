/* Synthetic streams exercise the exact legacy opcodes emitted for AppKit.
 * No executable mappings or signing exemptions are needed for parser tests. */
#include "internal.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static uintptr_t storage[16];
static int token;
static int missing;
int mp_fail(Image *im,const char *s) { snprintf(im->error,sizeof im->error,"%s",s);return 0; }
void *mp_resolve_weak(Image *im,const char *name) {(void)im;assert(!strcmp(name,"_symbol"));return &token;}
void *mp_resolve(Image *im,const char *lib,const char *name) {
    if(missing){mp_fail(im,"missing import");return NULL;}
    (void)im;assert(!strcmp(lib,"test"));assert(!strcmp(name,"_symbol"));return &token;
}
static void *lazy_target(const char *library,const char *symbol) {
    assert(!strcmp(library,"test") && !strcmp(symbol,"_symbol"));return &token;
}
static Image fixture(const unsigned char *stream,size_t size) {
    for(unsigned i=0;i<16;i++)storage[i]=0x1000+i*8;
    Image im={.file=stream,.file_size=size,.count=1,.low=0x1000,.span=sizeof storage,
        .base=(unsigned char *)storage,.library_count=1,.libraries={"test"}};
    im.segments[0]=(struct segment_command_64){.vmaddr=0x1000,.vmsize=sizeof storage,.initprot=VM_PROT_READ|VM_PROT_WRITE};
    return im;
}
static void rebase_ok(void) {
    unsigned char stream[]={0x11,0x20,0,0x80,2,8,0x70,8,0x41,0x51,0};
    Image im=fixture(stream,sizeof stream);assert(mp_apply_rebase(&im,0,sizeof stream));
    assert(im.stats.rebases==4);
    for(unsigned i=0;i<16;i++)assert(storage[i]==((i==0||i==2||i==4||i==7)?(uintptr_t)storage+i*8:0x1000+i*8));
}
static void bind_ok(void) {
    unsigned char stream[]={0x11,0x40,'_','s','y','m','b','o','l',0,0x70,0,0xc0,3,8,0};
    Image im=fixture(stream,sizeof stream);assert(mp_apply_bind(&im,0,sizeof stream,0));
    assert(im.stats.binds==3);
    for(unsigned i=0;i<16;i++)assert(storage[i]==((i==0||i==2||i==4)?(uintptr_t)&token:0x1000+i*8));
}
static void extended_opcodes(void) {
    unsigned char rebase[]={0x11,0x20,0,0x30,16,0x51,0};
    Image im=fixture(rebase,sizeof rebase);
    assert(mp_apply_rebase(&im,0,sizeof rebase));
    assert(im.stats.rebases==1 && storage[2]==(uintptr_t)storage+16);
    unsigned char binds[]={0x20,1,0x40,'_','s','y','m','b','o','l',0,0x70,0,0xa0,8,0xb1,0x90,0};
    im=fixture(binds,sizeof binds);assert(mp_apply_bind(&im,0,sizeof binds,0));
    assert(im.stats.binds==3);
    for(unsigned i=0;i<16;i++)assert(storage[i]==((i==0||i==2||i==4)?(uintptr_t)&token:0x1000+i*8));
    unsigned char weak[]={0x11,0x41,'_','s','y','m','b','o','l',0,0x70,0,0x90,0};
    im=fixture(weak,sizeof weak);assert(!mp_apply_bind(&im,0,sizeof weak,0));
    MPExtensions extension={.allow_weak_imports=1};
    im=fixture(weak,sizeof weak);im.services.extensions=&extension;missing=1;
    assert(mp_apply_bind(&im,0,sizeof weak,0));assert(storage[0]==0 && !im.error[0]);
    weak[1]=0x40;im=fixture(weak,sizeof weak);im.services.extensions=&extension;
    assert(!mp_apply_bind(&im,0,sizeof weak,0));assert(strstr(im.error,"missing import"));missing=0;
    unsigned char badOrdinal[]={0x20,65,0x40,'_','s','y','m','b','o','l',0,0x70,0,0x90,0};
    im=fixture(badOrdinal,sizeof badOrdinal);assert(!mp_apply_bind(&im,0,sizeof badOrdinal,0));
    unsigned char truncated[]={0x11,0x20,0,0x30,0x80};
    im=fixture(truncated,sizeof truncated);assert(!mp_apply_rebase(&im,0,sizeof truncated));
}
static void chained(void) {
    unsigned char file[8192]={0};uintptr_t memory[512]={0};
    // One 4K writable page, one rebase followed by an imported pointer + 3.
    uint32_t header[]={0,32,64,68,1,1,0};memcpy(file+4096,header,sizeof header);
    uint32_t starts[]={1,8};memcpy(file+4096+32,starts,sizeof starts);
    uint32_t bytes=24;uint16_t page=4096,format=6,pages=1,start=0;
    memcpy(file+4096+40,&bytes,4);memcpy(file+4096+44,&page,2);memcpy(file+4096+46,&format,2);memcpy(file+4096+60,&pages,2);memcpy(file+4096+62,&start,2);
    file[4096+64]=1;memcpy(file+4096+68,"_symbol",8);
    uint64_t first=16ULL|(2ULL<<51),second=(1ULL<<63)|(3ULL<<24);memcpy(file,&first,8);memcpy(file+8,&second,8);
    Image im={.file=file,.file_size=sizeof file,.count=1,.low=0x1000,.span=sizeof memory,.base=(unsigned char *)memory,.library_count=1,.libraries={"test"}};
    im.segments[0]=(struct segment_command_64){.vmaddr=0x1000,.vmsize=4096,.filesize=4096,.initprot=VM_PROT_READ|VM_PROT_WRITE};
    assert(mp_apply_chains(&im,4096,80));assert(memory[0]==(uintptr_t)memory+16);assert(memory[1]==(uintptr_t)&token+3);assert(im.stats.binds==1 && im.stats.rebases==1);
    first|=0x80ULL<<36;memcpy(file,&first,8);
    assert(mp_apply_chains(&im,4096,80));assert(memory[0]==((uintptr_t)memory+16+(0x80ULL<<56)));
    assert(!mp_apply_chains(&im,8190,80));
    file[4096+46]=1;assert(!mp_apply_chains(&im,4096,80));assert(strstr(im.error,"format"));file[4096+46]=6;
    uint16_t outside=4092;memcpy(file+4096+62,&outside,2);assert(!mp_apply_chains(&im,4096,80));assert(strstr(im.error,"crosses page"));memcpy(file+4096+62,&start,2);
    second|=1;memcpy(file+8,&second,8);assert(!mp_apply_chains(&im,4096,80));assert(strstr(im.error,"ordinal"));
}
static void negatives(void) {
    unsigned char oversized[]={0x11,0x20,0,0x80,0x81,0x40,0,0};
    Image im=fixture(oversized,sizeof oversized);assert(!mp_apply_rebase(&im,0,sizeof oversized));assert(strstr(im.error,"count limit"));
    unsigned char truncated[]={0x11,0x20,0,0x70,0x80};
    im=fixture(truncated,sizeof truncated);assert(!mp_apply_rebase(&im,0,sizeof truncated));assert(strstr(im.error,"truncated"));
    unsigned char misaligned[]={0x11,0x20,1,0x70,0,0};
    im=fixture(misaligned,sizeof misaligned);assert(!mp_apply_rebase(&im,0,sizeof misaligned));assert(strstr(im.error,"aligned"));
    unsigned char outside[]={0x11,0x20,120,0x80,2,0,0};
    im=fixture(outside,sizeof outside);assert(!mp_apply_rebase(&im,0,sizeof outside));assert(strstr(im.error,"aligned"));
    unsigned char overflow[]={0x11,0x20,0,0x70,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,1,0};
    im=fixture(overflow,sizeof overflow);assert(!mp_apply_rebase(&im,0,sizeof overflow));assert(strstr(im.error,"overflow"));
    unsigned char bind_count[]={0x11,0x40,'_','s','y','m','b','o','l',0,0x70,0,0xc0,0x81,0x40,0,0};
    im=fixture(bind_count,sizeof bind_count);assert(!mp_apply_bind(&im,0,sizeof bind_count,0));assert(strstr(im.error,"count limit"));
    unsigned char bind_overflow[]={0x11,0x40,'_','s','y','m','b','o','l',0,0x70,0,0xc0,1,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,1,0};
    im=fixture(bind_overflow,sizeof bind_overflow);assert(!mp_apply_bind(&im,0,sizeof bind_overflow,0));assert(strstr(im.error,"overflow"));
    unsigned char bind_truncated[]={0x11,0x40,'_','s','y','m','b','o','l',0,0x70,0,0xc0,1};
    im=fixture(bind_truncated,sizeof bind_truncated);assert(!mp_apply_bind(&im,0,sizeof bind_truncated,0));assert(strstr(im.error,"truncated"));
    unsigned char readonly[]={0x11,0x20,0,0x51,0};
    im=fixture(readonly,sizeof readonly);im.segments[0].initprot=VM_PROT_READ|VM_PROT_EXECUTE;
    assert(!mp_apply_rebase(&im,0,sizeof readonly));assert(strstr(im.error,"writable"));
}
static void large_game_cases(void) {
    unsigned char rebases[]={0x11,0x20,0,0x52,0};
    Image im=fixture(rebases,sizeof rebases);storage[0]|=0x80ULL<<56;
    assert(mp_apply_rebase(&im,0,sizeof rebases));
    assert(storage[0]==(uintptr_t)storage+(0x80ULL<<56));
    MPExtensions policy={.max_fixups=1};
    im=fixture(rebases,sizeof rebases);im.services.extensions=&policy;
    assert(!mp_apply_rebase(&im,0,sizeof rebases));assert(strstr(im.error,"limit"));
    policy.max_fixups=2;im=fixture(rebases,sizeof rebases);im.services.extensions=&policy;
    assert(mp_apply_rebase(&im,0,sizeof rebases));assert(im.stats.rebases==2);
    unsigned char binds[]={0x11,0x40,'_','s','y','m','b','o','l',0,0x70,0,0x60,8,0x90,0x60,0x78,0x90,0};
    im=fixture(binds,sizeof binds);assert(mp_apply_bind(&im,0,sizeof binds,0));
    assert(storage[0]==(uintptr_t)&token+8 && storage[1]==(uintptr_t)&token-8);
    unsigned char truncated[]={0x60,0x80};im=fixture(truncated,sizeof truncated);
    assert(!mp_apply_bind(&im,0,sizeof truncated,0));assert(strstr(im.error,"truncated"));
    unsigned char overflow[]={0x60,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,2};
    im=fixture(overflow,sizeof overflow);assert(!mp_apply_bind(&im,0,sizeof overflow,0));assert(strstr(im.error,"overflow"));
    unsigned char lazy[]={0x11,0x40,'_','s','y','m','b','o','l',0,0x70,0,0x90,0};
    policy.resolve_lazy=lazy_target;policy.max_fixups=8192;missing=1;
    im=fixture(lazy,sizeof lazy);im.services.extensions=&policy;
    assert(!mp_apply_bind(&im,0,sizeof lazy,0)); // Eager data never deferred.
    im=fixture(lazy,sizeof lazy);im.services.extensions=&policy;
    assert(mp_apply_bind(&im,0,sizeof lazy,1));assert(storage[0]==(uintptr_t)&token && !im.error[0]);missing=0;
    unsigned char weak[]={0x40,'_','s','y','m','b','o','l',0,0x70,0,0x90,0};
    im=fixture(weak,sizeof weak);assert(mp_apply_bind(&im,0,sizeof weak,2));assert(storage[0]==(uintptr_t)&token);
}
int main(void) {rebase_ok();bind_ok();extended_opcodes();chained();negatives();large_game_cases();puts("Fixup streams: positive and negative cases passed");}
