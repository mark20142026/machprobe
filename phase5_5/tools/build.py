#!/usr/bin/env python3
"""Package exact guest bytes in an iOS container; compile only our runtime/shims."""
import hashlib,json,os,plistlib,shutil,subprocess,zipfile,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'build/phase5.5-runtime';APP=OUT/'Payload/VelorenHost.app'
APP.mkdir(parents=True,exist_ok=True);frameworks=APP/'Frameworks';frameworks.mkdir(exist_ok=True)
env=dict(os.environ,DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
def run(args):return subprocess.check_output([str(x) for x in args],env=env,text=True).strip()
sdk=run(['xcrun','--sdk','iphoneos','--show-sdk-path']);target='arm64-apple-ios14.0'
data=(ROOT/'build/phase5.5/original/extracted/veloren-voxygen').read_bytes()
manifest={'arm64_sha256':'786b7ba15f46982a1bfbd3af53373c505d5dce0efb344dfe19a159b7e6e00b1d','slice_size':len(data),'release':'weekly-macos-aarch64-2026-09-30T23_33.zip'}
assert hashlib.sha256(data).hexdigest()==manifest['arm64_sha256']
parsed=json.loads(run([ROOT/'build/machprobe','inspect',ROOT/'build/phase5.5/original/extracted/veloren-voxygen','--json']))
textsize=next(s['filesize'] for s in parsed['segments'] if s['name']=='__TEXT')
(OUT/'guest-text.bin').write_bytes(data[:textsize]);segments=[s for s in parsed['segments'] if s['name']!='__PAGEZERO']
base=min(s['vmaddr'] for s in segments)
span=max(s['vmaddr']+s['vmsize'] for s in segments)-base
(OUT/'guest-data.bin').write_bytes(data[textsize:]+bytes(max(0,span-len(data))))
(OUT/'empty.s').write_text('.section __TEXT,__text,regular,pure_instructions\n')
run(['xcrun','clang','-target',target,'-isysroot',sdk,'-c',OUT/'empty.s','-o',OUT/'empty.o'])
container=frameworks/'MPGuest.dylib'
run(['xcrun','ld','-dylib',OUT/'empty.o','-arch','arm64','-platform_version','ios','14.0','27.0','-syslibroot',sdk,'-lSystem','-sectcreate','__TEXT','__guest',OUT/'guest-text.bin','-sectcreate','__DATA','__guest',OUT/'guest-data.bin','-sectalign','__TEXT','__guest','4000','-sectalign','__DATA','__guest','4000','-install_name','@rpath/MPGuest.dylib','-o',container])
run(['codesign','--force','--sign','-',container])
objects=[]
for source in [*[ROOT/'runtime'/p for p in ['image.c','fixups.c','services.c','tls.c','group.c']],ROOT/'phase4/runtime/Extended.c',ROOT/'phase4_5/host/GameBridge.m',ROOT/'phase5_5/host/Main.m',ROOT/'phase5/runtime/Policy.c',ROOT/'phase5_5/runtime/Policy.c',ROOT/'phase5_5/runtime/LazyImports.c',ROOT/'phase5_5/runtime/Constants.m',ROOT/'phase5_5/runtime/Display.m',ROOT/'phase5_5/runtime/LegacyMetal.m',ROOT/'phase5_5/runtime/BaseVertex.m',ROOT/'phase5_5/runtime/AudioDiagnostics.m',ROOT/'phase5_5/runtime/Keyboard.m',ROOT/'phase5_5/tests/MetalProbe.m',ROOT/'phase5_5/tests/UIKitProbe.m',ROOT/'phase5_5/tests/AudioProbe.m',ROOT/'phase5_5/runtime/ObjCRuntime.m',ROOT/'phase5/runtime/AppKitCompat.m',ROOT/'phase5/runtime/Lifecycle.m',ROOT/'phase5/runtime/Menu.m',ROOT/'phase5/runtime/Updater.m',ROOT/'phase5/runtime/Window.m',ROOT/'phase5/runtime/MetalCompat.m',ROOT/'phase5/runtime/Input.m',ROOT/'phase5/runtime/Observe.m',ROOT/'phase5/runtime/Controls.m',ROOT/'phase4/runtime/ImageShim.m']:
 obj=OUT/('_'.join(source.relative_to(ROOT).with_suffix('').parts)+'.o');run(['xcrun','clang','-target',target,'-isysroot',sdk,'-g','-O0','-I'+str(ROOT/'runtime'),'-I'+str(ROOT/'phase4/runtime'),'-I'+str(ROOT/'phase4_5/host'),'-I'+str(ROOT/'phase5/runtime'),*(['-fobjc-arc'] if source.suffix=='.m' else []),'-c',source,'-o',obj]);objects.append(obj)
run(['xcrun','swiftc','-target',target,'-sdk',sdk,'-parse-as-library','-import-objc-header',ROOT/'phase4/runtime/ImageShim.h','-emit-object',ROOT/'phase4/runtime/ImageShim.swift','-o',OUT/'SwiftShim.o'])
run(['xcrun','swiftc','-target',target,'-sdk',sdk,*objects,OUT/'SwiftShim.o','-framework','Foundation','-framework','UIKit','-framework','Metal','-framework','MetalKit','-framework','QuartzCore','-framework','CoreGraphics','-framework','CoreText','-framework','CoreFoundation','-framework','AudioToolbox','-framework','AVFAudio','-Xlinker','-export_dynamic','-o',APP/'VelorenHost'])
# Copy the official resource tree byte-for-byte, retaining relative paths.
if '--with-assets' in sys.argv:
 shutil.copytree(ROOT/'build/phase5.5/original/extracted/assets',APP/'assets',dirs_exist_ok=True)
elif (APP/'assets').exists():
 shutil.rmtree(APP/'assets') # Generated copy only; originals and deployed data retained.
(APP/'target.json').write_text(json.dumps(manifest,indent=2))
info={'CFBundleIdentifier':'research.machprobe.VelorenHost','CFBundleExecutable':'VelorenHost','CFBundleName':'VelorenHost','CFBundleDisplayName':'Veloren research runtime','CFBundlePackageType':'APPL','CFBundleShortVersionString':'1.0','CFBundleVersion':'1','CFBundleSupportedPlatforms':['iPhoneOS'],'LSRequiresIPhoneOS':True,'MinimumOSVersion':'14.0','UIDeviceFamily':[1,2],'UISupportedInterfaceOrientations':['UIInterfaceOrientationPortrait','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight'],'UILaunchScreen':{},'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False}}
(APP/'Info.plist').write_bytes(plistlib.dumps(info));(APP/'AppIcon.icns').unlink(missing_ok=True)
run(['codesign','--force','--sign','-',APP])
with zipfile.ZipFile(OUT/'VelorenHost.ipa','w',zipfile.ZIP_DEFLATED) as z:
 for f in sorted(APP.rglob('*')):
  if f.is_file():z.write(f,f.relative_to(OUT))
print(OUT/'VelorenHost.ipa')
