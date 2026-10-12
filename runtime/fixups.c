#include "internal.h"
#include <string.h>
#include <limits.h>
#include <stdio.h>
#define fail mp_fail
static int range(Image *im,uint64_t o,uint64_t n){return o<=im->file_size && n<=im->file_size-o;}
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
static int sleb(Image *im,const unsigned char **cursor,const unsigned char *end,int64_t *value) {
    uint64_t bits=0;
    for(unsigned i=0;i<10;i++) {
        if(*cursor==end)return fail(im,"truncated dyld SLEB128");
        unsigned char c=*(*cursor)++;
        if(i==9 && c!=0 && c!=0x7f)return fail(im,"overflowing dyld SLEB128");
        bits|=(uint64_t)(c&127)<<(i*7);
        if(!(c&128)) {
            unsigned shift=(i+1)*7;
            if((c&64) && shift<64)bits|=UINT64_MAX<<shift;
            memcpy(value,&bits,sizeof bits);return 1;
        }
    }
    return fail(im,"overflowing dyld SLEB128");
}
int mp_apply_rebase(Image *im, uint32_t offset, uint32_t size) {
    if (!range(im,offset,size)) return fail(im,"rebase stream outside file");
    if(!size)return 1;
    const unsigned char *p=im->file+offset,*end=p+size;
    unsigned segment=UINT_MAX, type=0;
    uint64_t address=0;
    while (p<end) {
        unsigned char byte=*p++,op=byte&REBASE_OPCODE_MASK,imm=byte&REBASE_IMMEDIATE_MASK;
        uint64_t count=0,skip=0;
        switch(op) {
        case REBASE_OPCODE_DONE:
            while(p<end) if(*p++) return fail(im,"nonzero rebase padding");
            return 1;
        case REBASE_OPCODE_SET_TYPE_IMM: type=imm; break;
        case REBASE_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB:
            segment=imm; if(!uleb(im,&p,end,&address))return 0; break;
        case REBASE_OPCODE_ADD_ADDR_ULEB:
            if(!uleb(im,&p,end,&skip))return 0;
            if(address>UINT64_MAX-skip)return fail(im,"rebase address overflow");
            address+=skip;break;
        case REBASE_OPCODE_ADD_ADDR_IMM_SCALED:
            skip=(uint64_t)imm*sizeof(uintptr_t);
            if(address>UINT64_MAX-skip)return fail(im,"rebase address overflow");
            address+=skip;break;
        case REBASE_OPCODE_DO_REBASE_ULEB_TIMES_SKIPPING_ULEB:
            if(!uleb(im,&p,end,&count) || !uleb(im,&p,end,&skip))return 0;
            goto rebase_many;
        case REBASE_OPCODE_DO_REBASE_ADD_ADDR_ULEB:
            count=1;if(!uleb(im,&p,end,&skip))return 0;
            goto rebase_many;
        case REBASE_OPCODE_DO_REBASE_ULEB_TIMES:
            if(!uleb(im,&p,end,&count))return 0;
            goto rebase_many;
        case REBASE_OPCODE_DO_REBASE_IMM_TIMES:
            count=imm;
        rebase_many:
            if(count>mp_fixup_limit(im))return fail(im,"rebase count limit");
            if(type!=REBASE_TYPE_POINTER)return fail(im,"unsupported rebase type");
            while(count--) {
                if(im->stats.rebases>=mp_fixup_limit(im))return fail(im,"rebase limit");
                uintptr_t *where=slot(im,segment,address); if(!where)return 0;
                // Legacy relocations also carry high-byte language/runtime tags.
                // Validate the address portion, then add slide without losing it.
                uintptr_t addressPart=*where & 0x00ffffffffffffffULL;
                if(addressPart<im->low || addressPart-im->low>=im->span) {
                    snprintf(im->error,sizeof im->error,"rebase target outside image: segment=%u offset=0x%llx target=0x%llx",segment,(unsigned long long)address,(unsigned long long)*where);return 0;
                }
                *where=(uintptr_t)im->base+(addressPart-im->low)+(*where&0xff00000000000000ULL);
                if(skip>UINT64_MAX-sizeof(uintptr_t) || address>UINT64_MAX-sizeof(uintptr_t)-skip)return fail(im,"rebase address overflow");
                im->stats.rebases++; address+=sizeof(uintptr_t)+skip;
            }
            break;
        default: return fail(im,"rebase opcode outside supported runtime subset");
        }
    }
    // dyld's loop is `while(!done && p<end)`: reaching the end is completion
    // (libmbedx509 in SuperTuxKart ends exactly at the boundary).
    return 1;
}
int mp_apply_bind(Image *im, uint32_t offset, uint32_t size, int lazy) {
    if (!range(im,offset,size)) return fail(im,"bind stream outside file");
    if(!size)return 1;
    const unsigned char *p=im->file+offset,*end=p+size;
    unsigned segment=UINT_MAX,type=BIND_TYPE_POINTER,ordinal=0;
    int special=0,special_ordinal=0; // BIND_OPCODE_SET_DYLIB_SPECIAL_IMM state.
    uint64_t address=0;
    int64_t addend=0;
    const char *symbol=NULL;
    int last_done=0,weak=0;
    while(p<end) {
        unsigned char byte=*p++,op=byte&BIND_OPCODE_MASK,imm=byte&BIND_IMMEDIATE_MASK;
        last_done=op==BIND_OPCODE_DONE;
        switch(op) {
        case BIND_OPCODE_DONE:
            if(lazy==1) { segment=UINT_MAX; address=0; ordinal=0; special=0; symbol=NULL; type=BIND_TYPE_POINTER; weak=0; addend=0; break; }
            while(p<end)if(*p++)return fail(im,"nonzero bind padding");
            return 1;
        case BIND_OPCODE_SET_DYLIB_ORDINAL_ULEB: {
            uint64_t value;if(!uleb(im,&p,end,&value) || value>UINT_MAX)return fail(im,"bad library ordinal");
            ordinal=(unsigned)value;special=0;break;
        }
        case BIND_OPCODE_SET_DYLIB_ORDINAL_IMM: ordinal=imm;special=0; break;
        case BIND_OPCODE_SET_DYLIB_SPECIAL_IMM:
            // dyld: 0 is self, otherwise a sign-extended negative ordinal.
            special=1;special_ordinal=imm?(int)(int8_t)(BIND_OPCODE_MASK|imm):0;
            if(special_ordinal<BIND_SPECIAL_DYLIB_WEAK_LOOKUP)return fail(im,"unknown special bind ordinal");
            break;
        case BIND_OPCODE_SET_TYPE_IMM: type=imm; break;
        case BIND_OPCODE_SET_ADDEND_SLEB:
            if(!sleb(im,&p,end,&addend))return 0;break;
        case BIND_OPCODE_SET_SYMBOL_TRAILING_FLAGS_IMM: {
            if(imm & ~(BIND_SYMBOL_FLAGS_WEAK_IMPORT | (lazy==2?BIND_SYMBOL_FLAGS_NON_WEAK_DEFINITION:0)))return fail(im,"unsupported symbol flags");
            weak=(imm&BIND_SYMBOL_FLAGS_WEAK_IMPORT)!=0;
            if(weak && !(im->services.extensions && im->services.extensions->allow_weak_imports))return fail(im,"unsupported symbol flags");
            const unsigned char *zero=memchr(p,0,(size_t)(end-p));
            if(!zero)return fail(im,"unterminated bind symbol");
            symbol=(const char *)p;p=zero+1;break;
        }
        case BIND_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB:
            segment=imm;if(!uleb(im,&p,end,&address))return 0;break;
        case BIND_OPCODE_ADD_ADDR_ULEB: {
            uint64_t delta;if(!uleb(im,&p,end,&delta))return 0;
            // Apple ld emits modulo-2^64 negative deltas here; validate the
            // resulting slot at DO_BIND rather than rejecting the encoding.
            address+=delta;break;
        }
        case BIND_OPCODE_DO_BIND:
        case BIND_OPCODE_DO_BIND_ADD_ADDR_ULEB:
        case BIND_OPCODE_DO_BIND_ADD_ADDR_IMM_SCALED:
        case BIND_OPCODE_DO_BIND_ULEB_TIMES_SKIPPING_ULEB: {
            uint64_t count=1,skip=0;
            if(op==BIND_OPCODE_DO_BIND_ULEB_TIMES_SKIPPING_ULEB &&
               (!uleb(im,&p,end,&count) || !uleb(im,&p,end,&skip)))return 0;
            if(op==BIND_OPCODE_DO_BIND_ADD_ADDR_ULEB && !uleb(im,&p,end,&skip))return 0;
            if(op==BIND_OPCODE_DO_BIND_ADD_ADDR_IMM_SCALED)skip=(uint64_t)imm*sizeof(uintptr_t);
            if(count>mp_fixup_limit(im))return fail(im,"bind count limit");
            if(type!=BIND_TYPE_POINTER || (lazy!=2 && !special && (ordinal==0 || ordinal>im->library_count)) || !symbol)return fail(im,"unsupported bind state");
            if(im->stats.binds>=mp_fixup_limit(im))return fail(im,"bind limit");
            void *target=lazy==2?mp_resolve_weak(im,symbol):special?mp_resolve_special(im,special_ordinal,symbol):mp_resolve(im,im->libraries[ordinal-1],symbol);
            if(!target && !weak && im->services.extensions && im->services.extensions->unresolved) {
                im->services.extensions->unresolved(im,lazy==2?"(weak coalescing)":special?"(special ordinal)":im->libraries[ordinal-1],symbol,lazy==1);
                im->error[0]=0;weak=1; // Probe only: the group never starts.
            }
            if(!target && !weak && !special && lazy==1 && im->services.extensions && im->services.extensions->resolve_lazy) {
                target=im->services.extensions->resolve_lazy(im->libraries[ordinal-1],symbol);
                if(target)im->error[0]=0;
            }
            if(!target && !weak)return 0;
            if(!target)im->error[0]=0;
            while(count--) {
                if(im->stats.binds>=mp_fixup_limit(im))return fail(im,"bind limit");
                uintptr_t *where=slot(im,segment,address);if(!where)return 0;
                uintptr_t value=(uintptr_t)target;
                uint64_t magnitude=addend<0?0-(uint64_t)addend:(uint64_t)addend;
                if(target && ((addend<0 && value<magnitude) || (addend>=0 && UINTPTR_MAX-value<magnitude)))return fail(im,"bind addend overflow");
                *where=target?value+(uint64_t)addend:0;
                // DO_BIND_ADD_ADDR_ULEB, like ADD_ADDR_ULEB, may carry a
                // modulo-2^64 negative delta (seen in SuperTuxKart); the next
                // slot() call validates the wrapped address before any write.
                if(op!=BIND_OPCODE_DO_BIND_ADD_ADDR_ULEB && (skip>UINT64_MAX-sizeof(uintptr_t) || address>UINT64_MAX-sizeof(uintptr_t)-skip))return fail(im,"bind address overflow");
                im->stats.binds++;address+=sizeof(uintptr_t)+skip;
            }
            break;
        }
        default:snprintf(im->error,sizeof im->error,"bind opcode outside supported runtime subset: 0x%x at file 0x%llx",op,(unsigned long long)(p-im->file-1));return 0;
        }
    }
    (void)last_done; // As for rebases, the stream end also terminates binds in dyld.
    return 1;
}

