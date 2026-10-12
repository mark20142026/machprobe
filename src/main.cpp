#include "machprobe.hpp"
#include <iostream>

int main(int argc,char** argv) {
    bool json=false;
    try {
        if(argc<3) throw std::invalid_argument("usage: machprobe inspect|deps FILE [--arch arm64|arm64e] [--json] [--max-depth N]");
        std::string mode=argv[1], arch="arm64"; unsigned depth=16;
        if(mode!="inspect" && mode!="deps") throw std::invalid_argument("expected inspect or deps");
        for(int i=3;i<argc;++i) {
            std::string arg=argv[i];
            if(arg=="--json") json=true;
            else if(arg=="--arch" && i+1<argc) { arch=argv[++i]; if(arch!="arm64" && arch!="arm64e") throw std::invalid_argument("unsupported --arch"); }
            else if(arg=="--max-depth" && i+1<argc && mode=="deps") {
                std::string n=argv[++i];
                if(n.empty() || n.find_first_not_of("0123456789")!=std::string::npos || n.size()>3 || std::stoul(n)>128) throw std::invalid_argument("--max-depth must be 0..128");
                depth=unsigned(std::stoul(n));
            } else throw std::invalid_argument("unknown or incomplete option: "+arg);
        }
        auto report=mode=="inspect"?mp::inspect(argv[2],arch).report:mp::dependencies(argv[2],arch,depth);
        std::cout<<(json?report.dump()+"\n":mp::describe(report)); return 0;
    } catch(const std::exception& error) {
        if(json) std::cout<<mp::Json(mp::Json::Object{{"schema_version",1},{"error",error.what()}}).dump()<<"\n";
        else std::cerr<<"machprobe: "<<error.what()<<"\n";
        return 1;
    }
}
