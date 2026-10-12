#!/usr/bin/env python3
"""Install an IPA into the running vphone guest without the GUI.

Needs the VM launched with the host API (see progress.md, Phase 6 task 5):
  VPHONE_API_TOKEN=$(cat build/vm-api-token) vphone-cli vm launch iphone \
      --library-root ~/.vphone/machines --api-listen 127.0.0.1:18765
Streams the file with PUT /v1/files/content, then calls apps.install
(vphoned re-signs, installs and deletes the uploaded file)."""
import argparse,json,os,sys,time,urllib.request,urllib.error,urllib.parse
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
TOKEN=(ROOT/'build/vm-api-token').read_text().strip()
PORT=(ROOT/'build/vm-api-port').read_text().strip() if (ROOT/'build/vm-api-port').exists() else '18765'
BASE=f'http://127.0.0.1:{PORT}'
def request(method,path,body=None,content_type='application/json',timeout=600):
    r=urllib.request.Request(BASE+path,data=body,method=method,headers={'Authorization':'Bearer '+TOKEN,'Content-Type':content_type})
    try:
        with urllib.request.urlopen(r,timeout=timeout) as response:return response.read()
    except urllib.error.HTTPError as e:return e.read() # JSON {"error":...}; rpc() raises with it.
def rpc(method,params,timeout=600):
    reply=json.loads(request('POST','/v1/rpc',json.dumps({'method':method,'params':params}).encode(),timeout=timeout))
    if 'error' in reply or 'result' not in reply:raise RuntimeError(f'{method}: {reply.get("error",reply)}')
    return reply.get('result')
def upload(local,remote):
    size=os.path.getsize(local);started=time.monotonic()
    with open(local,'rb') as f:
        r=urllib.request.Request(f'{BASE}/v1/files/content?path={urllib.parse.quote(remote)}',data=f,method='PUT',
            headers={'Authorization':'Bearer '+TOKEN,'Content-Type':'application/octet-stream','Content-Length':str(size)})
        urllib.request.urlopen(r,timeout=1800).read()
    entry=[e for e in rpc('files.list',{'path':os.path.dirname(remote)})['entries'] if e['name']==os.path.basename(remote)]
    if not entry or entry[0].get('size')!=size:raise RuntimeError(f'upload size mismatch: {entry} vs {size}')
    print(f'uploaded {size/2**20:.1f} MiB in {time.monotonic()-started:.1f}s')
if __name__=='__main__':
    import urllib.parse
    p=argparse.ArgumentParser();p.add_argument('ipa');p.add_argument('--bundle-id');p.add_argument('--launch',action='store_true');a=p.parse_args()
    remote='/private/var/tmp/'+Path(a.ipa).name
    upload(a.ipa,remote)
    print('install:',json.dumps(rpc('apps.install',{'path':remote}))[:400])
    if a.launch and a.bundle_id:
        lock=rpc('device.info',{})['lock']
        if lock['locked'] and not lock['passcode_enabled']:
            rpc('input.button',{'name':'home'});time.sleep(.5);rpc('input.button',{'name':'home'})
        print('launch:',rpc('apps.launch',{'bundle_id':a.bundle_id}))
