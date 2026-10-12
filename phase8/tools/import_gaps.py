#!/usr/bin/env python3
"""Offline iOS import-gap analysis: every symbol the guest images import from a
system library, checked against the iOS SDK's .tbd export lists (following
re-exported libraries). Guest-to-guest imports are skipped. Writes
build/phase8/import-gaps.json and prints a per-library summary.
Usage: import_gaps.py DIR EXECUTABLE   (DIR holds EXECUTABLE + Frameworks/*.dylib)"""
import json,os,re,subprocess,sys
from collections import defaultdict
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
ENV=dict(os.environ,DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
SDK=subprocess.check_output(['xcrun','--sdk','iphoneos','--show-sdk-path'],env=ENV,text=True).strip()
def tbd_path(install):
    m=re.match(r'/System/Library/(Private)?Frameworks/(\w+)\.framework/(Versions/\w/)?(\w+)$',install)
    if m:return Path(SDK)/f'System/Library/{m.group(1) or ""}Frameworks/{m.group(2)}.framework/{m.group(4)}.tbd'
    if install.startswith('/usr/lib/'):return Path(SDK)/(install[1:].rsplit('.dylib',1)[0]+'.tbd')
    return None
_cache={}
def exports(install,seen=None):
    """Symbol set exported by install (incl. re-exports); None if absent on iOS."""
    seen=seen or set()
    if install in _cache:return _cache[install]
    p=tbd_path(install)
    if not p or not p.exists():
        # Versioned /usr/lib names (libbz2.1.0) map to the unversioned tbd.
        alt=re.sub(r'(\.\d+)+$','',str(p)[:-4])+'.tbd' if p else None
        if alt and Path(alt).exists():p=Path(alt)
        else:_cache[install]=None;return None
    text=p.read_text(errors='replace');syms=set()
    def lists(key):
        for m in re.finditer(key+r':\s*\[(.*?)\]',text,re.S):
            for tok in re.split(r'[,\s]+',m.group(1)):
                tok=tok.strip().strip("'\"")
                if tok:yield tok
    for k in ['symbols','weak-symbols','thread-local-symbols']:syms.update(lists(k))
    for c in lists('objc-classes'):syms.update({'_OBJC_CLASS_$_'+c,'_OBJC_METACLASS_$_'+c})
    for c in lists('objc-eh-types'):syms.add('_OBJC_EHTYPE_$_'+c)
    for c in lists('objc-ivars'):syms.add('_OBJC_IVAR_$_'+c)
    _cache[install]=syms
    for r in re.findall(r"libraries:\s*\[(.*?)\]",text,re.S):  # reexported-libraries
        for lib in re.split(r'[,\s]+',r):
            lib=lib.strip().strip("'\"")
            if lib.startswith('/') and lib not in seen and lib!=install:
                seen.add(lib);sub=exports(lib,seen)
                if sub:syms.update(sub)
    return syms
def image_imports(path):
    libs={}
    for line in subprocess.check_output(['otool','-L',str(path)],text=True).splitlines()[1:]:
        name=line.strip().split(' (')[0];leaf=name.rsplit('/',1)[-1]
        for k in {leaf,leaf.split('.')[0],re.sub(r'\.dylib$','',leaf)}:libs.setdefault(k,name)
    out=[]
    for line in subprocess.check_output(['xcrun','dyld_info','-imports',str(path)],env=ENV,text=True).splitlines():
        m=re.match(r'\s+0x[0-9A-Fa-f]+\s+(\S+)\s+\(from (.+?)\)',line)
        if m:out.append((m.group(1),libs.get(m.group(2),m.group(2))))
    return out
def main():
    d=Path(sys.argv[1]);images=[d/sys.argv[2]]+sorted((d/'Frameworks').glob('*.dylib'))
    gaps=defaultdict(set);counts=defaultdict(int)
    for img in images:
        for sym,lib in image_imports(img):
            if lib.startswith('@'):continue                      # guest member
            counts[lib]+=1;ex=exports(lib)
            if ex is None or sym not in ex:gaps[lib].add(f'{sym}  [{img.name}]')
    out=ROOT/'build/phase8/import-gaps.json';out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps({k:sorted(v) for k,v in gaps.items()},indent=1))
    print(f'{"library":72} imports missing')
    for lib in sorted(counts,key=lambda l:-len(gaps.get(l,()))):
        print(f'{lib[:72]:72} {counts[lib]:7} {len(gaps.get(lib,())):7}{"  (library absent on iOS)" if exports(lib) is None else ""}')
    print('total missing',sum(len(v) for v in gaps.values()),'->',out)
if __name__=='__main__':main()
