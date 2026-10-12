#!/usr/bin/env python3
"""One entry point for setting up Cyberpunk 2077 on your own iPhone with machprobe.
Every step is safe to re-run. Run them in this order (AGENT-SETUP.md explains each):

  setup.py doctor          check everything; prints PASS/FAIL with the fix for each FAIL
  setup.py config          detect iPhone, signing identity and Apple team -> machprobe.local.json
  setup.py prepare-game    copy + verify the game's 5 binaries from YOUR Steam install
  setup.py profile         register the App ID and make a provisioning profile (Xcode account)
  setup.py build           build the iOS app (CP2077Host)
  setup.py install         sign + install the app on the iPhone   (ask the user first)
  setup.py copy-data       copy the ~61 GB of game data to the iPhone (resumable, verified)
  setup.py restore         copy your Mac saves + recommended settings (never overwrites)
  setup.py launch          start the game on the iPhone             (ask the user first)

config takes optional overrides: --udid --identity --team --bundle-prefix.
prepare-game takes --steam <path to the 'Cyberpunk 2077' folder>.
restore takes --saves / --settings (default both) and --force."""
import json,os,platform,plistlib,re,shutil,subprocess,sys,hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'phase7/tools'))
import localconfig
XCODE='/Applications/Xcode.app/Contents/Developer'
ENV=dict(os.environ,DEVELOPER_DIR=XCODE)
STEAM=Path.home()/'Library/Application Support/Steam/steamapps'
GAME_DEFAULT=STEAM/'common/Cyberpunk 2077'
BUILD_ID='20383525'   # The Steam macOS build machprobe was made for (app 1091500).
KNOWN=ROOT/'phase8/cyberpunk-macos-20383525.sha256'
THIN=ROOT/'build/cyberpunk/thin'
WORK=ROOT/'build/setup'
MAC_SAVES=Path.home()/'Library/Application Support/CD Projekt Red/Cyberpunk 2077/saves'
PHONE_USER='Library/Application Support/CD Projekt Red/Cyberpunk 2077'
SETTINGS=ROOT/'phase8/config-recommended-UserSettings.json'
FREE_GB=65

def sh(*a,check=False,**k):return subprocess.run([str(x) for x in a],env=ENV,capture_output=True,text=True,check=check,**k)
def dc(*a,check=False):return sh('xcrun','devicectl',*a,check=check)
def say(ok,what,fix=''):
    print(f"{'PASS' if ok else 'FAIL'}  {what}"+('' if ok or not fix else f"\n      fix: {fix}"),flush=True);return ok
def tool(name,*a):
    r=subprocess.run([sys.executable,str(ROOT/'phase8/tools'/name),*a],env=ENV)
    if r.returncode:sys.exit(r.returncode)

# ---- detection ------------------------------------------------------------------------------
def devices():
    """Physical iPhones/iPads paired with this Mac: [(udid, name, developerModeStatus)]."""
    WORK.mkdir(parents=True,exist_ok=True);out=WORK/'devices.json'
    if dc('list','devices','--json-output',out).returncode or not out.exists():return []
    res=[]
    for d in json.loads(out.read_text())['result']['devices']:
        h,p=d.get('hardwareProperties',{}),d.get('deviceProperties',{})
        if h.get('reality')=='physical' and h.get('platform')=='iOS':
            res.append((h.get('udid'),h.get('marketingName') or h.get('deviceType'),p.get('developerModeStatus')))
    return res
def identities():
    """Apple Development signing identities in the keychain: [(sha1, label)]."""
    out=sh('security','find-identity','-v','-p','codesigning').stdout
    return [(m[1],m[2]) for m in re.finditer(r'\d+\) ([0-9A-F]{40}) "([^"]+)"',out) if 'Apple Development' in m[2]]
