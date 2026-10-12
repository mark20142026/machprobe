#!/usr/bin/env python3
"""Package the unchanged SuperTuxKart arm64 images for iOS: one signed container
dylib per guest image (exact bytes in __TEXT/__DATA __guest sections), plus a
copy of the guest's compact unwind table rebased to the container so libunwind
(which asks dyld first) can unwind C++ exceptions through guest code.
Only our runtime and adapters are compiled. Usage: build.py [--quick]
(--quick reuses existing containers when the guest bytes are unchanged)."""
import hashlib,json,os,plistlib,struct,subprocess,sys,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'build/phase6-runtime';APP=OUT/'Payload/STKHost.app'
THIN=ROOT/'build/stk/thin';WORK=OUT/'containers'
env=dict(os.environ,DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
def run(args):return subprocess.check_output([str(x) for x in args],env=env,text=True).strip()
sdk=run(['xcrun','--sdk','iphoneos','--show-sdk-path']);target='arm64-apple-ios14.0'

def sections(data):
    """Segments and sections of a thin 64-bit Mach-O."""
    magic,cpu,sub,ftype,ncmds,sizeofcmds,flags,_=struct.unpack_from('<8I',data,0)
    assert magic==0xfeedfacf,hex(magic)
    segs=[];secs=[];off=32
    for _ in range(ncmds):
        cmd,size=struct.unpack_from('<2I',data,off)
        if cmd==0x19:
            name=data[off+8:off+24].rstrip(b'\0').decode();vmaddr,vmsize,fileoff,filesize=struct.unpack_from('<4Q',data,off+24)
            nsects=struct.unpack_from('<I',data,off+64)[0];segs.append((name,vmaddr,vmsize,fileoff,filesize))
            for j in range(nsects):
                s=off+72+80*j;sect=data[s:s+16].rstrip(b'\0').decode();seg=data[s+16:s+32].rstrip(b'\0').decode()
                addr,ssize=struct.unpack_from('<2Q',data,s+32);soff=struct.unpack_from('<I',data,s+48)[0]
                secs.append((seg,sect,addr,ssize,soff))
        off+=size
    return segs,secs

def rebase_unwind(blob,delta):
    """Shift every image-relative offset in a compact unwind table by delta.
    Compressed second-level entries are relative to their index entry and need
    no change. DWARF-mode entries point into __eh_frame, which is not copied."""
    u=bytearray(blob);stats={'dwarf':0,'functions':0}
    def add(o):struct.pack_into('<I',u,o,struct.unpack_from('<I',u,o)[0]+delta)
    version,common_off,common_n,pers_off,pers_n,index_off,index_n=struct.unpack_from('<7I',u,0)
    assert version==1,version
    dwarf=lambda e:(e&0x0f000000)==0x03000000
    stats['dwarf']+=sum(dwarf(struct.unpack_from('<I',u,common_off+4*i)[0]) for i in range(common_n))
    for i in range(pers_n):add(pers_off+4*i)
    index=[struct.unpack_from('<3I',u,index_off+12*i) for i in range(index_n)]
    for i,(func,second,lsda) in enumerate(index):
        add(index_off+12*i)
        if i+1<index_n:
            for o in range(lsda,index[i+1][2],8):add(o);add(o+4)
        if not second:continue
        kind=struct.unpack_from('<I',u,second)[0]
        if kind==2:
            entry_off,count=struct.unpack_from('<2H',u,second+4)
            for k in range(count):
                add(second+entry_off+8*k);stats['functions']+=1
                stats['dwarf']+=dwarf(struct.unpack_from('<I',u,second+entry_off+8*k+4)[0])
        elif kind==3:
            entry_off,count,enc_off,enc_n=struct.unpack_from('<4H',u,second+4);stats['functions']+=count
            stats['dwarf']+=sum(dwarf(struct.unpack_from('<I',u,second+enc_off+4*e)[0]) for e in range(enc_n))
        else:raise ValueError(f'unwind page kind {kind}')
    return bytes(u),stats

def container(index,name,data):
    segs,secs=sections(data)
    text=next(s for s in segs if s[0]=='__TEXT');assert text[3]==0
    textsize=text[4];segs=[s for s in segs if s[0]!='__PAGEZERO']
    base=min(s[1] for s in segs);span=max(s[1]+s[2] for s in segs)-base
    d=WORK/str(index);d.mkdir(parents=True,exist_ok=True)
    (d/'text.bin').write_bytes(data[:textsize]);(d/'data.bin').write_bytes(data[textsize:]+bytes(max(0,span-len(data))))
    unwind=next((s for s in secs if s[0]=='__TEXT' and s[1]=='__unwind_info'),None)
    out=APP/'Frameworks'/f'MPGuest-{index}.dylib'
    def link(unwind_blob):
        args=['xcrun','ld','-dylib',OUT/'empty.o','-arch','arm64','-platform_version','ios','14.0','27.0','-syslibroot',sdk,'-lSystem']
        if unwind_blob is not None:(d/'unwind.bin').write_bytes(unwind_blob);args+=['-sectcreate','__TEXT','__unwind_info',d/'unwind.bin']
        args+=['-sectcreate','__TEXT','__guest',d/'text.bin','-sectcreate','__DATA','__guest',d/'data.bin',
               '-sectalign','__TEXT','__guest','4000','-sectalign','__DATA','__guest','4000','-install_name',f'@rpath/MPGuest-{index}.dylib','-o',out]
        run(args);return next(s[2] for s in sections(out.read_bytes())[1] if s[0]=='__TEXT' and s[1]=='__guest')
    stats={}
    if unwind:
        original=data[unwind[4]:unwind[4]+unwind[3]]
        delta=link(original)                       # Same size, so the layout is final.
        shifted,stats=rebase_unwind(original,delta)
        assert link(shifted)==delta,'container layout moved'
    else:link(None)
    run(['codesign','--force','--sign','-',out])
    return {'name':name,'container':out.name,'sha256':hashlib.sha256(data).hexdigest(),'slice_size':len(data),'unwind':stats}

def main():
    (APP/'Frameworks').mkdir(parents=True,exist_ok=True);WORK.mkdir(parents=True,exist_ok=True)
    (OUT/'empty.s').write_text('.section __TEXT,__text,regular,pure_instructions\n')
    run(['xcrun','clang','-target',target,'-isysroot',sdk,'-c',OUT/'empty.s','-o',OUT/'empty.o'])
    images=[('supertuxkart',THIN/'supertuxkart')]+[(p.name,p) for p in sorted((THIN/'libs').glob('*.dylib'))]
    expected=dict(l.split()[::-1] for l in (THIN/'SHA256SUMS').read_text().splitlines())
    old={m['name']:m for m in json.loads((APP/'target.json').read_text())['images']} if (APP/'target.json').exists() and '--quick' in sys.argv else {}
    manifest=[]
    for i,(name,path) in enumerate(images):
        data=path.read_bytes();digest=hashlib.sha256(data).hexdigest()
        assert digest==expected[str(path.relative_to(ROOT/'build/stk'))],name  # Preserved release bytes only.
        if name in old and old[name]['sha256']==digest and (APP/'Frameworks'/old[name]['container']).exists():manifest.append(old[name]);continue
        manifest.append(container(i,name,data));print('container',i,name,manifest[-1]['unwind'])
    (APP/'target.json').write_text(json.dumps({'release':'SuperTuxKart-1.5-mac-signed.zip','images':manifest},indent=2))
    # Our runtime and adapters only.
    sources=[*[ROOT/'runtime'/p for p in ['image.c','fixups.c','services.c','tls.c','group.c']],ROOT/'phase4/runtime/Extended.c',ROOT/'phase4_5/host/GameBridge.m',
        ROOT/'phase5/runtime/Policy.c',ROOT/'phase5_5/runtime/Policy.c',ROOT/'phase6/runtime/Policy.c',ROOT/'phase6/host/Main.m',
        *[ROOT/'phase5_5/runtime'/p for p in ['LazyImports.c','Constants.m','Display.m','LegacyMetal.m','BaseVertex.m','AudioDiagnostics.m','Keyboard.m','ObjCRuntime.m']],
        *[ROOT/'phase5_5/tests'/p for p in ['MetalProbe.m','UIKitProbe.m','AudioProbe.m']],
        *[ROOT/'phase5/runtime'/p for p in ['AppKitCompat.m','Lifecycle.m','Menu.m','Updater.m','Window.m','MetalCompat.m','Input.m','Observe.m','Controls.m']],
        ROOT/'phase4/runtime/ImageShim.m',*sorted((ROOT/'phase6/runtime').glob('*.m')),*sorted((ROOT/'phase6/tests').glob('*.m'))]
    objects=[]
    for source in sources:
        obj=OUT/('_'.join(source.relative_to(ROOT).with_suffix('').parts)+'.o')
        run(['xcrun','clang','-target',target,'-isysroot',sdk,'-g','-O1','-I'+str(ROOT/'runtime'),'-I'+str(ROOT/'phase4/runtime'),'-I'+str(ROOT/'phase4_5/host'),'-I'+str(ROOT/'phase5/runtime'),
             *(['-fobjc-arc'] if source.suffix=='.m' else []),'-c',source,'-o',obj]);objects.append(obj)
    run(['xcrun','swiftc','-target',target,'-sdk',sdk,'-parse-as-library','-import-objc-header',ROOT/'phase4/runtime/ImageShim.h','-emit-object',ROOT/'phase4/runtime/ImageShim.swift','-o',OUT/'SwiftShim.o'])
    run(['xcrun','swiftc','-target',target,'-sdk',sdk,*objects,OUT/'SwiftShim.o',*sum([['-framework',f] for f in ['Foundation','UIKit','Metal','MetalKit','QuartzCore','CoreGraphics','CoreText','CoreFoundation','AudioToolbox','AVFAudio','IOSurface','GameController']],[]),
         '-Xlinker','-export_dynamic','-Xlinker','-rpath','-Xlinker','@executable_path/Frameworks','-o',APP/'STKHost'])
    seed=ROOT/'phase6/host/config-seed.xml'
    if seed.exists():(APP/'config-seed.xml').write_bytes(seed.read_bytes())
    info={'CFBundleIdentifier':'research.machprobe.STKHost','CFBundleExecutable':'STKHost','CFBundleName':'STKHost','CFBundleDisplayName':'SuperTuxKart research runtime',
          'CFBundlePackageType':'APPL','CFBundleShortVersionString':'1.0','CFBundleVersion':'1','CFBundleSupportedPlatforms':['iPhoneOS'],'LSRequiresIPhoneOS':True,
          'MinimumOSVersion':'14.0','UIDeviceFamily':[1,2],'UIRequiresFullScreen':True,'UIStatusBarHidden':True,
          'UISupportedInterfaceOrientations':['UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight'],
          'UILaunchScreen':{},'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False}}
    (APP/'Info.plist').write_bytes(plistlib.dumps(info))
    run(['codesign','--force','--sign','-',APP])
    with zipfile.ZipFile(OUT/'STKHost.ipa','w',zipfile.ZIP_DEFLATED) as z:
        for f in sorted(APP.rglob('*')):
            if f.is_file():z.write(f,f.relative_to(OUT))
    print(OUT/'STKHost.ipa')
if __name__=='__main__':main()
