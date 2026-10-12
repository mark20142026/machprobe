#!/usr/bin/env python3
"""Real VM touch input, sustained frames, unload/reload, and process relaunch."""
import argparse,json,time,base64
from pathlib import Path
from vm import rpc,report,BUNDLE,ROOT
p=argparse.ArgumentParser();p.add_argument('--seconds',type=int,default=180);a=p.parse_args();E=ROOT/'docs/evidence/phase4.5'
def save(name,r): (E/name).write_text(json.dumps(r,indent=2)+'\n')
def screen(name):
 r=rpc('screen.screenshot');data=next(v for v in r.values() if isinstance(v,str) and len(v)>1000);(E/name).write_bytes(base64.b64decode(data))
def button(name,hold=0):
 rows=rpc('ui.tree',{'max_elements':40})['elements'];b=next(x for x in rows if x['identifier']=='arena-'+name)
 rpc('input.long_press' if hold else 'input.tap',{'x':b['x'],'y':b['y'],**({'seconds':hold} if hold else {})})
 time.sleep(1.2)
results={'input':[]};before=report();assert before['verification']['passed'];assert before['guest']['device_class']=='MTLDebugDevice'
button('Reset');before=report()['guest'];button('W',1);after=report()['guest'];assert after['camera_z']<before['camera_z']-.5;assert after['events']>=before['events']+2
results['input'].append({'action':'hold W for one second','before':before,'after':after})
before=after;rpc('input.swipe',{'x1':180,'y1':350,'x2':260,'y2':350,'seconds':.5});time.sleep(1.2);after=report()['guest'];assert abs(after['yaw']-before['yaw'])>.1
results['input'].append({'action':'drag look','before':before,'after':after})
before=after;button('Space');after=report()['guest'];assert after['actions']==before['actions']+1 and not after['spinning'];time.sleep(2);paused=report()['guest'];assert abs(paused['angle']-after['angle'])<.001 and paused['frames']>after['frames']
results['input'].append({'action':'Space pauses animation while frames continue','before':before,'after':after,'later':paused});screen('interactive-scene.jpg');button('Space');button('Reset')
save('input.json',results);first=report();start=time.monotonic();print('Input passed; sustained rendering started',flush=True)
while time.monotonic()-start<a.seconds:
 time.sleep(min(20,a.seconds-(time.monotonic()-start)))
 r=report();assert r['pid']==first['pid'];assert r['guest']['gpu_errors']==0;assert r['guest']['frames']>first['guest']['frames']
 print(json.dumps({'seconds':round(time.monotonic()-start),'frames':r['guest']['frames'],'fps':r['guest']['fps'],'gpu_errors':r['guest']['gpu_errors']}),flush=True)
r=report();save('sustained.json',r);screen('sustained-scene.jpg');assert r['guest']['frames']-first['guest']['frames']>a.seconds*15
assert r['guest']['library_compiles']==r['guest']['pipeline_creations']==r['guest']['asset_textures']==1
assert r['guest']['sync_waits']==2
for i in range(5):
 button('Reload');r=report();assert r['verification']['passed'];assert r['guest']['frames']>0;assert r['guest']['gpu_errors']==0
 c=r['cycles'][-1];assert c['live_images_after']==0 and not c['bridge_after']['monitor_alive'] and not c['bridge_after']['surface_alive'];assert not c['after_stop']['running'];assert c['after_stop']['completed']==c['after_stop']['frames']
 print('Unload/reload cycle',i+1,'passed',flush=True)
save('reloads.json',r)
info=rpc('apps.info',{'bundle_id':BUNDLE});save('installed.json',info)
log=rpc('files.read',{'path':info['data_path']+'/Documents/metal-validation.log','limit':300000})['content'];(E/'ios-validation.txt').write_text(log)
assert 'Metal API Validation Enabled' in log and 'failed assertion' not in log and 'validateRender' not in log
old=r['pid'];rpc('apps.terminate',{'bundle_id':BUNDLE});rpc('apps.launch',{'bundle_id':BUNDLE});time.sleep(3);r=report();assert r['pid']!=old and r['verification']['passed'] and r['guest']['frames']>10;save('relaunch.json',r);print('Process relaunch passed',flush=True)
