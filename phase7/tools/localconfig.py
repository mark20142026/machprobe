"""Per-user values (iPhone UDID, signing identity, Apple team, App ID prefix) live in the
git-ignored machprobe.local.json at the repository root, never in the code.
Create it with:  python3 phase8/tools/setup.py config"""
import json,plistlib,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];PATH=ROOT/'machprobe.local.json'
KEYS=('device_udid','signing_identity','team_id','bundle_prefix')
def load():
    if not PATH.exists():raise SystemExit(f'{PATH.name} is missing: run  python3 phase8/tools/setup.py config')
    c=json.loads(PATH.read_text());missing=[k for k in KEYS if not c.get(k)]
    if missing:raise SystemExit(f'{PATH.name} lacks {missing}: run  python3 phase8/tools/setup.py config')
    return c
def bundle(app):return load()['bundle_prefix']+'.'+app   # e.g. <prefix>.CP2077, <prefix>.STKHost
PROFILES=Path.home()/'Library/Developer/Xcode/UserData/Provisioning Profiles'
def profile_info(f):
    out=subprocess.run(['security','cms','-D','-i',str(f)],capture_output=True).stdout
    return plistlib.loads(out) if out else {}
def profile(bundle_id):
    """Newest provisioning profile whose App ID is exactly bundle_id (never just the newest overall)."""
    found=[f for f in PROFILES.glob('*.mobileprovision') if profile_info(f).get('Entitlements',{}).get('application-identifier','').split('.',1)[-1]==bundle_id]
    if not found:raise SystemExit(f'no provisioning profile for {bundle_id}: run  python3 phase8/tools/setup.py profile')
    return max(found,key=lambda f:f.stat().st_mtime)
