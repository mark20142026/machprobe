#!/usr/bin/env python3
"""Bounded read-only sampling of an existing Veloren research session."""
import argparse, json, subprocess, time
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--samples',type=int,default=20);p.add_argument('--interval',type=float,default=10);p.add_argument('--out',type=Path,required=True);args=p.parse_args()
if not 2<=args.samples<=360 or not 1<=args.interval<=60:p.error('samples 2..360; interval 1..60 seconds')
def rpc(method,params):
 r=subprocess.run(['vphone-launchpad-cli','guest','rpc','iphone',method,json.dumps(params)],check=True,capture_output=True,text=True,timeout=20)
 return json.loads(r.stdout)['result']
bundle='research.machprobe.VelorenHost';path=rpc('apps.info',{'bundle_id':bundle})['data_path']+'/Documents/runtime.json';samples=[];started=time.monotonic()
for i in range(args.samples):
 report=json.loads(rpc('files.read',{'path':path,'limit':200000})['content'])
 processes=rpc('processes.list',{'filter':'VelorenHost'})['processes']
 sample={'utc':time.time(),'elapsed':time.monotonic()-started,'run_id':report.get('run_id'),'pid':report.get('pid'),'stage':report.get('stage'),'exception':report.get('exception'),'presentation':report.get('presentation'),'input':report.get('input'),'processes':processes}
 samples.append(sample);args.out.write_text(json.dumps({'samples':samples},indent=2))
 if not processes or (i and sample['run_id']!=samples[0]['run_id']):raise SystemExit('Session ended or changed; samples retained')
 if i+1<args.samples:time.sleep(args.interval)
print(f'Saved {len(samples)} samples to {args.out}')
