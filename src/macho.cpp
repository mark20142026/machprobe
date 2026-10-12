#include "machprobe.hpp"
#include <mach-o/loader.h>
#include <mach-o/fat.h>
#include <mach-o/nlist.h>
#include <mach/arm/thread_status.h>
#include <mach/machine.h>
#include <algorithm>
#include <cstring>
#include <fstream>
#include <functional>
#include <iomanip>
#include <limits>
#include <set>
#include <sstream>

namespace mp {
namespace {
std::string quote(const std::string& s) {
    std::ostringstream out; out << '"';
    // Non-ASCII bytes are escaped too: malformed symbol names cannot corrupt JSON.
    for (unsigned char c : s) {
        if (c == '"' || c == '\\') out << '\\' << c;
        else if (c < 32 || c >= 127) out << "\\u00" << std::hex << std::setw(2) << std::setfill('0') << unsigned(c);
        else out << c;
    }
    return out.str() + '"';
}
struct Bytes {
    const uint8_t* data; size_t size;
    void range(uint64_t off, uint64_t length) const {
        if (off > size || length > size - off) throw std::runtime_error("range outside Mach-O slice");
    }
    template<class T> T read(uint64_t off) const {
        range(off, sizeof(T)); T v; std::memcpy(&v, data + off, sizeof v); return v;
    }
    std::string string(uint64_t off, uint64_t end) const {
        if (end > size || off >= end) throw std::runtime_error("invalid string bounds");
        auto z = static_cast<const uint8_t*>(std::memchr(data + off, 0, end - off));
        if (!z) throw std::runtime_error("unterminated Mach-O string");
        return std::string(reinterpret_cast<const char*>(data + off), z - data - off);
    }
};
std::string fixed(const char* s, size_t n) { return std::string(s, strnlen(s,n)); }
uint32_t be32(const Bytes& b, size_t o) {
    b.range(o,4); return (uint32_t(b.data[o])<<24)|(uint32_t(b.data[o+1])<<16)|(uint32_t(b.data[o+2])<<8)|b.data[o+3];
}
uint64_t be64(const Bytes& b, size_t o) { return (uint64_t(be32(b,o))<<32)|be32(b,o+4); }
std::string platform(uint32_t n) {
    switch(n) {
        case PLATFORM_MACOS: return "macOS"; case PLATFORM_IOS: return "iOS";
        case PLATFORM_TVOS: return "tvOS"; case PLATFORM_WATCHOS: return "watchOS";
        case PLATFORM_BRIDGEOS: return "bridgeOS"; case PLATFORM_MACCATALYST: return "Mac Catalyst";
        case PLATFORM_IOSSIMULATOR: return "iOS Simulator"; case PLATFORM_TVOSSIMULATOR: return "tvOS Simulator";
        case PLATFORM_WATCHOSSIMULATOR: return "watchOS Simulator"; case PLATFORM_DRIVERKIT: return "DriverKit";
        default: return "unknown(" + std::to_string(n) + ")";
    }
}
std::string filetype(uint32_t n) {
    switch(n) {
#define FT(x) case x: return #x
        FT(MH_OBJECT); FT(MH_EXECUTE); FT(MH_FVMLIB); FT(MH_CORE); FT(MH_PRELOAD);
        FT(MH_DYLIB); FT(MH_DYLINKER); FT(MH_BUNDLE); FT(MH_DYLIB_STUB); FT(MH_DSYM); FT(MH_KEXT_BUNDLE);
#undef FT
        default: return "unknown";
    }
}
std::string command(uint32_t n) {
    switch(n) {
#define LC(x) case x: return #x
        LC(LC_SEGMENT); LC(LC_SYMTAB); LC(LC_SYMSEG); LC(LC_THREAD); LC(LC_UNIXTHREAD);
        LC(LC_LOADFVMLIB); LC(LC_IDFVMLIB); LC(LC_IDENT); LC(LC_FVMFILE); LC(LC_PREPAGE);
        LC(LC_DYSYMTAB); LC(LC_LOAD_DYLIB); LC(LC_ID_DYLIB); LC(LC_LOAD_DYLINKER); LC(LC_ID_DYLINKER);
        LC(LC_PREBOUND_DYLIB); LC(LC_ROUTINES); LC(LC_SUB_FRAMEWORK); LC(LC_SUB_UMBRELLA);
        LC(LC_SUB_CLIENT); LC(LC_SUB_LIBRARY); LC(LC_TWOLEVEL_HINTS); LC(LC_PREBIND_CKSUM);
        LC(LC_LOAD_WEAK_DYLIB); LC(LC_SEGMENT_64); LC(LC_ROUTINES_64); LC(LC_UUID); LC(LC_RPATH);
        LC(LC_CODE_SIGNATURE); LC(LC_SEGMENT_SPLIT_INFO); LC(LC_REEXPORT_DYLIB); LC(LC_LAZY_LOAD_DYLIB);
        LC(LC_ENCRYPTION_INFO); LC(LC_DYLD_INFO); LC(LC_DYLD_INFO_ONLY); LC(LC_LOAD_UPWARD_DYLIB);
        LC(LC_VERSION_MIN_MACOSX); LC(LC_VERSION_MIN_IPHONEOS); LC(LC_FUNCTION_STARTS); LC(LC_DYLD_ENVIRONMENT);
        LC(LC_MAIN); LC(LC_DATA_IN_CODE); LC(LC_SOURCE_VERSION); LC(LC_DYLIB_CODE_SIGN_DRS);
        LC(LC_ENCRYPTION_INFO_64); LC(LC_LINKER_OPTION); LC(LC_LINKER_OPTIMIZATION_HINT);
        LC(LC_VERSION_MIN_TVOS); LC(LC_VERSION_MIN_WATCHOS); LC(LC_NOTE); LC(LC_BUILD_VERSION);
        LC(LC_DYLD_EXPORTS_TRIE); LC(LC_DYLD_CHAINED_FIXUPS); LC(LC_FILESET_ENTRY);
#ifdef LC_ATOM_INFO
        LC(LC_ATOM_INFO);
#endif
#ifdef LC_FUNCTION_VARIANTS
        LC(LC_FUNCTION_VARIANTS); LC(LC_FUNCTION_VARIANT_FIXUPS);
#endif
#ifdef LC_TARGET_TRIPLE
        LC(LC_TARGET_TRIPLE);
#endif
#ifdef LC_LAZY_LOAD_DYLIB_INFO
        LC(LC_LAZY_LOAD_DYLIB_INFO);
#endif
#undef LC
        default: return "UNKNOWN";
    }
}
uint64_t uleb(const Bytes& b, uint64_t& off, uint64_t end) {
    uint64_t result = 0;
    for (unsigned i=0; i<10; ++i) {
        if (off >= end) throw std::runtime_error("truncated ULEB128");
        uint8_t c = b.read<uint8_t>(off++);
        if (i == 9 && (c & 0xfe)) throw std::runtime_error("overflowing ULEB128");
        result |= uint64_t(c & 127) << (7*i);
        if (!(c & 128)) return result;
    }
    throw std::runtime_error("overflowing ULEB128");
}
Json exports(const Bytes& b) {
    Json result = Json::array(); std::set<uint64_t> active; size_t visits=0;
    std::function<void(uint64_t,const std::string&,unsigned)> visit;
    visit = [&](uint64_t off, const std::string& prefix, unsigned depth) {
        if (depth>256 || ++visits>100000 || prefix.size()>65536) throw std::runtime_error("export trie traversal limit");
        if (!active.insert(off).second) throw std::runtime_error("cyclic export trie");
        uint64_t p=off, terminal=uleb(b,p,b.size); b.range(p,terminal); uint64_t end=p+terminal;
        if (terminal) {
            auto flags=uleb(b,p,end);
            Json e=Json::Object{{"name",prefix},{"flags",flags},{"source","export_trie"}};
            if (flags & EXPORT_SYMBOL_FLAGS_REEXPORT) {
                e["library_ordinal"]=uleb(b,p,end); e["import_name"]=b.string(p,end);
            } else {
                e["address_or_offset"]=uleb(b,p,end);
                if (flags & EXPORT_SYMBOL_FLAGS_STUB_AND_RESOLVER) e["resolver_offset"]=uleb(b,p,end);
            }
            result.push(e);
        }
        p=end; uint8_t children=b.read<uint8_t>(p++);
        for (unsigned i=0;i<children;++i) {
            auto edge=b.string(p,b.size); p+=edge.size()+1;
            if (edge.empty()) throw std::runtime_error("empty export trie edge");
            auto child=uleb(b,p,b.size); visit(child,prefix+edge,depth+1);
        }
        active.erase(off);
    };
    if(b.size) visit(0,"",0);
    return result;
}
}
std::string Json::dump(unsigned indent) const {
    return std::visit([&](const auto& v)->std::string {
        using T=std::decay_t<decltype(v)>;
        if constexpr(std::is_same_v<T,std::nullptr_t>) return "null";
        else if constexpr(std::is_same_v<T,bool>) return v?"true":"false";
        else if constexpr(std::is_integral_v<T>) return std::to_string(v);
        else if constexpr(std::is_same_v<T,std::string>) return quote(v);
        else {
            std::string s=std::is_same_v<T,Array>?"[":"{"; bool first=true;
            for(const auto& item:v) {
                if(!first) s+=",";
                s+="\n"+std::string(indent+2,' '); first=false;
                if constexpr(std::is_same_v<T,Array>) s+=item.dump(indent+2);
                else s+=quote(item.first)+": "+item.second.dump(indent+2);
            }
            if(!first) s+="\n"+std::string(indent,' ');
            return s+(std::is_same_v<T,Array>?"]":"}");
        }
    },value);
}
std::string version(uint32_t v) { return std::to_string(v>>16)+"."+std::to_string((v>>8)&255)+"."+std::to_string(v&255); }

Image inspect(const std::filesystem::path& path, const std::string& arch) {
    std::ifstream stream(path,std::ios::binary|std::ios::ate);
    if(!stream) throw std::runtime_error("cannot open " + path.string());
    auto length=stream.tellg();
    if(length<0 || uint64_t(length)>512ULL*1024*1024) throw std::runtime_error("input exceeds 512 MiB limit");
    std::vector<uint8_t> storage(static_cast<size_t>(length)); stream.seekg(0);
    if(!storage.empty() && !stream.read(reinterpret_cast<char*>(storage.data()),storage.size())) throw std::runtime_error("cannot read input");
    Bytes whole{storage.data(),storage.size()}, b=whole;
    Json slices=Json::array(); uint64_t sliceOffset=0;
    uint32_t magic=be32(whole,0);
    if(magic==FAT_MAGIC || magic==FAT_MAGIC_64) {
        bool wide=magic==FAT_MAGIC_64; uint32_t count=be32(whole,4); uint64_t stride=wide?32:20;
        whole.range(8,uint64_t(count)*stride); bool found=false; int best=-1;
        std::vector<std::pair<uint64_t,uint64_t>> ranges;
        for(uint32_t i=0;i<count;++i) {
            size_t p=8+uint64_t(i)*stride; uint32_t cpu=be32(whole,p), sub=be32(whole,p+4);
            uint64_t off=wide?be64(whole,p+8):be32(whole,p+8), size=wide?be64(whole,p+16):be32(whole,p+12);
            uint32_t align=be32(whole,p+(wide?24:16));
            whole.range(off,size);
            if(off<8+uint64_t(count)*stride || size<sizeof(mach_header_64) || align>63 || (off % (uint64_t(1)<<align))) throw std::runtime_error("invalid universal slice bounds/alignment");
            for(auto [a,z]:ranges) if(off<z && a<off+size) throw std::runtime_error("overlapping universal slices");
            ranges.emplace_back(off,off+size);
            slices.push(Json::Object{{"cpu_type",cpu},{"cpu_subtype",sub},{"offset",off},{"size",size}});
            auto base=sub & ~uint32_t(CPU_SUBTYPE_MASK);
            bool match=cpu==CPU_TYPE_ARM64 && (arch=="arm64" || (arch=="arm64e" && base==CPU_SUBTYPE_ARM64E));
            int score=base==CPU_SUBTYPE_ARM64_ALL?2:1;
            if(match && score>best) { b={whole.data+off,size_t(size)}; sliceOffset=off; found=true; best=score; }
        }
        if(!found) throw Unsupported("no compatible ARM64 slice for " + arch);
    }
    auto h=b.read<mach_header_64>(0);
    if(h.magic!=MH_MAGIC_64) throw Unsupported("unsupported Mach-O magic/endian/class (requires little-endian 64-bit)");
    if(h.cputype!=CPU_TYPE_ARM64) throw Unsupported("unsupported CPU (requires ARM64)");
    uint32_t subtype=uint32_t(h.cpusubtype)&~uint32_t(CPU_SUBTYPE_MASK);
    if(arch=="arm64e" && subtype!=CPU_SUBTYPE_ARM64E) throw Unsupported("requested arm64e slice not found");
    if(!std::get<Json::Array>(slices.value).empty()) {
        bool agrees=false;
        for(auto& s:std::get<Json::Array>(slices.value)) {
            if(s.at("offset").dump()==std::to_string(sliceOffset))
                agrees=s.at("cpu_type").dump()==std::to_string(h.cputype) && s.at("cpu_subtype").dump()==std::to_string(uint32_t(h.cpusubtype));
        }
        if(!agrees) throw std::runtime_error("universal and slice CPU metadata disagree");
    }
    b.range(sizeof h,h.sizeofcmds);
    if(h.ncmds>h.sizeofcmds/sizeof(load_command)) throw std::runtime_error("impossible load command count");
    Image image; image.cpu=h.cputype; image.subtype=h.cpusubtype;
    auto& r=image.report;
    r["schema_version"]=1; r["path"]=std::filesystem::absolute(path).lexically_normal().string();
    r["slice_offset"]=sliceOffset; r["slice_size"]=b.size; r["slices"]=slices;
    r["header"]=Json::Object{{"architecture",subtype==CPU_SUBTYPE_ARM64E?"arm64e":"arm64"},{"cpu_type",h.cputype},{"cpu_subtype",uint32_t(h.cpusubtype)},{"subtype_base",subtype},{"subtype_capabilities",uint32_t(h.cpusubtype)&uint32_t(CPU_SUBTYPE_MASK)},{"file_type",filetype(h.filetype)},{"file_type_id",h.filetype},{"flags",h.flags},{"ncmds",h.ncmds},{"sizeofcmds",h.sizeofcmds}};
    for(auto key:{"load_commands","build_versions","dylibs","rpaths","entry_points","uuids","segments","code_signing","encryption","linkedit","exports","defined_external_symbols","undefined_symbols","diagnostics"}) r[key]=Json::array();
    r["symbol_coverage"]="LC_SYMTAB externals plus export trie; bind opcodes/chained imports and runtime lookups are not decoded";
    bool hasSymbols=false; symtab_command symbols{};
    std::vector<std::pair<uint32_t,uint32_t>> tries;
    std::vector<segment_command_64> segments;
    uint64_t off=sizeof h, commandsEnd=off+h.sizeofcmds;
    for(uint32_t index=0;index<h.ncmds;++index) {
        auto lc=b.read<load_command>(off);
        if(lc.cmdsize<8 || lc.cmdsize%8 || lc.cmdsize>commandsEnd-off) throw std::runtime_error("invalid load command size/alignment");
        auto need=[&](size_t n) { if(lc.cmdsize<n) throw std::runtime_error("truncated " + command(lc.cmd)); };
        auto str=[&](uint32_t p,size_t minimum) { if(p<minimum || p>=lc.cmdsize) throw std::runtime_error("invalid command string offset"); return b.string(off+p,off+lc.cmdsize); };
        r["load_commands"].push(Json::Object{{"index",index},{"name",command(lc.cmd)},{"command",lc.cmd},{"required_by_dyld",bool(lc.cmd&LC_REQ_DYLD)},{"offset",off},{"size",lc.cmdsize}});
        switch(lc.cmd) {
        case LC_BUILD_VERSION: {
            need(sizeof(build_version_command)); auto c=b.read<build_version_command>(off);
            if(c.ntools>(lc.cmdsize-sizeof c)/sizeof(build_tool_version)) throw std::runtime_error("invalid build tools count");
            Json tools=Json::array();
            for(uint32_t i=0;i<c.ntools;++i) { auto t=b.read<build_tool_version>(off+sizeof c+i*sizeof(build_tool_version)); tools.push(Json::Object{{"tool",t.tool},{"version",version(t.version)}}); }
            r["build_versions"].push(Json::Object{{"source",command(lc.cmd)},{"platform_id",c.platform},{"platform",platform(c.platform)},{"minimum_os",version(c.minos)},{"sdk",version(c.sdk)},{"tools",tools}}); break;
        }
        case LC_VERSION_MIN_MACOSX: case LC_VERSION_MIN_IPHONEOS: case LC_VERSION_MIN_TVOS: case LC_VERSION_MIN_WATCHOS: {
            need(sizeof(version_min_command)); auto c=b.read<version_min_command>(off);
            uint32_t p=lc.cmd==LC_VERSION_MIN_MACOSX?PLATFORM_MACOS:lc.cmd==LC_VERSION_MIN_IPHONEOS?PLATFORM_IOS:lc.cmd==LC_VERSION_MIN_TVOS?PLATFORM_TVOS:PLATFORM_WATCHOS;
            r["build_versions"].push(Json::Object{{"source",command(lc.cmd)},{"platform_id",p},{"platform",platform(p)},{"minimum_os",version(c.version)},{"sdk",version(c.sdk)}}); break;
        }
        case LC_LOAD_DYLIB: case LC_LOAD_WEAK_DYLIB: case LC_REEXPORT_DYLIB: case LC_LOAD_UPWARD_DYLIB: case LC_LAZY_LOAD_DYLIB: case LC_ID_DYLIB: {
            need(sizeof(dylib_command)); auto c=b.read<dylib_command>(off); auto name=str(c.dylib.name.offset,sizeof c);
            r["dylibs"].push(Json::Object{{"name",name},{"kind",command(lc.cmd)},{"current_version",version(c.dylib.current_version)},{"compatibility_version",version(c.dylib.compatibility_version)}});
            if(lc.cmd!=LC_ID_DYLIB) image.dependencies.push_back({name,command(lc.cmd)}); break;
        }
        case LC_RPATH: {
            need(sizeof(rpath_command)); auto c=b.read<rpath_command>(off); auto p=str(c.path.offset,sizeof c); image.rpaths.push_back(p); r["rpaths"].push(p); break;
        }
        case LC_LOAD_DYLINKER: case LC_ID_DYLINKER: case LC_DYLD_ENVIRONMENT: {
            need(sizeof(dylinker_command)); auto c=b.read<dylinker_command>(off);
            auto& last=std::get<Json::Array>(r["load_commands"].value).back(); last["value"]=str(c.name.offset,sizeof c); break;
        }
        case LC_UUID: {
            need(sizeof(uuid_command)); auto c=b.read<uuid_command>(off); std::ostringstream s;
            for(unsigned i=0;i<16;++i) { if(i==4||i==6||i==8||i==10)s<<'-'; s<<std::hex<<std::setw(2)<<std::setfill('0')<<unsigned(c.uuid[i]); }
            r["uuids"].push(s.str()); break;
        }
        case LC_MAIN: {
            need(sizeof(entry_point_command)); auto c=b.read<entry_point_command>(off);
            r["entry_points"].push(Json::Object{{"source","LC_MAIN"},{"entryoff",c.entryoff},{"stacksize",c.stacksize}}); break;
        }
        case LC_UNIXTHREAD: case LC_THREAD: {
            uint64_t p=off+8;
            while(p<off+lc.cmdsize) {
                if(off+lc.cmdsize-p<8) throw std::runtime_error("truncated thread flavor");
                auto flavor=b.read<uint32_t>(p), count=b.read<uint32_t>(p+4); p+=8;
                if(uint64_t(count)*4>off+lc.cmdsize-p) throw std::runtime_error("truncated thread state");
                Json e=Json::Object{{"source",command(lc.cmd)},{"flavor",flavor},{"word_count",count}};
                if(flavor==ARM_THREAD_STATE64 && count==ARM_THREAD_STATE64_COUNT) {
                    auto t=b.read<arm_thread_state64_t>(p); e["virtual_address"]=t.__pc;
                } else e["status"]="unsupported thread flavor";
                r["entry_points"].push(e); p+=uint64_t(count)*4;
            } break;
        }
        case LC_SEGMENT_64: {
            need(sizeof(segment_command_64)); auto c=b.read<segment_command_64>(off);
            if(c.nsects>(lc.cmdsize-sizeof c)/sizeof(section_64)) throw std::runtime_error("invalid section count");
            b.range(c.fileoff,c.filesize); segments.push_back(c);
            Json sections=Json::array();
            for(uint32_t i=0;i<c.nsects;++i) {
                auto s=b.read<section_64>(off+sizeof c+i*sizeof(section_64));
                auto type=s.flags&SECTION_TYPE;
                if(type!=S_ZEROFILL && type!=S_GB_ZEROFILL && type!=S_THREAD_LOCAL_ZEROFILL) b.range(s.offset,s.size);
                sections.push(Json::Object{{"name",fixed(s.sectname,16)},{"segment",fixed(s.segname,16)},{"address",s.addr},{"size",s.size},{"offset",s.offset},{"flags",s.flags}});
            }
            r["segments"].push(Json::Object{{"name",fixed(c.segname,16)},{"vmaddr",c.vmaddr},{"vmsize",c.vmsize},{"fileoff",c.fileoff},{"filesize",c.filesize},{"maxprot",c.maxprot},{"initprot",c.initprot},{"sections",sections}}); break;
        }
        case LC_SYMTAB: {
            need(sizeof(symtab_command)); if(hasSymbols) throw std::runtime_error("duplicate LC_SYMTAB"); hasSymbols=true; symbols=b.read<symtab_command>(off);
            b.range(symbols.symoff,uint64_t(symbols.nsyms)*sizeof(nlist_64)); b.range(symbols.stroff,symbols.strsize); break;
        }
        case LC_CODE_SIGNATURE: case LC_DYLIB_CODE_SIGN_DRS: case LC_DYLD_EXPORTS_TRIE: case LC_DYLD_CHAINED_FIXUPS: case LC_FUNCTION_STARTS: case LC_DATA_IN_CODE: case LC_SEGMENT_SPLIT_INFO: case LC_LINKER_OPTIMIZATION_HINT: {
            need(sizeof(linkedit_data_command)); auto c=b.read<linkedit_data_command>(off); b.range(c.dataoff,c.datasize);
            Json j=Json::Object{{"command",command(lc.cmd)},{"offset",c.dataoff},{"size",c.datasize}};
            r["linkedit"].push(j);
            if(lc.cmd==LC_CODE_SIGNATURE || lc.cmd==LC_DYLIB_CODE_SIGN_DRS) r["code_signing"].push(j);
            if(lc.cmd==LC_DYLD_EXPORTS_TRIE && c.datasize) tries.emplace_back(c.dataoff,c.datasize);
            break;
        }
        case LC_DYLD_INFO: case LC_DYLD_INFO_ONLY: {
            need(sizeof(dyld_info_command)); auto c=b.read<dyld_info_command>(off);
            for(auto tuple: {std::make_tuple("rebase",c.rebase_off,c.rebase_size),std::make_tuple("bind",c.bind_off,c.bind_size),std::make_tuple("weak_bind",c.weak_bind_off,c.weak_bind_size),std::make_tuple("lazy_bind",c.lazy_bind_off,c.lazy_bind_size),std::make_tuple("export",c.export_off,c.export_size)}) {
                auto [kind,start,size]=tuple; b.range(start,size); r["linkedit"].push(Json::Object{{"command",command(lc.cmd)},{"kind",kind},{"offset",start},{"size",size}});
            }
            if(c.export_size) tries.emplace_back(c.export_off,c.export_size); break;
        }
        case LC_ENCRYPTION_INFO: case LC_ENCRYPTION_INFO_64: {
            need(lc.cmd==LC_ENCRYPTION_INFO_64?sizeof(encryption_info_command_64):sizeof(encryption_info_command));
            auto c=b.read<encryption_info_command>(off); b.range(c.cryptoff,c.cryptsize);
            r["encryption"].push(Json::Object{{"command",command(lc.cmd)},{"offset",c.cryptoff},{"size",c.cryptsize},{"cryptid",c.cryptid},{"encrypted",c.cryptid!=0}}); break;
        }
        default: break;
        }
        off+=lc.cmdsize;
    }
    if(off!=commandsEnd) throw std::runtime_error("load command sizes do not match sizeofcmds");
    for(auto& e:std::get<Json::Array>(r["entry_points"].value)) {
        if(std::get<Json::Object>(e.value).count("entryoff")) {
            auto entry=std::get<uint64_t>(e.at("entryoff").value); bool mapped=false;
            for(auto s:segments) if(fixed(s.segname,16)=="__TEXT" && entry>=s.fileoff && entry-s.fileoff<s.filesize) {
                auto delta=entry-s.fileoff;
                if(delta>UINT64_MAX-s.vmaddr) throw std::runtime_error("entry address overflow");
                e["virtual_address"]=s.vmaddr+delta; mapped=true;
            }
            if(!mapped) r["diagnostics"].push("LC_MAIN entryoff is not in a file-backed __TEXT segment");
        }
    }
    if(hasSymbols) for(uint32_t i=0;i<symbols.nsyms;++i) {
        auto n=b.read<nlist_64>(symbols.symoff+uint64_t(i)*sizeof(nlist_64));
        if(n.n_un.n_strx>=symbols.strsize) throw std::runtime_error("symbol string index outside table");
        auto name=b.string(uint64_t(symbols.stroff)+n.n_un.n_strx,uint64_t(symbols.stroff)+symbols.strsize);
        if(n.n_type&N_STAB || !(n.n_type&N_EXT)) continue;
        bool undef=(n.n_type&N_TYPE)==N_UNDF;
        Json s=Json::Object{{"name",name},{"type",n.n_type},{"section",n.n_sect},{"description",n.n_desc},{"value",n.n_value},{"source","LC_SYMTAB"},{"private_external",bool(n.n_type&N_PEXT)}};
        if(undef) {
            s["weak_import"]=bool(n.n_desc&N_WEAK_REF); auto ordinal=GET_LIBRARY_ORDINAL(n.n_desc); s["library_ordinal"]=ordinal;
            if(ordinal>0 && size_t(ordinal)<=image.dependencies.size()) s["library"]=image.dependencies[ordinal-1].name;
            s["common_symbol"]=n.n_value!=0; r["undefined_symbols"].push(s);
        } else r["defined_external_symbols"].push(s);
    }
    std::set<std::pair<uint32_t,uint32_t>> uniqueTries(tries.begin(),tries.end());
    for(auto [start,size]:uniqueTries) {
        auto decoded=exports({b.data+start,size});
        for(auto& e:std::get<Json::Array>(decoded.value)) r["exports"].push(e);
    }
    if(!hasSymbols) r["diagnostics"].push("No LC_SYMTAB; undefined-symbol coverage unavailable");
    return image;
}
}
