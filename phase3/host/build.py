#!/usr/bin/env python3
"""Build an iPhoneOS host with immutable encoded macOS guest resources."""
import base64,hashlib,json,os,plistlib,subprocess,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'build/phase3-ios'
APP=OUT/'Payload/MachProbe.app'
APP.mkdir(parents=True,exist_ok=True)
env=dict(os.environ,DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
def run(args): return subprocess.check_output([str(x) for x in args],env=env,text=True).strip()
sdk=run(['xcrun','--sdk','iphoneos','--show-sdk-path'])
# Keep the GUI guest a macOS executable; only its container targets iOS.
guestdir=ROOT/'build/phase3';guestdir.mkdir(exist_ok=True)
macsdk=subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'],text=True).strip()
subprocess.run(['xcrun','clang','-arch','arm64','-isysroot',macsdk,'-mmacosx-version-min=11.0','-g','-O0','-fno-objc-arc','-fno-objc-exceptions','-fno-exceptions','-Wl,-export_dynamic',str(ROOT/'phase3/guests/appkit_gui.m'),'-framework','AppKit','-o',str(guestdir/'appkit_gui')],check=True)
empty=OUT/'empty.s';empty.write_text('.section __TEXT,__text,regular,pure_instructions\n')
run(['xcrun','clang','-target','arm64-apple-ios14.0','-isysroot',sdk,'-c',empty,'-o',OUT/'empty.o'])
# A recompiled iOS counterpart is an admission control, never a macOS result.
control=OUT/'hello-ios'
run(['xcrun','clang','-target','arm64-apple-ios14.0','-isysroot',sdk,ROOT/'samples/hello.c','-o',control])
run(['codesign','--force','--sign','-',control])
(APP/'hello-ios.b64').write_bytes(base64.b64encode(control.read_bytes()))
manifest={}
frameworks=APP/'Frameworks';frameworks.mkdir(exist_ok=True)
for name in ['hello','interactive','file_io','framework','foundation','metal_info','metal_compute','appkit_gui']:
 p=ROOT/'build'/name if name in ['hello','file_io','framework','metal_info'] else ROOT/'build/phase2'/name
 if name=='appkit_gui':p=guestdir/name
 data=p.read_bytes();manifest[name]={'sha256':hashlib.sha256(data).hexdigest(),'size':len(data),'platform':'macOS','source':str(p.relative_to(ROOT))}
 parsed=json.loads(run([ROOT/'build/machprobe','inspect',p,'--json']))
 textsize=next(s['filesize'] for s in parsed['segments'] if s['name']=='__TEXT')
 manifest[name]['section']='__TEXT';manifest[name]['container']='MP'+name+'.dylib'
 textpart=OUT/(name+'T.bin');textpart.write_bytes(data[:textsize])
 datapart=OUT/(name+'D.bin');datapart.write_bytes(data[textsize:])
 library=frameworks/manifest[name]['container']
 run(['xcrun','ld','-dylib',OUT/'empty.o','-arch','arm64','-platform_version','ios','14.0','27.0','-syslibroot',sdk,'-lSystem','-sectcreate','__TEXT','__guest',textpart,'-sectcreate','__DATA','__guest',datapart,'-sectalign','__TEXT','__guest','4000','-sectalign','__DATA','__guest','4000','-install_name','@rpath/'+library.name,'-o',library])
 run(['codesign','--force','--sign','-',library])
 (APP/(name+'.b64')).write_bytes(base64.b64encode(data))
 assert base64.b64decode((APP/(name+'.b64')).read_bytes())==data
(APP/'guests.json').write_text(json.dumps(manifest,indent=2)+'\n')
sources=[*[ROOT/'phase3/host'/p for p in ['Main.m','signature_probe.m','AppKitBridge.m','MetalGuestView.m','Audit.m']],ROOT/'phase2/host/checks.c',*[ROOT/'runtime'/p for p in ['image.c','fixups.c','services.c','tls.c','group.c']]]
objects=[]
for source in sources:
 obj=OUT/(source.stem+'.o')
 run(['xcrun','clang','-target','arm64-apple-ios14.0','-isysroot',sdk,'-g','-O0','-Wall','-Wextra','-I'+str(ROOT/'runtime'),'-I'+str(ROOT/'phase2/host'),*(['-fobjc-arc'] if source.suffix=='.m' else []),'-c',source,'-o',obj]);objects.append(obj)
run(['xcrun','clang','-target','arm64-apple-ios14.0','-isysroot',sdk,*objects,'-framework','UIKit','-framework','Foundation','-framework','CoreFoundation','-framework','CoreGraphics','-framework','CoreText','-framework','QuartzCore','-framework','Metal','-lobjc','-o',APP/'MachProbe'])
info={'CFBundleIdentifier':'research.machprobe.Admission','CFBundleExecutable':'MachProbe','CFBundleName':'MachProbe','CFBundleDisplayName':'MachProbe iOS','CFBundlePackageType':'APPL','CFBundleShortVersionString':'1.0','CFBundleVersion':'1','CFBundleSupportedPlatforms':['iPhoneOS'],'LSRequiresIPhoneOS':True,'MinimumOSVersion':'14.0','UIDeviceFamily':[1,2],'UILaunchScreen':{}}
info['UIApplicationSceneManifest']={'UIApplicationSupportsMultipleScenes':False,'UISceneConfigurations':{'UIWindowSceneSessionRoleApplication':[{'UISceneConfigurationName':'Default','UISceneDelegateClassName':'SceneDelegate'}]}}
(APP/'Info.plist').write_bytes(plistlib.dumps(info))
run(['codesign','--force','--sign','-',APP]);run(['codesign','--verify','--strict',APP])
ipa=OUT/'MachProbe.ipa'
with zipfile.ZipFile(ipa,'w',zipfile.ZIP_DEFLATED) as z:
 for f in sorted(APP.rglob('*')):
  if f.is_file():z.write(f,f.relative_to(OUT))
print(ipa)
