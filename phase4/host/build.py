#!/usr/bin/env python3
"""Build only OUR diagnostic host; preserve the distributed app and slice bytes."""
import base64,hashlib,json,os,plistlib,subprocess,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]; OUT=ROOT/'build/phase4'
APP=OUT/'Payload/Phase4Probe.app';APP.mkdir(parents=True,exist_ok=True)
manifest=json.loads((OUT/'target.json').read_text())
exe=OUT/'original/extracted/DashboardCalculator.app/Contents/MacOS/DashboardCalculator'
for name,path in [('original',exe),('arm64',OUT/'selected-arm64')]:
 data=path.read_bytes();assert hashlib.sha256(data).hexdigest()==manifest[name+'_sha256']
 (APP/(name+'.b64')).write_bytes(base64.b64encode(data))
(APP/'target.json').write_bytes((OUT/'target.json').read_bytes())
env=dict(os.environ,DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
def run(args): return subprocess.check_output([str(x) for x in args],env=env,text=True).strip()
sources=[ROOT/'phase4/host/Probe.m',*[ROOT/'runtime'/p for p in ['image.c','fixups.c','services.c','tls.c','group.c']]]
libs=['-framework','Foundation','-framework','CoreFoundation','-framework','Metal','-lobjc']
for platform,main,output in [('macosx','CLI.m',OUT/'host-probe'),('iphoneos','Main.m',APP/'Phase4Probe')]:
 sdk=run(['xcrun','--sdk',platform,'--show-sdk-path']);target='arm64-apple-ios14.0' if platform=='iphoneos' else 'arm64-apple-macos11.0'
 objects=[]
 for source in [*sources,ROOT/'phase4/host'/main]:
  obj=OUT/(platform+'-'+source.stem+'.o')
  run(['xcrun','clang','-target',target,'-isysroot',sdk,'-Wall','-Wextra','-g','-O0','-I'+str(ROOT/'runtime'),*(['-fobjc-arc'] if source.suffix=='.m' else []),'-c',source,'-o',obj]);objects.append(obj)
 run(['xcrun','clang','-target',target,'-isysroot',sdk,*objects,*libs,*(['-framework','UIKit'] if platform=='iphoneos' else []),'-o',output])
info={'CFBundleIdentifier':'research.machprobe.Phase4Probe','CFBundleExecutable':'Phase4Probe','CFBundleName':'Phase4Probe','CFBundleDisplayName':'Phase 4 diagnostics','CFBundlePackageType':'APPL','CFBundleShortVersionString':'1.0','CFBundleVersion':'1','CFBundleSupportedPlatforms':['iPhoneOS'],'LSRequiresIPhoneOS':True,'MinimumOSVersion':'14.0','UIDeviceFamily':[1,2],'UILaunchScreen':{},'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False,'UISceneConfigurations':{'UIWindowSceneSessionRoleApplication':[{'UISceneConfigurationName':'Default','UISceneDelegateClassName':'Scene'}]}}}
(APP/'Info.plist').write_bytes(plistlib.dumps(info))
run(['codesign','--force','--sign','-',APP]);run(['codesign','--verify','--strict',APP])
with zipfile.ZipFile(OUT/'Phase4Probe.ipa','w',zipfile.ZIP_DEFLATED) as z:
 for p in sorted(APP.rglob('*')):
  if p.is_file():z.write(p,p.relative_to(OUT))
print(OUT/'Phase4Probe.ipa')
