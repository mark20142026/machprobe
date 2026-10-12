#!/usr/bin/env python3
"""Control only the experimental runtime host in the existing iphone VM."""
import argparse,base64,json,subprocess,time,uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'build/phase4-runtime';BUNDLE='research.machprobe.MacGuest'
p=argparse.ArgumentParser();p.add_argument('action',choices=['install','launch','report','crash']);a=p.parse_args()
def rpc(method,params):
 r=subprocess.run(['vphone-launchpad-cli','guest','rpc','iphone',method,json.dumps(params)],capture_output=True,text=True)
 if r.returncode:raise RuntimeError(r.stderr.strip())
 return json.loads(r.stdout)['result']
if a.action=='install':
 try:rpc('apps.terminate',{'bundle_id':BUNDLE})
 except RuntimeError as e:
  if 'app not found' not in str(e):raise
 data=(OUT/'MacGuest.ipa').read_bytes();home='/private/var/mobile/ipas/MacGuest.ipa';tmp='/private/var/tmp/guest-'+str(uuid.uuid4())+'.ipa'
 rpc('files.write',{'path':home,'encoding':'base64','content':base64.b64encode(data).decode()});rpc('files.copy',{'from':home,'to':tmp});print(rpc('apps.install',{'path':tmp}))
elif a.action=='launch':
 lock=rpc('device.info',{})['lock']
 if lock['locked'] and not lock['passcode_enabled']:
  rpc('input.button',{'name':'home'});time.sleep(.5);rpc('input.button',{'name':'home'})
 print(rpc('apps.launch',{'bundle_id':BUNDLE}))
elif a.action=='report':
 info=rpc('apps.info',{'bundle_id':BUNDLE})
 data=rpc('files.read',{'path':info['data_path']+'/Documents/runtime.json','limit':200000})['content']
 (OUT/'last-run.json').write_text(data);print(data)
else:
 files=rpc('files.list',{'path':'/var/mobile/Library/Logs/CrashReporter'})['entries']
 crashes=sorted([f for f in files if f['name'].startswith('MacGuest-')],key=lambda f:f['mtime'])
 if not crashes:print('No runtime crash report')
 else:
  f=crashes[-1];data=rpc('files.read',{'path':f['path'],'limit':300000})['content'];(OUT/f['name']).write_text(data)
  print(OUT/f['name'])
