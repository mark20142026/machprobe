#!/usr/bin/env python3
"""Package the unchanged Cyberpunk 2077 (Steam macOS build 20383525) arm64 images
for iOS: one signed container per image (Phase 6 packaging, rebased unwind),
plus the lean Phase 8 host built with -O3 and LTO. App ID is ALWAYS
<bundle_prefix>.CP2077 from machprobe.local.json. Needs build/cyberpunk/thin
(python3 phase8/tools/setup.py prepare-game). Usage: build.py [--quick]"""
import hashlib,json,plistlib,sys,zipfile,importlib.util
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'phase7/tools'));import localconfig
spec=importlib.util.spec_from_file_location('p6',ROOT/'phase6/tools/build.py');p6=importlib.util.module_from_spec(spec);spec.loader.exec_module(p6)
OUT=ROOT/'build/phase8-runtime';APP=OUT/'Payload/CP2077Host.app';THIN=ROOT/'build/cyberpunk/thin'
p6.OUT,p6.APP,p6.WORK=OUT,APP,OUT/'containers'   # Reuse container() with our paths.
run,sdk,target=p6.run,p6.sdk,p6.target
def main():
    (APP/'Frameworks').mkdir(parents=True,exist_ok=True);p6.WORK.mkdir(parents=True,exist_ok=True)
    (OUT/'empty.s').write_text('.section __TEXT,__text,regular,pure_instructions\n')
    run(['xcrun','clang','-target',target,'-isysroot',sdk,'-c',OUT/'empty.s','-o',OUT/'empty.o'])
    images=[('Cyberpunk2077',THIN/'Cyberpunk2077')]+[(p.name,p) for p in sorted((THIN/'Frameworks').glob('*.dylib'))]
    expected=dict(l.split()[::-1] for l in (THIN/'SHA256SUMS').read_text().splitlines())
    old={m['name']:m for m in json.loads((APP/'target.json').read_text())['images']} if (APP/'target.json').exists() and '--quick' in sys.argv else {}
    manifest=[]
    for i,(name,path) in enumerate(images):
        data=path.read_bytes();digest=hashlib.sha256(data).hexdigest()
        assert digest==expected[str(path.relative_to(THIN))],name   # Preserved release bytes only.
        if name in old and old[name]['sha256']==digest and (APP/'Frameworks'/old[name]['container']).exists():manifest.append(old[name]);continue
        manifest.append(p6.container(i,name,data));print('container',i,name,manifest[-1]['unwind'],flush=True)
    (APP/'target.json').write_text(json.dumps({'release':'Cyberpunk 2077 Steam macOS build 20383525','images':manifest},indent=2))
    sources=[*[ROOT/'runtime'/p for p in ['image.c','fixups.c','services.c','tls.c','group.c']],ROOT/'phase4/runtime/Extended.c',ROOT/'phase4_5/host/GameBridge.m',
        ROOT/'phase5/runtime/Policy.c',ROOT/'phase5_5/runtime/Policy.c',
        *[ROOT/'phase5_5/runtime'/p for p in ['LazyImports.c','Constants.m','Display.m','LegacyMetal.m','BaseVertex.m','AudioDiagnostics.m','Keyboard.m','ObjCRuntime.m']],
        *[ROOT/'phase5_5/tests'/p for p in ['MetalProbe.m','UIKitProbe.m','AudioProbe.m']],
        *[ROOT/'phase5/runtime'/p for p in ['AppKitCompat.m','Lifecycle.m','Menu.m','Updater.m','Window.m','MetalCompat.m','Input.m','Observe.m','Controls.m']],
        ROOT/'phase4/runtime/ImageShim.m',
        *[ROOT/'phase6/runtime'/p for p in ['Desktop.m','AppKitExtras.m','Watchdog.m','FrameCounter.m']],
        ROOT/'phase8/runtime/Policy.c',ROOT/'phase8/runtime/CPDesktop.m',ROOT/'phase8/runtime/CPMetal.m',ROOT/'phase8/runtime/CPAppKit.m',ROOT/'phase8/runtime/CPControls.m',ROOT/'phase8/host/Main.m']
    objects=[]
    for source in sources:
        obj=OUT/('_'.join(source.relative_to(ROOT).with_suffix('').parts)+'.o')
        run(['xcrun','clang','-target',target,'-isysroot',sdk,'-g','-O3','-flto=thin','-I'+str(ROOT/'runtime'),'-I'+str(ROOT/'phase4/runtime'),'-I'+str(ROOT/'phase4_5/host'),'-I'+str(ROOT/'phase5/runtime'),
             *(['-fobjc-arc'] if source.suffix=='.m' else []),'-c',source,'-o',obj]);objects.append(obj)
    run(['xcrun','swiftc','-target',target,'-sdk',sdk,'-O','-parse-as-library','-import-objc-header',ROOT/'phase4/runtime/ImageShim.h','-emit-object',ROOT/'phase4/runtime/ImageShim.swift','-o',OUT/'SwiftShim.o'])
    run(['xcrun','swiftc','-target',target,'-sdk',sdk,*objects,OUT/'SwiftShim.o',*sum([['-framework',f] for f in ['Foundation','UIKit','Metal','MetalKit','QuartzCore','CoreGraphics','CoreText','CoreFoundation','AudioToolbox','AVFAudio','IOSurface','GameController','MetalFX']],[]),
         '-Xlinker','-export_dynamic','-Xlinker','-rpath','-Xlinker','@executable_path/Frameworks','-o',APP/'CP2077Host'])
    info={'CFBundleIdentifier':localconfig.bundle('CP2077'),'CFBundleExecutable':'CP2077Host','CFBundleName':'CP2077Host','CFBundleDisplayName':'Cyberpunk 2077',
          'CFBundlePackageType':'APPL','CFBundleShortVersionString':'1.0','CFBundleVersion':'2','CFBundleSupportedPlatforms':['iPhoneOS'],'LSRequiresIPhoneOS':True,
          'MinimumOSVersion':'15.0','UIDeviceFamily':[1,2],'UIRequiresFullScreen':True,'UIStatusBarHidden':True,'UIApplicationSupportsIndirectInputEvents':True,
          'UISupportedInterfaceOrientations':['UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight'],
          'GCSupportsControllerUserInteraction':True,'GCSupportedGameControllers':[{'ProfileName':'ExtendedGamepad'}],
          'UIFileSharingEnabled':True,'LSSupportsOpeningDocumentsInPlace':True,   # Finder can copy the game data into Documents.
          'UILaunchScreen':{},'CADisableMinimumFrameDurationOnPhone':True,   # ProMotion: allow 120 Hz
          'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False}}
    # App icon from the user's own installed game (never stored in the repo).
    icns=Path.home()/'Library/Application Support/Steam/steamapps/common/Cyberpunk 2077/Cyberpunk2077.app/Contents/Resources/AppIcon.icns'
    if icns.exists():
        run(['xcrun','swift',ROOT/'phase8/tools/make_icon.swift',icns,APP])
        info['CFBundleIcons']={'CFBundlePrimaryIcon':{'CFBundleIconFiles':['AppIcon60x60'],'CFBundleIconName':'AppIcon'}}
        info['CFBundleIcons~ipad']={'CFBundlePrimaryIcon':{'CFBundleIconFiles':['AppIcon60x60','AppIcon76x76','AppIcon83.5x83.5'],'CFBundleIconName':'AppIcon'}}
    (APP/'Info.plist').write_bytes(plistlib.dumps(info))
    (APP/'selectors.txt').write_bytes((ROOT/'phase8/host/selectors.txt').read_bytes())   # MP_SEL_SURVEY input.
    run(['codesign','--force','--sign','-',APP])
    with zipfile.ZipFile(OUT/'CP2077Host.ipa','w',zipfile.ZIP_DEFLATED) as z:
        for f in sorted(APP.rglob('*')):
            if f.is_file():z.write(f,f.relative_to(OUT))
    print(OUT/'CP2077Host.ipa')
if __name__=='__main__':main()
