#!/usr/bin/env python3
"""Drive the STK research host in the VM: install, launch, probe, report."""
import json,sys,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'tools'))
import vphone_install as v
BUNDLE='research.machprobe.STKHost';OUT=ROOT/'build/phase6-runtime'
def docs():return v.rpc('apps.info',{'bundle_id':BUNDLE})['data_path']+'/Documents/'
def read(name,limit=400000):
    try:return v.rpc('files.read',{'path':docs()+name,'limit':limit}).get('content','')
    except RuntimeError:return ''
def report():
    text=read('runtime.json');(OUT/'last-run.json').write_text(text);return json.loads(text) if text else {}
def stop():
    try:v.rpc('apps.terminate',{'bundle_id':BUNDLE})
    except RuntimeError:pass
    for _ in range(10):
        procs=v.rpc('processes.list',{'filter':'STKHost'})['processes']
        if not procs:return
        for p in procs:
            try:v.rpc('processes.kill',{'pid':p['pid'],'signal':'KILL','force':True})
            except RuntimeError as e:print('kill:',e)
        time.sleep(.5)
def launch(marker=None,wait=30,until=None):
    old=report().get('run_id')
    if marker:v.request('PUT','/v1/files/content?path='+docs()+marker,b'1','application/octet-stream')
    stop()
    lock=v.rpc('device.info',{})['lock']
    if lock['locked'] and not lock['passcode_enabled']:v.rpc('input.button',{'name':'home'});time.sleep(.5);v.rpc('input.button',{'name':'home'})
    for attempt in range(5):
        try:v.rpc('apps.launch',{'bundle_id':BUNDLE});break
        except RuntimeError as e:
            print('launch retry:',str(e)[:160]);time.sleep(2)
    deadline=time.monotonic()+wait;r={}
    while time.monotonic()<deadline:
        time.sleep(1);r=report()
        if r.get('run_id')!=old and (r.get('stage') in ('vertex probe complete','exception','group load failed','import probe complete','guest returned','container failed','guest hash mismatch') or (until and until(r))):break
    if marker:v.rpc('files.remove',{'path':docs()+marker})
    return r
def summary(r):
    print(json.dumps({k:r.get(k) for k in ['pid','stage','error','exception','rebases','binds','initializers']},indent=1))
    print('events:',r.get('events',[])[-10:])
    if r.get('main_stack_stalled'):print('STALLED MAIN STACK:\n  '+'\n  '.join(r['main_stack_stalled'][:30]))
    if r.get('main_stack_sample'):print('MAIN STACK SAMPLE:\n  '+'\n  '.join(r['main_stack_sample'][:30]))
    if r.get('sdl_error'):print('SDL error:',r['sdl_error'])
if __name__=='__main__':
    action=sys.argv[1]
    if action=='install':
        stop();print(v.rpc('apps.install',{'path':(v.upload(str(OUT/'STKHost.ipa'),'/private/var/tmp/STKHost.ipa'),'/private/var/tmp/STKHost.ipa')[1]})['bundle_id'])
    elif action=='probe':
        r=launch('run-import-probe',60);summary(r)
        for k,l in sorted(r.get('import_probe',{}).items()):print(f'\n## {k} ({len(l)})\n  '+'\n  '.join(sorted(l)))
    elif action=='survey':
        wait=float(sys.argv[2]) if len(sys.argv)>2 else 60
        taps=[tuple(map(float,t.split(','))) for t in sys.argv[3:] if ',' in t] # x,y points tapped after wait
        r=launch('run-selector-survey',wait)
        for x,y in taps:v.rpc('input.tap',{'x':x,'y':y});time.sleep(2)
        if '--keys' in sys.argv or True:
            for name in ['up','up','left','right','down','return','escape','space','a']:
                try:v.rpc('input.key',{'name':name})
                except RuntimeError as e:print('key',name,e)
                time.sleep(.4)
        if taps:time.sleep(10);r=report()
        summary(r)
        print('\n'.join(r.get('selector_survey',[])));print('sdl_error:',r.get('sdl_error'))
    elif action=='args':
        v.request('PUT','/v1/files/content?path='+docs()+'arguments.json',json.dumps(sys.argv[2:]).encode(),'application/octet-stream');print('arguments:',sys.argv[2:])
    elif action=='env':
        v.request('PUT','/v1/files/content?path='+docs()+'env.json',json.dumps(dict(a.split('=',1) for a in sys.argv[2:])).encode(),'application/octet-stream');print('env:',sys.argv[2:])
    elif action=='probe-vertex':
        r=launch('run-vertex-probe',30);print(json.dumps(r.get('vertex_probe'),indent=1))
    elif action=='launch':summary(launch(wait=float(sys.argv[2]) if len(sys.argv)>2 else 30))
    elif action=='report':summary(report())
    elif action=='logs':
        for n in ['runtime-stderr.log','runtime-stdout.log']:t=read(n);(OUT/n).write_text(t);print('==',n);print('\n'.join(t.splitlines()[-int(sys.argv[2]) if len(sys.argv)>2 else -40:]))
    elif action=='screenshot':
        import base64;r=v.rpc('screen.screenshot',{});p=OUT/'last-screen.jpg';p.write_bytes(base64.b64decode(r['data']));print(p)