def teams():
    """Teams Xcode is signed in to: [(team_id, name, is_free)]."""
    out=subprocess.run(['defaults','export','com.apple.dt.Xcode','-'],capture_output=True).stdout
    try:prefs=plistlib.loads(out)
    except Exception:return []
    res=[]
    for lst in prefs.get('IDEProvisioningTeamByIdentifier',{}).values():
        for t in lst:res.append((t.get('teamID'),t.get('teamName'),bool(t.get('isFreeProvisioningTeam'))))
    return sorted(set(res))
def game_dir(args):
    i=args.index('--steam') if '--steam' in args else -1
    return Path(args[i+1]).expanduser() if i>=0 else GAME_DEFAULT
def steam_build():
    acf=STEAM/'appmanifest_1091500.acf'
    m=re.search(r'"buildid"\s+"(\d+)"',acf.read_text()) if acf.exists() else None
    return m[1] if m else None
def known():return dict(l.split()[::-1] for l in KNOWN.read_text().splitlines())
def sha(p):
    h=hashlib.sha256()
    with open(p,'rb') as f:
        for b in iter(lambda:f.read(1<<20),b''):h.update(b)
    return h.hexdigest()

# ---- commands -------------------------------------------------------------------------------
def doctor(args):
    ok=True
    ok&=say(platform.machine()=='arm64','Mac has Apple silicon','machprobe needs an M-series Mac to build')
    ok&=say(Path(XCODE).exists(),'Xcode is installed at /Applications/Xcode.app','install Xcode from the Mac App Store, open it once, accept the licence')
    g=game_dir(args)
    ok&=say((g/'Cyberpunk2077.app/Contents/MacOS/Cyberpunk2077').exists(),f'Cyberpunk 2077 (macOS) is installed via Steam',
            'in Steam on this Mac: install Cyberpunk 2077 (you must own it); or pass --steam <folder>')
    b=steam_build()
    ok&=say(b==BUILD_ID,f'Steam build is {BUILD_ID} (found {b})','other builds are untested; the binaries must match the known hashes (prepare-game checks)')
    ok&=say(THIN.joinpath('SHA256SUMS').exists(),'game binaries prepared (build/cyberpunk/thin)','run: setup.py prepare-game')
    cfg=localconfig.PATH.exists()
    ok&=say(cfg,'machprobe.local.json exists','run: setup.py config')
    ids=identities()
    ok&=say(bool(ids),'an "Apple Development" signing identity is in the keychain',
            'Xcode > Settings > Accounts: add your Apple ID, then Manage Certificates > + > Apple Development')
    ok&=say(bool(teams()),'Xcode is signed in to an Apple developer team','Xcode > Settings > Accounts: sign in with your Apple ID (a free account works)')
    devs=devices()
    ok&=say(bool(devs),'an iPhone is paired with this Mac','connect it by USB, unlock it, tap "Trust This Computer"')
    if cfg:
        c=localconfig.load();mine=[d for d in devs if d[0]==c['device_udid']]
        ok&=say(bool(mine),'the configured iPhone is visible','connect and unlock it, or re-run setup.py config')
        if mine:ok&=say(mine[0][2]=='enabled','Developer Mode is on',
                        'iPhone: Settings > Privacy & Security > Developer Mode > On, restart, confirm')
        ok&=say(c['signing_identity'] in [i[0] for i in ids],'the configured signing identity is in the keychain','re-run setup.py config')
        try:
            prof=localconfig.profile_info(localconfig.profile(localconfig.bundle('CP2077')))
            import datetime
            exp=prof['ExpirationDate'];left=(exp.replace(tzinfo=None)-datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)).days   # plist dates are UTC
            ok&=say(left>=0,f'provisioning profile valid ({left} days left)','run: setup.py profile, then setup.py install (keeps data)')
            ok&=say(c['device_udid'] in prof.get('ProvisionedDevices',[]),'profile includes this iPhone','run: setup.py profile')
            ok&=say(prof.get('Entitlements',{}).get('com.apple.developer.kernel.increased-memory-limit') is True,
                    'profile has the increased-memory-limit entitlement','run: setup.py profile')
        except SystemExit:ok&=say(False,'a provisioning profile exists for the Cyberpunk App ID','run: setup.py profile')
    print(f"NOTE  check the iPhone has at least {FREE_GB} GB free (Settings > General > iPhone Storage)")
    print('\nALL GOOD' if ok else '\nFix the FAIL lines above (top to bottom), then run doctor again.')
    return 0 if ok else 1

