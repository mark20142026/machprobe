#!/usr/bin/env python3
"""Install/observe only our app in an already configured vphone VM."""
import argparse,base64,json,subprocess,uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
BUNDLE='research.machprobe.Phase4Probe'
p=argparse.ArgumentParser();p.add_argument('action',choices=['install','launch','report']);p.add_argument('--vm',default='iphone');p.add_argument('--output',type=Path);args=p.parse_args()
def rpc(method,params):
 r=subprocess.run(['vphone-launchpad-cli','guest','rpc',args.vm,method,json.dumps(params)],capture_output=True,text=True)
 if r.returncode:raise RuntimeError(r.stderr.strip())
 result=json.loads(r.stdout)
 if not result.get('ok'):raise RuntimeError(result)
 return result['result']
if args.action=='install':
 data=(ROOT/'build/phase4/Phase4Probe.ipa').read_bytes()
 rpc('files.mkdir',{'path':'/private/var/mobile/ipas'})
 rpc('files.write',{'path':'/private/var/mobile/ipas/Phase4Probe.ipa','encoding':'base64','content':base64.b64encode(data).decode()})
 temporary='/private/var/tmp/phase4-'+str(uuid.uuid4())+'.ipa'
 rpc('files.copy',{'from':'/private/var/mobile/ipas/Phase4Probe.ipa','to':temporary})
 # First install has no running app to terminate. The installer handles upgrades.

 print(json.dumps(rpc('apps.install',{'path':temporary}),indent=2))
elif args.action=='launch':print(json.dumps(rpc('apps.launch',{'bundle_id':BUNDLE}),indent=2))
else:
 info=rpc('apps.info',{'bundle_id':BUNDLE})
 result=json.loads(rpc('files.read',{'path':info['data_path']+'/Documents/probe.json','limit':200000})['content'])
 if args.output:args.output.write_text(json.dumps(result,indent=2)+'\n')
 print(json.dumps({'run_id':result.get('run_id'),'pid':result.get('pid'),'complete':result.get('complete'),'loader':result.get('loader'),'missing_strong':result.get('missing_strong')},indent=2))
