#!/usr/bin/env python3
"""Build one macOS guest, then embed its exact bytes in a separate iOS host."""
import hashlib,json,os,plistlib,shutil,subprocess,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'build/phase4.5';MAC=OUT/'Arena.app';APP=OUT/'Payload/ArenaHost.app'
env=dict(os.environ,DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
def run(args):return subprocess.check_output([str(x) for x in args],env=env,text=True).strip()
for p in [MAC/'Contents/MacOS',MAC/'Contents/Resources',APP/'Frameworks']:p.mkdir(parents=True,exist_ok=True)
macsdk=run(['xcrun','--sdk','macosx','--show-sdk-path']);ios=run(['xcrun','--sdk','iphoneos','--show-sdk-path']);guest=MAC/'Contents/MacOS/Arena'
run(['xcrun','clang','-arch','arm64','-isysroot',macsdk,'-mmacosx-version-min=11.0','-O1','-g','-Wall','-Wextra','-fno-objc-arc','-fno-objc-exceptions','-fno-exceptions','-Wl,-no_fixup_chains','-Wl,-export_dynamic',ROOT/'phase4_5/guest/Game.m','-framework','AppKit','-framework','MetalKit','-framework','Metal','-framework','QuartzCore','-o',guest])
for f in ['scene.metal','checker.rgba']:shutil.copy2(ROOT/'phase4_5/guest'/f,MAC/'Contents/Resources'/f);shutil.copy2(ROOT/'phase4_5/guest'/f,APP/f)
(MAC/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'research.machprobe.NativeArena','CFBundleExecutable':'Arena','CFBundleName':'Arena','CFBundlePackageType':'APPL','NSHighResolutionCapable':True,'LSMinimumSystemVersion':'11.0'}))
run(['codesign','--force','--sign','-',MAC]);data=guest.read_bytes();manifest={'sha256':hashlib.sha256(data).hexdigest(),'size':len(data),'platform':'macOS','source':'phase4_5/guest/Game.m','resources':{f:hashlib.sha256((MAC/'Contents/Resources'/f).read_bytes()).hexdigest() for f in ['scene.metal','checker.rgba']}}
parsed=json.loads(run([ROOT/'build/machprobe','inspect',guest,'--json']));(OUT/'guest-macho.json').write_text(json.dumps(parsed,indent=2));assert parsed['build_versions'][0]['platform']=='macOS' and parsed['header']['architecture']=='arm64'
textsize=next(s['filesize'] for s in parsed['segments'] if s['name']=='__TEXT');(OUT/'guestT.bin').write_bytes(data[:textsize]);(OUT/'guestD.bin').write_bytes(data[textsize:]);(OUT/'empty.s').write_text('.section __TEXT,__text,regular,pure_instructions\n');target='arm64-apple-ios14.0'
run(['xcrun','clang','-target',target,'-isysroot',ios,'-c',OUT/'empty.s','-o',OUT/'empty.o']);container=APP/'Frameworks/ArenaGuest.dylib'
run(['xcrun','ld','-dylib',OUT/'empty.o','-arch','arm64','-platform_version','ios','14.0','27.0','-syslibroot',ios,'-lSystem','-sectcreate','__TEXT','__guest',OUT/'guestT.bin','-sectcreate','__DATA','__guest',OUT/'guestD.bin','-sectalign','__TEXT','__guest','4000','-sectalign','__DATA','__guest','4000','-install_name','@rpath/ArenaGuest.dylib','-o',container]);run(['codesign','--force','--sign','-',container])
objects=[]
for src in [*[ROOT/'runtime'/n for n in ['image.c','fixups.c','services.c','tls.c','group.c']],ROOT/'phase4_5/host/GameBridge.m',ROOT/'phase4_5/host/Main.m']:
 obj=OUT/(src.stem+'.o');run(['xcrun','clang','-target',target,'-isysroot',ios,'-O1','-g','-Wall','-Wextra','-I'+str(ROOT/'runtime'),*(['-fobjc-arc'] if src.suffix=='.m' else []),'-c',src,'-o',obj]);objects.append(obj)
run(['xcrun','clang','-target',target,'-isysroot',ios,*objects,'-framework','Foundation','-framework','UIKit','-framework','Metal','-framework','MetalKit','-framework','QuartzCore','-framework','CoreFoundation','-framework','AudioToolbox','-framework','CoreGraphics','-o',APP/'ArenaHost'])
(APP/'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'research.machprobe.Arena','CFBundleExecutable':'ArenaHost','CFBundleName':'ArenaHost','CFBundleDisplayName':'Mac Metal Arena','CFBundlePackageType':'APPL','CFBundleShortVersionString':'1.0','CFBundleVersion':'1','CFBundleSupportedPlatforms':['iPhoneOS'],'MinimumOSVersion':'14.0','LSRequiresIPhoneOS':True,'UIDeviceFamily':[1,2],'UILaunchScreen':{},'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False}}));(APP/'guest.json').write_text(json.dumps(manifest,indent=2));(OUT/'guest.json').write_text(json.dumps(manifest,indent=2))
run(['codesign','--force','--sign','-',APP]);run(['codesign','--verify','--strict',APP]);assert guest.read_bytes()==data
with zipfile.ZipFile(OUT/'ArenaHost.ipa','w',zipfile.ZIP_DEFLATED) as z:
 for f in sorted(APP.rglob('*')):
  if f.is_file():z.write(f,f.relative_to(OUT))
print(OUT/'ArenaHost.ipa')
