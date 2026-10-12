#!/usr/bin/env python3
"""Prepare black-box evidence and a byte-exact ARM64 slice; never read app source."""
import hashlib,json,plistlib,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'build/phase4'; EVIDENCE=ROOT/'docs/evidence/phase4'
APP=OUT/'original/extracted/DashboardCalculator.app'
EXE=APP/'Contents/MacOS/DashboardCalculator'
def digest(data): return hashlib.sha256(data).hexdigest()
def prepare():
    parsed=json.loads(subprocess.check_output([ROOT/'build/machprobe','inspect',EXE,'--arch','arm64','--json']))
    original=EXE.read_bytes(); offset=parsed['slice_offset']; size=parsed['slice_size']
    selected=original[offset:offset+size]
    assert parsed['header']['architecture']=='arm64' and len(selected)==size
    out=OUT/'selected-arm64';out.write_bytes(selected)
    info=plistlib.loads((APP/'Contents/Info.plist').read_bytes())
    record={'release':'v2.0-2203A1347','source':'https://github.com/elunico/DashboardCalculator/releases/download/v2.0-2203A1347/DashboardCalculator.app.zip',
            'version':info['CFBundleShortVersionString'],'build':info['CFBundleVersion'],
            'original_sha256':digest(original),'arm64_sha256':digest(selected),'slice_offset':offset,'slice_size':size,
            'slice_identity':'exact byte range from original universal executable; separate file, no re-signing',
            'build_versions':parsed['build_versions'],'libraries':parsed['dylibs'],'imports':parsed['undefined_symbols'],
            'resources':[str(p.relative_to(APP)) for p in sorted(APP.rglob('*')) if p.is_file()]}
    (OUT/'target.json').write_text(json.dumps(record,indent=2)+'\n')
    (EVIDENCE/'target.json').write_text(json.dumps(record,indent=2)+'\n')
    print(json.dumps({k:v for k,v in record.items() if k in ['original_sha256','arm64_sha256','slice_offset','slice_size']}))
if __name__=='__main__':prepare()