// Apple's <mach-o/fixup-chains.h>: the ordinary 64-bit offset format observed
// in the first real game. Authenticated, compressed and multi-start formats
// deliberately fail until a controlled experiment exercises them.
#include <mach-o/fixup-chains.h>
static uint16_t chain16(const unsigned char *p){uint16_t v;memcpy(&v,p,2);return v;}
static uint32_t chain32(const unsigned char *p){uint32_t v;memcpy(&v,p,4);return v;}
static uint64_t chain64(const unsigned char *p){uint64_t v;memcpy(&v,p,8);return v;}
static int chain_range(size_t total,uint64_t o,uint64_t n){return o<=total && n<=total-o;}
int mp_apply_chains(Image *im,uint32_t offset,uint32_t size) {
    if(!range(im,offset,size) || size<sizeof(struct dyld_chained_fixups_header))return fail(im,"truncated chained fixups header");
    const unsigned char *data=im->file+offset;struct dyld_chained_fixups_header h;memcpy(&h,data,sizeof h);
    if(h.fixups_version || h.symbols_format || h.imports_format!=DYLD_CHAINED_IMPORT || h.imports_count>mp_fixup_limit(im))return fail(im,"unsupported chained imports format/count");
    if(!chain_range(size,h.imports_offset,(uint64_t)h.imports_count*4) || h.symbols_offset>=size || !chain_range(size,h.starts_offset,4))return fail(im,"chained tables outside payload");
    uint32_t segments=chain32(data+h.starts_offset);
    if(segments!=im->count || !chain_range(size,h.starts_offset+4ULL,segments*4ULL))return fail(im,"invalid chained segment table");
    for(unsigned i=0;i<segments;i++) {
        uint32_t relative=chain32(data+h.starts_offset+4+i*4);if(!relative)continue;
        uint64_t so=(uint64_t)h.starts_offset+relative;
        if(!chain_range(size,so,22))return fail(im,"truncated chained segment");
        const unsigned char *seg=data+so;uint32_t bytes=chain32(seg);uint16_t pageSize=chain16(seg+4),format=chain16(seg+6),pages=chain16(seg+20);
        if(bytes<22 || !chain_range(size,so,bytes) || (uint64_t)pages*2>bytes-22 ||
           (pageSize!=4096 && pageSize!=16384) || format!=DYLD_CHAINED_PTR_64_OFFSET || chain32(seg+16))return fail(im,"unsupported chained segment format");
        struct segment_command_64 *mapped=&im->segments[i];
        if(mapped->vmaddr<im->low || chain64(seg+8)!=mapped->vmaddr-im->low || (uint64_t)pages*pageSize>mapped->vmsize)return fail(im,"chained segment range mismatch");
        for(unsigned page=0;page<pages;page++) {
            uint16_t start=chain16(seg+22+page*2);if(start==DYLD_CHAINED_PTR_START_NONE)continue;
            if(start&DYLD_CHAINED_PTR_START_MULTI)return fail(im,"chained multi-start unsupported");
            uint64_t at=start;
            for(unsigned steps=0;;steps++) {
                if(steps>=pageSize/4 || at>pageSize-8)return fail(im,"chained pointer crosses page");
                uint64_t within=(uint64_t)page*pageSize+at;
                uintptr_t *where=slot(im,i,within);if(!where)return 0;
                if(within>mapped->filesize || 8>mapped->filesize-within || !chain_range(im->file_size,mapped->fileoff+within,8))return fail(im,"chain lacks file-backed encoding");
                // Always decode from the original immutable file, never pointers
                // already rebound in resident memory.
                uint64_t raw=chain64(im->file+mapped->fileoff+within),next=(raw>>51)&4095,value;
                if(raw>>63) {
                    if((raw>>32)&0x7ffff)return fail(im,"reserved chained bind bits");
                    uint32_t ordinal=raw&0xffffff;if(ordinal>=h.imports_count)return fail(im,"chained import ordinal outside table");
                    uint32_t imp=chain32(data+h.imports_offset+ordinal*4),lib=imp&255,weak=(imp>>8)&1,name=imp>>9;
                    // 8-bit chained ordinals: 0 self, 0xFF main executable,
                    // 0xFE flat lookup, 0xFD weak lookup (fixup-chains.h).
                    int special=lib==0?BIND_SPECIAL_DYLIB_SELF:lib==0xff?BIND_SPECIAL_DYLIB_MAIN_EXECUTABLE:lib==0xfe?BIND_SPECIAL_DYLIB_FLAT_LOOKUP:lib==0xfd?BIND_SPECIAL_DYLIB_WEAK_LOOKUP:1;
                    if(special==1 && lib>im->library_count)return fail(im,"unsupported chained library ordinal");
                    uint64_t no=(uint64_t)h.symbols_offset+name;
                    if(no>=size || !memchr(data+no,0,size-no))return fail(im,"unterminated chained symbol");
                    void *target=special!=1?mp_resolve_special(im,special,(const char *)data+no):mp_resolve(im,im->libraries[lib-1],(const char *)data+no);
                    if(!target && special==BIND_SPECIAL_DYLIB_WEAK_LOOKUP){target=mp_resolve_weak(im,(const char *)data+no);}
                    // Chained images bind everything at load; function imports the
                    // host lacks get the same named abort-on-call stubs as lazy
                    // binds (never data or ObjC classes, which must resolve).
                    if(!target && !weak && special==1 && im->services.extensions && im->services.extensions->resolve_lazy && strncmp((const char *)data+no,"_OBJC_",6)) {
                        target=im->services.extensions->resolve_lazy(im->libraries[lib-1],(const char *)data+no);
                        if(target)im->error[0]=0;
                    }
                    if(!target && (!weak || !im->services.extensions || !im->services.extensions->allow_weak_imports))return 0;
                    if(!target)im->error[0]=0;
                    value=target?(uintptr_t)target+((raw>>24)&255):0;
                    if(im->stats.binds++>=mp_fixup_limit(im))return fail(im,"chained bind limit");
                } else {
                    if((raw>>44)&127)return fail(im,"reserved chained rebase bits");
                    uint64_t target=raw&0xfffffffffULL,high=(raw>>36)&255;
                    if(target>=im->span)return fail(im,"chained rebase target outside image");
                    // OFFSET preserves high8 before adding the runtime image base.
                    value=(uintptr_t)im->base+target+(high<<56);
                    if(im->stats.rebases++>=mp_fixup_limit(im))return fail(im,"chained rebase limit");
                }
                memcpy(where,&value,8);if(!next)break;at+=next*4;
            }
        }
    }
    return 1;
}