def config(args):
    def opt(n):return args[args.index(n)+1] if n in args else None
    devs=devices();ids=identities();tms=teams()
    udid=opt('--udid') or (devs[0][0] if len(devs)==1 else None)
    ident=opt('--identity') or (ids[0][0] if len(ids)==1 else None)
    team=opt('--team') or (tms[0][0] if len(tms)==1 else None)
    problems=[]
    if not udid:problems.append(('--udid',[f'{d[0]}  ({d[1]})' for d in devs] or ['no iPhone found: connect, unlock, trust this Mac']))
    if not ident:problems.append(('--identity',[f'{i[0]}  ({i[1]})' for i in ids] or ['none: Xcode > Settings > Accounts > Manage Certificates > + Apple Development']))
    if not team:problems.append(('--team',[f"{t[0]}  ({t[1]}{', free' if t[2] else ''})" for t in tms] or ['none: sign in to Xcode > Settings > Accounts']))
    if problems:
        for flag,choices in problems:print(f'choose {flag}:');[print('   ',c) for c in choices]
        print('re-run with the flag(s), e.g.  setup.py config --udid <UDID>');return 1
    # App IDs are unique across ALL Apple accounts, so default to a prefix unique to this team.
    prefix=opt('--bundle-prefix') or (json.loads(localconfig.PATH.read_text()).get('bundle_prefix') if localconfig.PATH.exists() else None) or f'machprobe.t{team.lower()}'
    localconfig.PATH.write_text(json.dumps({'device_udid':udid,'signing_identity':ident,'team_id':team,'bundle_prefix':prefix},indent=2)+'\n')
    print(f'wrote {localconfig.PATH.name} (git-ignored): App ID will be {prefix}.CP2077');return 0

def prepare_game(args):
    g=game_dir(args)/'Cyberpunk2077.app/Contents';want=known()
    if not g.exists():print(f'not found: {g}\nInstall Cyberpunk 2077 for macOS via Steam, or pass --steam <folder>');return 1
    shutil.rmtree(THIN,ignore_errors=True);(THIN/'Frameworks').mkdir(parents=True)
    for rel in want:
        src=g/('MacOS/'+rel if rel=='Cyberpunk2077' else rel);dst=THIN/rel
        if not src.exists():print(f'missing in your install: {src}');return 1
        # libsteam_api ships as universal (x86_64+arm64); machprobe loads only the arm64 slice.
        if 'arm64' in sh('lipo','-archs',src).stdout and len(sh('lipo','-archs',src).stdout.split())>1:sh('lipo',src,'-thin','arm64','-output',dst,check=True)
        else:shutil.copy2(src,dst)
    bad=[rel for rel,h in want.items() if sha(THIN/rel)!=h]
    if bad:
        print('these binaries differ from the supported build',BUILD_ID,':',bad)
        print('Your Steam copy is a different game version. machprobe was made for build',BUILD_ID,'; other builds may need changes.')
        return 1
    shutil.copy(KNOWN,THIN/'SHA256SUMS');print(f'OK: {len(want)} binaries copied from your install and verified (build {BUILD_ID})');return 0

