#!/usr/bin/env python3
"""Install/observe only our app in an already configured vphone VM."""
import argparse,base64,json,subprocess,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
BUNDLE='research.machprobe.Admission'
p=argparse.ArgumentParser();p.add_argument('action',choices=['install','launch','report']);p.add_argument('--vm',default='iphone');p.add_argument('--output',type=Path);args=p.parse_args()
def rpc(method,params):
 r=subprocess.run(['vphone-launchpad-cli','guest','rpc',args.vm,method,json.dumps(params)],capture_output=True,text=True,check=True)
 result=json.loads(r.stdout)
 if not result.get('ok'):raise RuntimeError(result)
 return result['result']
if args.action=='install':
 data=(ROOT/'build/phase3-ios/MachProbe.ipa').read_bytes()
 rpc('files.mkdir',{'path':'/private/var/mobile/ipas'})
 rpc('files.write',{'path':'/private/var/mobile/ipas/MachProbe-iOS.ipa','encoding':'base64','content':base64.b64encode(data).decode()})
 rpc('files.copy',{'from':'/private/var/mobile/ipas/MachProbe-iOS.ipa','to':'/private/var/tmp/machprobe-install.ipa'})
 rpc('apps.terminate',{'bundle_id':BUNDLE})
 print(json.dumps(rpc('apps.install',{'path':'/private/var/tmp/machprobe-install.ipa'}),indent=2))
elif args.action=='launch':print(json.dumps(rpc('apps.launch',{'bundle_id':BUNDLE}),indent=2))
else:
 info=rpc('apps.info',{'bundle_id':BUNDLE})
 result=json.loads(rpc('files.read',{'path':info['data_path']+'/Documents/probe.json','limit':200000})['content'])
 if args.output:args.output.write_text(json.dumps(result,indent=2)+'\n')
 print(json.dumps({'run_id':result.get('run_id'),'pid':result.get('pid'),'complete':result.get('complete'),'guests':{n:{k:v for k,v in g.items() if k in ['passed','input_passed','error','stage']} for n,g in result.get('guests',{}).items()}},indent=2))
