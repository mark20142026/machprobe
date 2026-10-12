#!/usr/bin/env python3
"""Build our own unencrypted IPA, then adapt a COPY using PlayCover's platform idea.

This intentionally uses minimal declarations/link stubs, not a full iOS SDK.
No third-party application, DRM, system security setting or system file is modified.
"""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import zipfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
BUILD = ROOT/'build/phase2-ui'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--launch',action='store_true',help='Try original app and launch the adapted copy; requires a GUI session')
args = parser.parse_args()

BUILD.mkdir(parents=True,exist_ok=True)
record = {'captured_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'commands':[], 'limitations':'Minimal UIKit declarations and iOS link stubs; no complete iOS SDK, provisioning, or device validation. SDK field 0 is intentional.'}

def run(argv, required=True):
    argv = [str(v) for v in argv]
    p = subprocess.run(argv,cwd=ROOT,capture_output=True,text=True,timeout=60)
    result = {'argv':argv,'returncode':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
    record['commands'].append(result)
    if required and p.returncode: raise RuntimeError(json.dumps(result))
    return result

def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def inspected(path):
    return json.loads(run([ROOT/'build/machprobe','inspect',path,'--json'])['stdout'])

def text_bytes(path, image):
    section = next(s for seg in image['segments'] for s in seg['sections']
                   if s['segment']=='__TEXT' and s['name']=='__text')
    start = image['slice_offset']+section['offset']
    return path.read_bytes()[start:start+section['size']]

sdk = run(['xcrun','--show-sdk-path'])['stdout'].strip()
sources=[HERE/'Main.m', HERE/'checks.c', *[ROOT/'runtime'/n for n in ['image.c','fixups.c','services.c','tls.c','group.c']]]
objects=[]
for source in sources:
    obj=BUILD/(source.stem+'.o')
    flags=['-fobjc-arc'] if source.suffix=='.m' else []
    run(['xcrun','clang','-target','arm64-apple-ios14.0','-isysroot',sdk,'-DMP_MINIMAL_UIKIT=1','-I'+str(ROOT/'runtime'),*flags,'-c',source,'-o',obj])
    objects.append(obj)
symbols=set()
definitions=set()
for obj in objects:
    symbols.update(run(['nm','-u',obj])['stdout'].split())
    for line in run(['nm','-gU',obj])['stdout'].splitlines():
        if line.split(): definitions.add(line.split()[-1])
symbols=sorted(symbols-definitions)
groups = {'UIKit':[],'Foundation':[],'CoreFoundation':[],'Metal':['_MTLCreateSystemDefaultDevice'],'objc':[],'System':['dyld_stub_binder']}
for symbol in symbols:
    if symbol.startswith('_objc_msgSend$'):
        if '_objc_msgSend' not in groups['objc']: groups['objc'].append('_objc_msgSend')
    elif symbol=='___CFConstantStringClassReference': groups['CoreFoundation'].append(symbol)
    elif symbol.startswith(('_objc','__objc','_sel_')) or symbol in ['_OBJC_CLASS_$_NSObject','_OBJC_METACLASS_$_NSObject']: groups['objc'].append(symbol)
    elif symbol.startswith('_UI') or '$_UI' in symbol: groups['UIKit'].append(symbol)
    elif symbol.startswith(('_NS','_OBJC_CLASS_$_NS','_OBJC_METACLASS_$_NS')): groups['Foundation'].append(symbol)
    else: groups['System'].append(symbol)
stubs = BUILD/'stubs';stubs.mkdir(exist_ok=True)
for library, exports in groups.items():
    if library in ['objc','System']:
        name = '/usr/lib/lib'+library+('.A' if library=='objc' else '.B')+'.dylib'
    else:
        name = '/System/Library/Frameworks/'+library+'.framework/'+library
    text = ('--- !tapi-tbd\ntbd-version: 4\ntargets: [ arm64-ios ]\ninstall-name: "'+name+'"\n'
            'exports:\n  - targets: [ arm64-ios ]\n    symbols: [ '+', '.join("'"+s+"'" for s in exports)+' ]\n...\n')
    (stubs/(library+'.tbd')).write_text(text)
original = BUILD/'Payload/HelloIOS.app'
original.mkdir(parents=True,exist_ok=True)
run(['xcrun','ld','-arch','arm64','-platform_version','ios','14.0','0.0','-e','_main',*objects,
     *sorted(stubs.glob('*.tbd')),'-o',original/'HelloIOS'])
info = {'CFBundleDevelopmentRegion':'en','CFBundleDisplayName':'Hello iOS ARM64','CFBundleExecutable':'HelloIOS',
        'CFBundleIdentifier':'research.machprobe.HelloIOS','CFBundleInfoDictionaryVersion':'6.0','CFBundleName':'HelloIOS',
        'CFBundlePackageType':'APPL','CFBundleShortVersionString':'1.0','CFBundleVersion':'1',
        'CFBundleSupportedPlatforms':['iPhoneOS'],'LSRequiresIPhoneOS':True,'MinimumOSVersion':'14.0',
        'UIDeviceFamily':[1,2],'UILaunchScreen':{}}
info['CFBundleIdentifier']='research.machprobe.Phase2'
info['CFBundleDisplayName']='Interactive macOS guest'
guest_paths=[ROOT/'build'/n for n in ['hello','file_io','framework','metal_info']]+[ROOT/'build/phase2'/n for n in ['interactive','foundation','metal_compute']]
record['guest_sha256']={p.name:digest(p) for p in guest_paths}
for guest in guest_paths:
    shutil.copy2(guest,original/guest.name)
    assert inspected(guest)['build_versions'][0]['platform_id']==1
(original/'Info.plist').write_bytes(plistlib.dumps(info))
run(['codesign','--force','--sign','-',original])
run(['codesign','--verify','--strict',original])
original_image = inspected(original/'HelloIOS')
assert original_image['header']['architecture']=='arm64'
assert original_image['build_versions'][0]['platform_id']==2
assert original_image['build_versions'][0]['sdk']=='0.0.0'
assert not any(e['encrypted'] for e in original_image['encryption'])
original_hash = digest(original/'HelloIOS')
ipa = BUILD/'HelloIOS.ipa'
with zipfile.ZipFile(ipa,'w',zipfile.ZIP_DEFLATED) as archive:
    for file in sorted(original.rglob('*')):
        if file.is_file(): archive.write(file,file.relative_to(BUILD))
if args.launch: record['original_launch'] = run(['open','-n',original],required=False)
converted = BUILD/'HelloIOS-Catalyst.app'
shutil.copytree(original,converted,dirs_exist_ok=True)
info['CFBundleIdentifier'] += '.Catalyst'
info['CFBundleDisplayName'] = 'Interactive macOS guest'
info['LSMinimumSystemVersion'] = '11.0'
(converted/'Info.plist').write_bytes(plistlib.dumps(info))
converted_binary = converted/'HelloIOS'
run(['xcrun','vtool','-set-build-version','maccatalyst','11.0','14.0','-replace','-output',BUILD/'HelloIOS-converted',converted_binary])
shutil.copyfile(BUILD/'HelloIOS-converted',converted_binary)
converted_binary.chmod(0o755)
run(['codesign','--force','--sign','-',converted])
run(['codesign','--verify','--strict',converted])
converted_image = inspected(converted_binary)
assert converted_image['build_versions'][0]['platform_id']==6
assert text_bytes(original/'HelloIOS',original_image)==text_bytes(converted_binary,converted_image)
assert digest(original/'HelloIOS')==original_hash
for path in [original/'HelloIOS',converted_binary]:
    run(['xcrun','vtool','-show-build',path]);run(['otool','-L',path])
record.update({'original_sha256':original_hash,'converted_sha256':digest(converted_binary),'ipa_sha256':digest(ipa),
               'text_section_unchanged':True,'original_platform':2,'converted_platform':6,
               'source_sha256':{str(p.relative_to(ROOT)):digest(p) for p in [*sources,HERE/'UIKitHost.h',*sorted((ROOT/'runtime').glob('*.h')),Path(__file__)]}})
record['guest_hashes_preserved']=all(digest(converted/p.name)==digest(p)==record['guest_sha256'][p.name] for p in guest_paths)
assert record['guest_hashes_preserved']
if args.launch:
    record['converted_launch'] = run(['open','-n',converted])
    record['ui_validation'] = 'open returned successfully; visible UI must be checked separately (see the separate UI observation record)'
(ROOT/'docs/evidence/phase2/ui-build.json').write_text(json.dumps(record,indent=2)+'\n')
print('Built',ipa)
print('Adapted copy:',converted)
print('Verified platforms 2 -> 6; __TEXT,__text identical; original SHA-256 unchanged.')
