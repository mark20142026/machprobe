#!/usr/bin/env python3
"""Capture narrow follow-up experiments without altering baseline executables."""
import datetime
import hashlib
import json
from pathlib import Path
import subprocess
from evidence import ROOT, capture, digest

sdk = Path(subprocess.check_output(['xcrun','--show-sdk-path'],text=True).strip())
headers = {
    'loader': (sdk/'usr/include/mach-o/loader.h', r'LC_BUILD_VERSION|LC_VERSION_MIN_|PLATFORM_MACOS |PLATFORM_IOS |PLATFORM_IOSSIMULATOR |PLATFORM_MACCATALYST |LC_MAIN|entryoff|LC_DYLD_CHAINED_FIXUPS'),
    'cache_api': (sdk/'usr/include/mach-o/dyld.h', r'_dyld_shared_cache_contains_path'),
    'metal': (sdk/'System/Library/Frameworks/Metal.framework/Headers/MTLDevice.h', r'MTLCreateSystemDefaultDevice|registryID API_|hasUnifiedMemory API_|lowPower API_|removable API_'),
}
r = {'captured_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
     'headers':{}, 'experiments':{}, 'baseline_hashes':{}}
for name,(path,pattern) in headers.items():
    r['headers'][name] = {'path':str(path),'sha256':digest(path),'selected_lines':capture(['rg','-n',pattern,str(path)])}
r['experiments']['ios_sdk_lookup'] = capture(['xcrun','--sdk','iphoneos','--show-sdk-path'])
r['experiments']['toolchain_selection'] = capture(['xcode-select','-p'])
r['experiments']['abi_macros'] = capture(['xcrun','clang','-arch','arm64','-isysroot',str(sdk),'-mmacosx-version-min=11.0','-dM','-E','-x','c','/dev/null'])
r['experiments']['objc_selectors'] = capture(['otool','-v','-s','__TEXT','__objc_methname','build/metal_info'])
r['experiments']['objc_disassembly'] = capture(['otool','-tvV','build/metal_info'])
for name in ['hello','file_io','framework','metal_info']:
    r['baseline_hashes'][name] = digest(ROOT/'build'/name)
    r['experiments']['entitlements_'+name] = capture(['codesign','-d','--entitlements',':-',str(ROOT/'build'/name)])
paths = ['/usr/lib/libSystem.B.dylib','/usr/lib/libobjc.A.dylib','/System/Library/Frameworks/Metal.framework/Versions/A/Metal']
r['experiments']['filesystem_presence'] = {p:{'exists':Path(p).exists(),'is_regular_file':Path(p).is_file(),'is_symlink':Path(p).is_symlink()} for p in paths}
variant = ROOT/'build/variants/hello-modern'
variant.parent.mkdir(exist_ok=True)
r['experiments']['modern_build'] = capture(['xcrun','clang','-arch','arm64','-isysroot',str(sdk),'-mmacosx-version-min=13.0','-Wl,-fixup_chains','samples/hello.c','-o',str(variant)])
if r['experiments']['modern_build']['returncode'] != 0:
    raise SystemExit(r['experiments']['modern_build']['stderr'])
r['experiments']['modern_sha256'] = digest(variant)
for label,cmd in {'modern_run':[str(variant)],'modern_otool':['otool','-l',str(variant)],
                  'modern_inspect':['build/machprobe','inspect',str(variant),'--json']}.items():
    r['experiments'][label] = capture(cmd)
    if r['experiments'][label]['returncode'] != 0: raise SystemExit(r['experiments'][label])
(ROOT/'docs/evidence/research.json').write_text(json.dumps(r,indent=2,sort_keys=True)+'\n')
print('Wrote docs/evidence/research.json')
