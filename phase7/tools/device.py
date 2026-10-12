#!/usr/bin/env python3
"""Drive STKHost on the physical iPhone over USB (devicectl): install,
launch, pull report/logs, push files. Device, identity and App ID come from
machprobe.local.json (see localconfig.py)."""
import json,os,subprocess,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'build/phase7'
import localconfig
_cfg=localconfig.load();UDID=_cfg['device_udid'];BUNDLE=localconfig.bundle('STKHost')
ENV=dict(os.environ,DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
def dc(*args,check=True):
    r=subprocess.run(['xcrun','devicectl',*args],env=ENV,capture_output=True,text=True)
    if check and r.returncode:raise RuntimeError((r.stdout+r.stderr)[-800:])
    return r
def pull(name,dest=None):
    dest=dest or OUT/Path(name).name
    r=dc('device','copy','from','--device',UDID,'--domain-type','appDataContainer','--domain-identifier',BUNDLE,'--source','Documents/'+name,'--destination',str(dest),check=False)
    return dest.read_text(errors='replace') if r.returncode==0 and dest.exists() else ''
def push(local,remote):dc('device','copy','to','--device',UDID,'--domain-type','appDataContainer','--domain-identifier',BUNDLE,'--source',str(local),'--destination','Documents/'+remote)
def report():t=pull('runtime.json');return json.loads(t) if t else {}
if __name__=='__main__':
    a=sys.argv[1]
    if a=='launch':print(dc('device','process','launch','--device',UDID,'--terminate-existing',BUNDLE).stdout.strip()[-200:])
    elif a=='deploy':
        # Phase 6 build -> copy -> sign with the dev certificate and the newest
        # profile for this App ID -> install over USB.
        if '--no-build' not in sys.argv:subprocess.run([sys.executable,str(ROOT/'phase6/tools/build.py'),'--quick'],check=True,capture_output=True)
        import plistlib,shutil
        profile=localconfig.profile(BUNDLE)
        app=OUT/'STKHost.app';shutil.rmtree(app,ignore_errors=True);OUT.mkdir(parents=True,exist_ok=True)
        subprocess.run(['ditto',str(ROOT/'build/phase6-runtime/Payload/STKHost.app'),str(app)],check=True);shutil.copy(profile,app/'embedded.mobileprovision')
        prof=plistlib.loads(subprocess.run(['security','cms','-D','-i',str(profile)],capture_output=True,check=True).stdout)
        ent=OUT/'entitlements.plist';plistlib.dump(prof['Entitlements'],open(ent,'wb'))
        identity=_cfg['signing_identity']
        for f in sorted((app/'Frameworks').glob('*.dylib')):subprocess.run(['codesign','--force','--sign',identity,'--timestamp=none',str(f)],check=True,capture_output=True)
        subprocess.run(['codesign','--force','--sign',identity,'--timestamp=none','--entitlements',str(ent),str(app)],check=True,capture_output=True)
        print('signed; profile expires',prof['ExpirationDate']);print(dc('device','install','app','--device',UDID,str(app)).stdout.strip()[-120:])
    elif a=='install':print(dc('device','install','app','--device',UDID,str(OUT/'STKHost.app')).stdout.strip()[-200:])
    elif a=='report':
        r=report();print(json.dumps({k:r.get(k) for k in ['pid','stage','error','exception','sdl_error','rebases','binds','initializers','frame_window','base_vertex','verified_images']},indent=1)[:3000]);print('events:',r.get('events',[])[-12:])
        if r.get('stack'):print('\n'.join(r['stack'][:25]))
    elif a=='logs':
        for n in ['runtime-stderr.log','runtime-stdout.log']:print('==',n);print('\n'.join(pull(n).splitlines()[-int(sys.argv[2]) if len(sys.argv)>2 else -30:]))
    elif a=='args':
        p=OUT/'arguments.json';p.write_text(json.dumps(sys.argv[2:]));push(p,'arguments.json');print('arguments:',sys.argv[2:])
