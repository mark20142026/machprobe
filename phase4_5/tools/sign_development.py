#!/usr/bin/env python3
"""Prepare an ordinary development IPA when the owner supplies a signing profile.

Does not install it. Use installd, not the VM research installer, for that test.
Never copies VM custom-trust or private-container entitlements.
"""
import argparse,datetime,fnmatch,hashlib,json,plistlib,shutil,subprocess,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'build/phase4.5'
p=argparse.ArgumentParser();p.add_argument('--profile',required=True,type=Path);p.add_argument('--identity',required=True);a=p.parse_args()
profile=plistlib.loads(subprocess.check_output(['security','cms','-D','-i',str(a.profile)]))
if profile['ExpirationDate']<=datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None):raise SystemExit('Provisioning profile has expired')
allowed=profile['Entitlements'];team=profile['TeamIdentifier'][0];bundle='research.machprobe.Arena';identifier=team+'.'+bundle
if not fnmatch.fnmatchcase(identifier,allowed['application-identifier']):raise SystemExit('Profile does not permit research.machprobe.Arena')
if not profile.get('ProvisionedDevices'):raise SystemExit('Use an iOS development profile listing the test device')
identities=subprocess.check_output(['security','find-identity','-v','-p','codesigning'],text=True)
if a.identity not in identities:raise SystemExit('Requested signing identity is not available')
app=OUT/'development/Payload/ArenaHost.app';shutil.copytree(OUT/'Payload/ArenaHost.app',app,dirs_exist_ok=True)
container=app/'Frameworks/ArenaGuest.dylib';before=container.read_bytes()
# Signing changes only the enclosing iOS signature, never the nested guest bytes.
parsed=json.loads(subprocess.check_output([ROOT/'build/machprobe','inspect',container,'--json']))
sections=[s for seg in parsed['segments'] for s in seg['sections'] if s['name']=='__guest'];sections.sort(key=lambda s:s['address'])
def guest(data):return b''.join(data[s['offset']:s['offset']+s['size']] for s in sections)
expected=json.loads((OUT/'guest.json').read_text())['sha256'];assert hashlib.sha256(guest(before)).hexdigest()==expected
entitlements={'application-identifier':identifier,'com.apple.developer.team-identifier':team,'get-task-allow':bool(allowed.get('get-task-allow',False))}
ent=OUT/'development/entitlements.plist';ent.write_bytes(plistlib.dumps(entitlements));shutil.copy2(a.profile,app/'embedded.mobileprovision')
subprocess.run(['codesign','--force','--sign',a.identity,container],check=True)
subprocess.run(['codesign','--force','--sign',a.identity,'--entitlements',ent,app],check=True)
subprocess.run(['codesign','--verify','--deep','--strict',app],check=True)
assert guest(container.read_bytes())==guest(before)
ipa=OUT/'ArenaHost-development.ipa'
with zipfile.ZipFile(ipa,'w',zipfile.ZIP_DEFLATED) as z:
 for f in sorted(app.rglob('*')):
  if f.is_file():z.write(f,f.relative_to(OUT/'development'))
print(ipa)
