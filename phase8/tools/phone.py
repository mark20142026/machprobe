#!/usr/bin/env python3
"""Cyberpunk 2077 on the physical iPhone over USB. App ID <bundle_prefix>.CP2077 from
machprobe.local.json: its own App ID, so no other project can replace it.
  phone.py check            device, Developer Mode, free space
  phone.py deploy           sign build/phase8-runtime CP2077Host.app + install
  phone.py push-data        copy archive/ engine/ r6/ into Documents/Cyberpunk 2077 (one folder at a time)
  phone.py launch | report | logs [N] | args ... | debug on|off"""
import json,plistlib,shutil,subprocess,sys,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'phase7/tools'))
import device as d   # devicectl helpers (UDID, BUNDLE, dc, pull, push)
import localconfig
BUNDLE=d.BUNDLE=localconfig.bundle('CP2077')
OUT=ROOT/'build/phase8-runtime';SIGNED=ROOT/'build/phase8-signed/CP2077Host.app'
GAME=Path.home()/'Library/Application Support/Steam/steamapps/common/Cyberpunk 2077'
IDENTITY=localconfig.load()['signing_identity']
def info():
    tmp=OUT/'device.json';d.dc('device','info','details','--device',d.UDID,'--json-output',str(tmp));return json.loads(tmp.read_text())['result']
def check():
    r=info();dp=r.get('deviceProperties',{});print('device:',r.get('hardwareProperties',{}).get('marketingName'),'iOS',dp.get('osVersionNumber'),'devmode:',dp.get('developerModeStatus'))
    tmp=OUT/'storage.json';rr=d.dc('device','info','lockState','--device',d.UDID,check=False);print(rr.stdout.strip()[-200:])
def deploy():
    PROFILE=localconfig.profile(BUNDLE)   # Newest profile for this App ID (setup.py profile makes one).
    prof=plistlib.loads(subprocess.run(['security','cms','-D','-i',str(PROFILE)],capture_output=True,check=True).stdout)
    shutil.rmtree(SIGNED,ignore_errors=True);SIGNED.parent.mkdir(parents=True,exist_ok=True)
    subprocess.run(['ditto',str(OUT/'Payload/CP2077Host.app'),str(SIGNED)],check=True);shutil.copy(PROFILE,SIGNED/'embedded.mobileprovision')
    ent=SIGNED.parent/'entitlements.plist';plistlib.dump(prof['Entitlements'],open(ent,'wb'))
    for f in sorted((SIGNED/'Frameworks').glob('*.dylib')):subprocess.run(['codesign','--force','--sign',IDENTITY,'--timestamp=none',str(f)],check=True,capture_output=True)
    subprocess.run(['codesign','--force','--sign',IDENTITY,'--timestamp=none','--entitlements',str(ent),str(SIGNED)],check=True,capture_output=True)
    print('signed (profile expires',prof['ExpirationDate'],')');print(d.dc('device','install','app','--device',d.UDID,str(SIGNED)).stdout.strip()[-150:])
def push_data():
    for folder in ['r6','engine','archive']:            # Small folders first; archive is ~60 GB.
        t=time.time();print('copying',folder,'...',flush=True)
        d.dc('device','copy','to','--device',d.UDID,'--domain-type','appDataContainer','--domain-identifier',d.BUNDLE,
             '--source',str(GAME/folder),'--destination','Documents/Cyberpunk 2077/'+folder)
        print(f'  {folder} done in {time.time()-t:.0f}s',flush=True)
if __name__=='__main__':
    a=sys.argv[1]
    if a=='check':check()
    elif a=='deploy':deploy()
    elif a=='push-data':push_data()
    elif a=='launch':print(d.dc('device','process','launch','--device',d.UDID,'--terminate-existing',d.BUNDLE).stdout.strip()[-200:])
    elif a=='report':
        r=d.report();print(json.dumps({k:r.get(k) for k in ['pid','stage','error','exception','load','gpu','data_present','memory_available_bytes','frame_window']},indent=1));print('events:',r.get('events',[])[-15:])
        if r.get('stack'):print('\n'.join(r['stack'][:25]))
    elif a=='logs':
        for n in ['runtime-stderr.log','runtime-stdout.log']:print('==',n);print('\n'.join(d.pull(n).splitlines()[-int(sys.argv[2]) if len(sys.argv)>2 else -30:]))
    elif a=='args':p=OUT/'arguments.json';p.write_text(json.dumps(sys.argv[2:]));d.push(p,'arguments.json');print('arguments:',sys.argv[2:])
    elif a=='debug':p=OUT/'debug';p.write_text('1');d.push(p,'debug') if sys.argv[2]=='on' else d.dc('device','copy','to','--device',d.UDID,'--domain-type','appDataContainer','--domain-identifier',d.BUNDLE,'--source',str(OUT/'empty'),'--destination','Documents/debug',check=False);print('debug',sys.argv[2])