def profile(args):
    c=localconfig.load();bid=localconfig.bundle('CP2077')
    print(f'registering App ID {bid} for team {c["team_id"]} (Xcode signs in with your account) ...',flush=True)
    r=sh('xcodebuild','-project',ROOT/'phase7/signing/Provisioner.xcodeproj','-configuration','Debug','-sdk','iphoneos',
         '-allowProvisioningUpdates',f'SYMROOT={WORK}/prov-build',f'OBJROOT={WORK}/prov-obj',
         f'PRODUCT_BUNDLE_IDENTIFIER={bid}',f'DEVELOPMENT_TEAM={c["team_id"]}','build')
    # The stub app may fail to link; only the profile Xcode creates on the way matters.
    try:p=localconfig.profile(bid)
    except SystemExit:
        print('no profile was created. xcodebuild said:');print('\n'.join(l for l in (r.stdout+r.stderr).splitlines() if 'error' in l.lower())[-1500:])
        print('Common causes: Xcode not signed in; iPhone not connected/registered; 10 App IDs per 7 days limit on free accounts.');return 1
    info=localconfig.profile_info(p);print(f'OK: profile {p.name}, expires {info["ExpirationDate"]}');return 0

def restore(args):
    c=localconfig.load();bid=localconfig.bundle('CP2077');both='--saves' not in args and '--settings' not in args
    def remote_has(path):
        # List the PARENT folder and look for the name: listing a file path itself reports nothing.
        # If the phone can't be listed, assume it exists, so nothing is overwritten by mistake.
        out=WORK/'remote.json';WORK.mkdir(parents=True,exist_ok=True);out.unlink(missing_ok=True)
        parent,name=path.rsplit('/',1)
        r=dc('device','info','files','--device',c['device_udid'],'--domain-type','appDataContainer','--domain-identifier',bid,'--subdirectory',parent,'--json-output',out)
        try:files=json.loads(out.read_text())['result'].get('files',[])
        except Exception:
            # Parent missing (fresh install) vs. phone unreachable: the container's Library always exists.
            ok=dc('device','info','files','--device',c['device_udid'],'--domain-type','appDataContainer','--domain-identifier',bid,'--subdirectory','Library').returncode==0
            if not ok:print('cannot read the phone (connected and unlocked?): not copying anything');sys.exit(1)
            return False
        return any(f['relativePath']==name or f['relativePath'].startswith(name+'/') for f in files)
    def push(src,dst):
        r=dc('device','copy','to','--device',c['device_udid'],'--domain-type','appDataContainer','--domain-identifier',bid,'--source',src,'--destination',dst)
        if r.returncode:print((r.stdout+r.stderr)[-400:]);sys.exit(1)
    if both or '--saves' in args:
        if not MAC_SAVES.exists():print(f'no Mac saves at {MAC_SAVES} (optional: start the game once on the Mac via Steam so Steam Cloud downloads them)')
        elif remote_has(PHONE_USER+'/saves') and '--force' not in args:print('phone already has saves: not touching them (use --force to overwrite)')
        else:
            stage=WORK/'saves';shutil.rmtree(stage,ignore_errors=True);shutil.copytree(MAC_SAVES,stage)
            (stage/'user.gls').unlink(missing_ok=True)   # EULA acceptance is per device: accept it once on the phone.
            push(stage,PHONE_USER+'/saves');print('OK: saves copied')
    if both or '--settings' in args:
        if remote_has(PHONE_USER+'/UserSettings.json') and '--force' not in args:print('phone already has UserSettings.json: not touching it (use --force)')
        else:push(SETTINGS,PHONE_USER+'/UserSettings.json');print('OK: recommended settings copied (1564x720, 60 fps cap)')
    return 0

if __name__=='__main__':
    a=sys.argv[1] if len(sys.argv)>1 else 'help';rest=sys.argv[2:]
    cmds={'doctor':doctor,'config':config,'prepare-game':prepare_game,'profile':profile,'restore':restore}
    if a in cmds:sys.exit(cmds[a](rest))
    elif a=='build':tool('build.py',*rest)
    elif a=='install':tool('phone.py','deploy')
    elif a=='copy-data':tool('push_resume.py','archive','engine','r6')
    elif a=='launch':tool('phone.py','launch')
    else:print(__doc__)
