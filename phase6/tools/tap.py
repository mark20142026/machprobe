#!/usr/bin/env python3
"""Tap the VM screen at landscape screenshot pixels (2796x1290 frame) and
save a screenshot afterwards: tap.py X Y [wait]. Points = pixels / 3."""
import sys,time,base64
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'tools'))
import vphone_install as v
x,y=float(sys.argv[1]),float(sys.argv[2]);wait=float(sys.argv[3]) if len(sys.argv)>3 else 3
v.rpc('input.tap',{'x':x/3,'y':y/3});time.sleep(wait)
r=v.rpc('screen.screenshot',{});p=ROOT/'build/phase6-runtime/last-screen.jpg';p.write_bytes(base64.b64decode(r['data']));print(p)
