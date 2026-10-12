#!/usr/bin/env python3
"""Observe/test the existing VM; this script changes no security settings."""
import argparse,base64,json,subprocess,time,uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'build/phase4.5';BUNDLE='research.machprobe.Arena'
def rpc(method,params={}):
 r=subprocess.run(['vphone-launchpad-cli','guest','rpc','iphone',method,json.dumps(params)],text=True,capture_output=True)
 if r.returncode:raise RuntimeError(r.stderr.strip())
 return json.loads(r.stdout)['result']
def report():
 info=rpc('apps.info',{'bundle_id':BUNDLE});return json.loads(rpc('files.read',{'path':info['data_path']+'/Documents/arena.json','limit':2000000})['content'])
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('action',choices=['install','launch','report','screenshot','crash']);p.add_argument('--output',type=Path);a=p.parse_args()
 if a.action=='install':
  try:rpc('apps.terminate',{'bundle_id':BUNDLE})
  except RuntimeError as e:
   if 'app not found' not in str(e):raise
  data=(OUT/'ArenaHost.ipa').read_bytes();home='/private/var/mobile/ipas/ArenaHost.ipa';tmp='/private/var/tmp/arena-'+str(uuid.uuid4())+'.ipa'
  rpc('files.write',{'path':home,'content':base64.b64encode(data).decode(),'encoding':'base64'});rpc('files.copy',{'from':home,'to':tmp});print(json.dumps(rpc('apps.install',{'path':tmp}),indent=2))
 elif a.action=='launch':
  lock=rpc('device.info')['lock']
  if lock['locked'] and not lock['passcode_enabled']:rpc('input.button',{'name':'home'});time.sleep(.5);rpc('input.button',{'name':'home'})
  print(json.dumps(rpc('apps.launch',{'bundle_id':BUNDLE}),indent=2))
 elif a.action=='report':
  r=report();(a.output or OUT/'last-run.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps({k:v for k,v in r.items() if k not in ['samples','cycles']},indent=2))
 elif a.action=='screenshot':
  r=rpc('screen.screenshot');data=next(v for v in r.values() if isinstance(v,str) and len(v)>1000);path=a.output or OUT/'screen.jpg';path.write_bytes(base64.b64decode(data));print(path)
 else:
  files=rpc('files.list',{'path':'/var/mobile/Library/Logs/CrashReporter'})['entries'];files=sorted([f for f in files if f['name'].startswith('ArenaHost-')],key=lambda f:f['mtime'])
  if files:
   f=files[-1];(OUT/f['name']).write_text(rpc('files.read',{'path':f['path'],'limit':500000})['content']);print(OUT/f['name'])
  else:print('No crash reports')
