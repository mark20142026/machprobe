#!/usr/bin/env python3
"""Package exact guest bytes in an iOS container; compile only our runtime/shims."""
import hashlib,json,os,plistlib,shutil,subprocess,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'build/phase4-runtime';APP=OUT/'Payload/MacGuest.app'
APP.mkdir(parents=True,exist_ok=True);frameworks=APP/'Frameworks';frameworks.mkdir(exist_ok=True)
env=dict(os.environ,DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
def run(args):return subprocess.check_output([str(x) for x in args],env=env,text=True).strip()
sdk=run(['xcrun','--sdk','iphoneos','--show-sdk-path']);target='arm64-apple-ios14.0'
manifest=json.loads((ROOT/'build/phase4/target.json').read_text());data=(ROOT/'build/phase4/selected-arm64').read_bytes()
assert hashlib.sha256(data).hexdigest()==manifest['arm64_sha256']
parsed=json.loads(run([ROOT/'build/machprobe','inspect',ROOT/'build/phase4/selected-arm64','--json']))
textsize=next(s['filesize'] for s in parsed['segments'] if s['name']=='__TEXT')
(OUT/'guest-text.bin').write_bytes(data[:textsize]);(OUT/'guest-data.bin').write_bytes(data[textsize:])
(OUT/'empty.s').write_text('.section __TEXT,__text,regular,pure_instructions\n')
run(['xcrun','clang','-target',target,'-isysroot',sdk,'-c',OUT/'empty.s','-o',OUT/'empty.o'])
container=frameworks/'MPGuest.dylib'
run(['xcrun','ld','-dylib',OUT/'empty.o','-arch','arm64','-platform_version','ios','14.0','27.0','-syslibroot',sdk,'-lSystem','-sectcreate','__TEXT','__guest',OUT/'guest-text.bin','-sectcreate','__DATA','__guest',OUT/'guest-data.bin','-sectalign','__TEXT','__guest','4000','-sectalign','__DATA','__guest','4000','-install_name','@rpath/MPGuest.dylib','-o',container])
run(['codesign','--force','--sign','-',container])
objects=[]
for source in [*[ROOT/'runtime'/p for p in ['image.c','fixups.c','services.c','tls.c','group.c']],ROOT/'phase4/runtime/Extended.c',ROOT/'phase4/runtime/ImageShim.m',ROOT/'phase4/host/RuntimeMain.m']:
 obj=OUT/(source.stem+'.o');run(['xcrun','clang','-target',target,'-isysroot',sdk,'-g','-O0','-I'+str(ROOT/'runtime'),'-I'+str(ROOT/'phase4/runtime'),*(['-fobjc-arc'] if source.suffix=='.m' else []),'-c',source,'-o',obj]);objects.append(obj)
run(['xcrun','swiftc','-target',target,'-sdk',sdk,'-parse-as-library','-import-objc-header',ROOT/'phase4/runtime/ImageShim.h','-emit-object',ROOT/'phase4/runtime/ImageShim.swift','-o',OUT/'SwiftShim.o'])
run(['xcrun','swiftc','-target',target,'-sdk',sdk,*objects,OUT/'SwiftShim.o','-framework','Foundation','-framework','UIKit','-framework','CoreFoundation','-framework','Metal','-framework','CoreText','-framework','AudioToolbox','-Xlinker','-export_dynamic','-o',APP/'MacGuest'])
resources=ROOT/'build/phase4/original/extracted/DashboardCalculator.app/Contents/Resources'
for p in resources.iterdir():
 if p.is_dir():shutil.copytree(p,APP/p.name,dirs_exist_ok=True)
 else:shutil.copy2(p,APP/p.name)
run(['python3',ROOT/'phase4/tools/convert_assets.py'])
(APP/'target.json').write_text(json.dumps(manifest,indent=2))
info={'CFBundleIdentifier':'research.machprobe.MacGuest','CFBundleExecutable':'MacGuest','CFBundleName':'MacGuest','CFBundleDisplayName':'Mac app runtime','CFBundlePackageType':'APPL','CFBundleShortVersionString':'1.0','CFBundleVersion':'1','CFBundleSupportedPlatforms':['iPhoneOS'],'LSRequiresIPhoneOS':True,'MinimumOSVersion':'14.0','UIDeviceFamily':[1,2],'UILaunchScreen':{},'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False}}
(APP/'Info.plist').write_bytes(plistlib.dumps(info));run(['codesign','--force','--sign','-',APP])
with zipfile.ZipFile(OUT/'MacGuest.ipa','w',zipfile.ZIP_DEFLATED) as z:
 for f in sorted(APP.rglob('*')):
  if f.is_file():z.write(f,f.relative_to(OUT))
print(OUT/'MacGuest.ipa')
