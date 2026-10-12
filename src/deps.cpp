#include "machprobe.hpp"
#include <mach-o/dyld.h>
#include <algorithm>
#include <functional>
#include <set>
#include <sstream>

namespace mp {
namespace fs=std::filesystem;
namespace {
bool starts(const std::string& a,const std::string& prefix) { return a.rfind(prefix,0)==0; }
std::string canonicalPath(const fs::path& p) { return fs::weakly_canonical(fs::absolute(p)).string(); }
Json categories(const std::string& p) {
    Json tags=Json::array(); bool tagged=false;
    auto add=[&](const char* t) { tags.push(t); tagged=true; };
    if(starts(p,"/usr/lib/") || starts(p,"/System/Library/")) add("Darwin/system");
    if(starts(p,"/System/Library/Frameworks/") || starts(p,"/System/Library/PrivateFrameworks/")) add("Apple framework");
    if(p.find("Metal")!=std::string::npos || p.find("QuartzCore")!=std::string::npos || p.find("OpenGL")!=std::string::npos) add("graphics/Metal");
    if(p.find("libobjc")!=std::string::npos) add("Objective-C runtime");
    if(!tagged) add("application-specific");
    return tags;
}
std::string expand(const std::string& p,const fs::path& loader,const fs::path& executable) {
    if(p=="@loader_path") return loader.string();
    if(p=="@executable_path") return executable.string();
    if(starts(p,"@loader_path/")) return (loader/p.substr(13)).lexically_normal().string();
    if(starts(p,"@executable_path/")) return (executable/p.substr(17)).lexically_normal().string();
    if(!p.empty() && p[0]!='/') return ""; // Relative and nested token paths depend on policy we do not model.
    return fs::path(p).lexically_normal().string();
}
}
Json dependencies(const fs::path& input,const std::string& arch,unsigned maxDepth) {
    const auto root=canonicalPath(input); const auto executable=fs::path(root).parent_path();
    Json report=Json::Object{{"schema_version",1},{"root",root},{"max_depth",maxDepth},{"node_limit",1024},{"nodes",Json::array()},{"edges",Json::array()},{"complete",true},{"limitations","Static load commands only; no dlopen discovery, environment/fallback policy, cache image parsing, or guarantee of dyld acceptance"}};
    auto& nodes=std::get<Json::Array>(report["nodes"].value);
    auto& edges=std::get<Json::Array>(report["edges"].value);
    std::map<std::string,size_t> visited, active;
    std::function<size_t(const std::string&,const Image&,std::vector<std::string>,unsigned)> walk;
    walk=[&](const std::string& path,const Image& image,std::vector<std::string> inherited,unsigned depth)->size_t {
        std::vector<std::string> runpaths;
        Json ignored=Json::array();
        for(auto& p:image.rpaths) {
            auto e=expand(p,fs::path(path).parent_path(),executable);
            if(e.empty()) ignored.push(p);
            else if(std::find(runpaths.begin(),runpaths.end(),e)==runpaths.end()) runpaths.push_back(e);
        }
        for(auto& p:inherited) if(std::find(runpaths.begin(),runpaths.end(),p)==runpaths.end()) runpaths.push_back(p);
        std::string key=path;
        for(auto& p:runpaths) key+='\0'+p;
        if(auto it=active.find(path);it!=active.end()) return it->second;
        if(auto it=visited.find(key);it!=visited.end()) return it->second;
        size_t id=nodes.size(); visited[key]=id; active[path]=id;
        Json rp=Json::array(); for(auto& p:runpaths) rp.push(p);
        nodes.push_back(Json::Object{{"id",id},{"path",path},{"depth",depth},{"runpaths",rp},{"unmodeled_rpaths",ignored},{"architecture",image.report.at("header").at("architecture")}});
        if(!std::get<Json::Array>(ignored.value).empty()) report["complete"]=false;
        for(auto& dep:image.dependencies) {
            Json edge=Json::Object{{"from",id},{"install_name",dep.name},{"kind",dep.kind},{"categories",categories(dep.name)},{"candidates",Json::array()}};
            std::vector<std::string> candidates;
            if(starts(dep.name,"@rpath/")) for(auto& p:runpaths) candidates.push_back((fs::path(p)/dep.name.substr(7)).lexically_normal().string());
            else { auto p=expand(dep.name,fs::path(path).parent_path(),executable); if(!p.empty()) candidates.push_back(p); }
            std::string resolved; bool cached=false;
            for(auto& p:candidates) {
                edge["candidates"].push(p);
                std::error_code error;
                if(fs::is_regular_file(p,error)) { resolved=canonicalPath(p); break; }
                if(_dyld_shared_cache_contains_path(p.c_str())) { resolved=p; cached=true; break; }
            }
            if(resolved.empty()) {
                edge["status"]=candidates.empty()?"unmodeled-path":"missing";
                edge["reason"]=candidates.empty()?"No modeled candidate; relative paths and nested tokens are not resolved":"No regular file or host shared-cache entry found";
                report["complete"]=false;
            } else {
                edge["resolved_path"]=resolved;
                if(cached) { edge["status"]="cache-only"; edge["reason"]="Host dyld cache membership confirmed; image not parsed"; report["complete"]=false; }
                else if(auto it=active.find(resolved);it!=active.end()) { edge["status"]="cycle"; edge["to"]=it->second; }
                else if(depth>=maxDepth || nodes.size()>=1024) {
                    edge["status"]=depth>=maxDepth?"depth-limit":"node-limit"; report["complete"]=false;
                } else {
                    try {
                        auto child=inspect(resolved,arch);
                        edge["to"]=walk(resolved,child,runpaths,depth+1); edge["status"]="inspected";
                    } catch(const Unsupported& error) {
                        edge["status"]="unsupported"; edge["reason"]=error.what(); report["complete"]=false;
                    } catch(const std::exception& error) {
                        edge["status"]="malformed"; edge["reason"]=error.what(); report["complete"]=false;
                    }
                }
            }
            edges.push_back(std::move(edge));
        }
        active.erase(path); return id;
    };
    walk(root,inspect(root,arch),{},0);
    return report;
}
std::string describe(const Json& report) {
    std::ostringstream out;
    std::function<void(const Json&,unsigned)> render;
    render=[&](const Json& j,unsigned indent) {
        if(auto object=std::get_if<Json::Object>(&j.value)) {
            for(auto& [key,value]:*object) {
                out<<std::string(indent,' ')<<key<<":";
                if(std::holds_alternative<Json::Object>(value.value) || std::holds_alternative<Json::Array>(value.value)) { out<<"\n"; render(value,indent+2); }
                else { out<<" "; render(value,0); }
            }
        } else if(auto array=std::get_if<Json::Array>(&j.value)) {
            if(array->empty()) out<<std::string(indent,' ')<<"(none)\n";
            for(auto& value:*array) {
                if(std::holds_alternative<Json::Object>(value.value)) { out<<std::string(indent,' ')<<"-\n"; render(value,indent+2); }
                else { out<<std::string(indent,' ')<<"- "; render(value,0); }
            }
        } else if(auto str=std::get_if<std::string>(&j.value)) {
            // Escape control bytes even in terminal reports (untrusted file strings).
            for(unsigned char c:*str) { if(c<32 || c>=127) out<<"\\x"<<"0123456789abcdef"[c>>4]<<"0123456789abcdef"[c&15]; else out<<c; }
            out<<"\n";
        } else out<<j.dump()<<"\n";
    };
    render(report,0); return out.str();
}
}
