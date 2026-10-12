#!/usr/bin/env python3
"""Control only the experimental runtime host in the existing iphone VM."""
import argparse,base64,json,subprocess,time,uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'build/phase5.5-runtime';BUNDLE='research.machprobe.VelorenHost'
p=argparse.ArgumentParser();p.add_argument('action',choices=['install','launch','report','crash','logs','observe','screenshot','probe-metal','probe-uikit','probe-audio']);a=p.parse_args()
def rpc(method,params):
 r=subprocess.run(['vphone-launchpad-cli' ,'guest','rpc','iphone',method,json.dumps(params)],capture_output=True,text=True)
 if r.returncode:raise RuntimeError(r.stderr.strip())
 return json.loads(r.stdout)['result']
def unlock():
 lock=rpc('device.info',{})['lock']
 if lock['locked'] and not lock['passcode_enabled']:
  rpc('input.button',{'name':'home'});time.sleep(.5);rpc('input.button',{'name':'home'})
if a.action.startswith('probe-'):
 kind=a.action[6:];info=rpc('apps.info',{'bundle_id':BUNDLE});documents=info['data_path']+'/Documents/'
 before=rpc('files.read',{'path':documents+'runtime.json','limit':200000}).get('content','')
 old=json.loads(before).get('run_id') if before else None
 marker=documents+'run-'+kind+'-probe'
 rpc('files.write',{'path':marker,'content':'1'})
 try:
  unlock()
  rpc('apps.launch',{'bundle_id':BUNDLE})
  deadline=time.monotonic()+30
  while time.monotonic()<deadline:
   value=json.loads(rpc('files.read',{'path':documents+'runtime.json','limit':200000})['content'])
   if value.get('run_id')!=old:
    if kind+'_probe' in value:
     (OUT/(kind+'-probe.json')).write_text(json.dumps(value,indent=2))
     assert value[kind+'_probe']['passed'],value
     print(json.dumps(value[kind+'_probe'],indent=2));break
    if value.get('stage')=='exception':raise RuntimeError(value.get('exception'))
   time.sleep(.25)
  else:raise TimeoutError('probe did not finish: '+json.dumps(value))
 finally:rpc('files.remove',{'path':marker})
elif a.action=='install':
 raise SystemExit('Use the running vphone window Apps > Install App Package for this large IPA; RPC has a 1 MiB body limit.')
elif a.action=='launch':
 unlock()
 print(rpc('apps.launch',{'bundle_id':BUNDLE}))
elif a.action in ('report','observe'):
 info=rpc('apps.info',{'bundle_id':BUNDLE})
 data=rpc('files.read',{'path':info['data_path']+'/Documents/runtime.json','limit':200000})['content']
 (OUT/'last-run.json').write_text(data)
 if a.action=='report':print(data)
 else:
  value=json.loads(data);print(json.dumps({k:value.get(k) for k in ['pid','stage','exception']},indent=2));print(value.get('events',[])[-6:])
  for name in ['runtime-stderr.log','runtime-stdout.log']:
   log=rpc('files.read',{'path':info['data_path']+'/Documents/'+name,'limit':200000})['content'];(OUT/name).write_text(log)
   lines=log.splitlines();important=[line for line in lines if 'MISSING LAZY' in line or 'Panic reason:' in line or "reason: '" in line]
   print(name+'\n'+'\n'.join(important or lines[-3:]))
elif a.action=='screenshot':
 result=rpc('screen.screenshot',{});path=OUT/'last-screen.jpg';path.write_bytes(base64.b64decode(result['data']));print(path)
elif a.action=='logs':
 info=rpc('apps.info',{'bundle_id':BUNDLE})
 for name in ['runtime-stderr.log','runtime-stdout.log']:
  data=rpc('files.read',{'path':info['data_path']+'/Documents/'+name,'limit':200000})['content']
  (OUT/name).write_text(data);print(name+'\n'+data)
else:
 files=rpc('files.list',{'path':'/var/mobile/Library/Logs/CrashReporter'})['entries']
 crashes=sorted([f for f in files if f['name'].startswith('VelorenHost-')],key=lambda f:f['mtime'])
 if not crashes:print('No runtime crash report')
 else:
  f=crashes[-1];data=rpc('files.read',{'path':f['path'],'limit':300000})['content'];(OUT/f['name']).write_text(data)
  print(OUT/f['name'])
