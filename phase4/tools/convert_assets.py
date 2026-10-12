#!/usr/bin/env python3
"""Convert catalog resource representations, never application code or layout."""
import hashlib,json,os,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'build/phase4-runtime';RAW=OUT/'decoded-assets';RAW.mkdir(parents=True,exist_ok=True)
APP=ROOT/'build/phase4/original/extracted/DashboardCalculator.app';CAR=APP/'Contents/Resources/Assets.car'
env=dict(os.environ,DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
def run(args):return subprocess.check_output([str(x) for x in args],env=env,text=True)
(OUT/'asset-info.json').write_text(run(['xcrun','assetutil','--info',CAR]))
run(['xcrun','clang','-fobjc-arc',ROOT/'phase4/tools/export_assets.m','-framework','AppKit','-framework','ImageIO','-o',OUT/'export-assets'])
run([OUT/'export-assets',APP,OUT/'asset-info.json',RAW])
CAT=OUT/'Converted.xcassets';CAT.mkdir(exist_ok=True)
(CAT/'Contents.json').write_text(json.dumps({'info':{'version':1,'author':'machprobe-resource-adapter'}}))
groups={}
for r in json.loads((RAW/'manifest.json').read_text()):groups.setdefault(r['name'],[]).append(r)
for name,records in groups.items():
 if '/' in name or name in ['.','..']:raise ValueError('unsafe asset name')
 image=records[0]['type']=='Image';directory=CAT/(name+('.imageset' if image else '.colorset'));directory.mkdir(exist_ok=True)
 items=[]
 for r in records:
  item={'idiom':'universal'}
  if r['appearance']=='dark':item['appearances']=[{'appearance':'luminosity','value':'dark'}]
  if image:
   scale=r['pixel_width']/r['point_width'];assert scale in [1,2,3]
   item.update(filename=r['file'],scale=f'{int(scale)}x');shutil.copy2(RAW/r['file'],directory/r['file'])
  else:
   item['color']={'color-space':'srgb','components':dict(zip(['red','green','blue','alpha'],map(str,r['rgba'])))}
  items.append(item)
 (directory/'Contents.json').write_text(json.dumps({'info':{'version':1,'author':'machprobe-resource-adapter'},'images' if image else 'colors':items},indent=2))
(OUT/'asset-conversion.json').write_text(json.dumps({'original_car_sha256':hashlib.sha256(CAR.read_bytes()).hexdigest(),'asset_count':len(groups),'decoded':json.loads((RAW/'manifest.json').read_text())},indent=2))
print(run(['xcrun','actool','--compile',OUT/'Payload/MacGuest.app','--platform','iphoneos','--minimum-deployment-target','14.0','--target-device','iphone','--target-device','ipad',CAT]))
