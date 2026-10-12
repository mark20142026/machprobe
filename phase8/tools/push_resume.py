#!/usr/bin/env python3
"""Resumable Cyberpunk data copy to the iPhone: per-file, skips files whose
size already matches, verifies at the end. Run with NO other devicectl use."""
import json,os,subprocess,sys,time
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'phase7/tools'));import localconfig
UDID=localconfig.load()['device_udid'];BUNDLE=localconfig.bundle('CP2077')
GAME=Path.home()/'Library/Application Support/Steam/steamapps/common/Cyberpunk 2077'
ENV=dict(os.environ,DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer');TMP=Path(__file__).resolve().parents[2]/'build/phase8-runtime/remote.json'
def dc(*a):return subprocess.run(['xcrun','devicectl',*a],env=ENV,capture_output=True,text=True)
def remote(sub):
    dc('device','info','files','--device',UDID,'--domain-type','appDataContainer','--domain-identifier',BUNDLE,'--subdirectory','Documents/Cyberpunk 2077/'+sub,'--json-output',str(TMP))
    try:fs=json.loads(TMP.read_text())['result'].get('files',[])
    except Exception:fs=[]
    return {f['relativePath']:f['metadata']['size'] for f in fs if not f['resources']['isDirectory']}
def seed(sub,local):
    # A fresh phone has none of the folders. Copying a folder creates its whole tree (a single
    # file copy may not), so first copy a skeleton holding the smallest file of each folder
    # (hard links: no extra disk space).
    import shutil;stage=TMP.parent/'seed'/sub;shutil.rmtree(stage,ignore_errors=True)
    smallest={}
    for r,size in local.items():
        d=str(Path(r).parent)
        if d not in smallest or size<local[smallest[d]]:smallest[d]=r
    for r in smallest.values():
        (stage/r).parent.mkdir(parents=True,exist_ok=True)
        try:os.link(GAME/sub/r,stage/r)
        except OSError:shutil.copy2(GAME/sub/r,stage/r)
    res=dc('device','copy','to','--device',UDID,'--domain-type','appDataContainer','--domain-identifier',BUNDLE,'--source',str(stage),'--destination',f'Documents/Cyberpunk 2077/{sub}')
    if res.returncode:sys.exit(f'seeding {sub} failed: {(res.stdout+res.stderr).strip()[-300:]}')
    shutil.rmtree(stage,ignore_errors=True)
for sub in sys.argv[1:] or ['archive','engine','r6']:
    local={str(p.relative_to(GAME/sub)):p.stat().st_size for p in (GAME/sub).rglob('*') if p.is_file()}
    have=remote(sub)
    if not have:print(f'{sub}: new on the phone, creating folders ...',flush=True);seed(sub,local);have=remote(sub)
    todo=[r for r,s in local.items() if have.get(r)!=s]
    total=sum(local[r] for r in todo);done=0;t0=time.time()
    print(f'{sub}: {len(local)} files, {len(todo)} to copy ({total/2**30:.1f} GiB)',flush=True)
    for r in sorted(todo,key=lambda r:local[r]):
        for attempt in range(4):
            res=dc('device','copy','to','--device',UDID,'--domain-type','appDataContainer','--domain-identifier',BUNDLE,'--source',str(GAME/sub/r),'--destination',f'Documents/Cyberpunk 2077/{sub}/{r}')
            if res.returncode==0:break
            print(f'  retry {attempt+1} {r}: {(res.stdout+res.stderr).strip()[-160:]}',flush=True);time.sleep(5)
        else:sys.exit(f'FAILED {r}')
        done+=local[r];el=time.time()-t0
        print(f'  {done/2**30:6.1f}/{total/2**30:.1f} GiB  {done/2**20/max(el,1):5.0f} MB/s  {r}',flush=True)
    have=remote(sub);bad=[r for r,s in local.items() if have.get(r)!=s]
    print(f'{sub}: verify {"OK" if not bad else "MISMATCH "+str(bad[:5])}',flush=True)
    if bad:sys.exit(1)
print('ALL DATA ON PHONE',flush=True)
