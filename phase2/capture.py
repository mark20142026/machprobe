#!/usr/bin/env python3
"""Capture Phase 2 results without overwriting Phase 1 evidence."""
import datetime,hashlib,json,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'docs/evidence/phase2'
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def run(args,required=True):
 p=subprocess.run(list(map(str,args)),cwd=ROOT,capture_output=True,text=True,timeout=120)
 result=dict(argv=list(map(str,args)),returncode=p.returncode,stdout=p.stdout,stderr=p.stderr)
 if required and p.returncode:raise RuntimeError(json.dumps(result))
 return result
build=run(['make','-f','phase2/Makefile','all'])
baseline=json.loads((OUT/'baseline.json').read_text())
for path,expected in baseline['preserved_sha256'].items():assert digest(ROOT/path)==expected,path
sources=[p for folder in ['runtime','phase2'] for p in (ROOT/folder).rglob('*') if p.is_file() and '__pycache__' not in str(p)]
record={'captured_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'phase1_hashes_preserved':True,'build':build,
        'source_sha256':{str(p.relative_to(ROOT)):digest(p) for p in sources},'environment':{},'guests':{},'validation':{}}
for name,args in [('os',['sw_vers']),('sdk',['xcrun','--show-sdk-version']),('ios_sdk',['xcrun','--sdk','iphoneos','--show-sdk-path']),('simulator_sdk',['xcrun','--sdk','iphonesimulator','--show-sdk-path'])]:record['environment'][name]=run(args,False)
for path in [ROOT/'build'/n for n in ['hello','file_io','framework','metal_info']]+[ROOT/'build/phase2'/n for n in ['interactive','foundation','metal_compute']]:
 before=digest(path);args=[str(ROOT/'build')] if path.name=='file_io' else []
 record['guests'][path.name]={'sha256':before,'kind':'untouched macOS executable (original Phase 1 binary)' if path.parent.name=='build' else 'new macOS-target guest, unchanged after build','inspection':json.loads(run(['build/machprobe','inspect',path,'--json'])['stdout']), 'native':run([path,*args]),'through_runtime':run(['build/phase2/runner',path,*args]),'signature':run(['codesign','--verify','--strict',path])}
 assert digest(path)==before
for name,target in [('phase2_normal',['make','-f','phase2/Makefile','test']),('phase2_sanitizers',['make','-f','phase2/Makefile','sanitize']),('phase1_normal',['make','test']),('phase1_sanitizers',['make','test-sanitize']),('phase1_loader',['make','test-loader']),('phase1_loader_sanitizers',['make','test-loader-sanitize'])]:
 record['validation'][name]=run(target)
 print(name,'passed',flush=True)
for path,expected in baseline['preserved_sha256'].items():assert digest(ROOT/path)==expected,path
record['abi']=run(['build/phase2/abi-test','build/phase2/interactive'])
record['ios_preflight']=run(['phase2/ios/scripts/preflight.sh'],False)
(OUT/'results.json').write_text(json.dumps(record,indent=2)+'\n')
print('Saved',OUT/'results.json')
