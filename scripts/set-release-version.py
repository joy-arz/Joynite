#!/usr/bin/env python3
"""Advance only Joynite's own version fields, leaving dependency pins intact."""
import argparse,json,re
from pathlib import Path
root=Path(__file__).resolve().parent.parent
parser=argparse.ArgumentParser();parser.add_argument('version');version=parser.parse_args().version
if not re.fullmatch(r'(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)',version):raise SystemExit('Use a stable X.Y.Z release version')
for name in ['desktop/package.json','desktop/package-lock.json','desktop/src-tauri/tauri.conf.json']:
 p=root/name;value=json.loads(p.read_text(encoding='utf-8'));value['version']=version
 if name.endswith('package-lock.json'):value['packages']['']['version']=version
 p.write_text(json.dumps(value,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
p=root/'macos/Info.plist';text=p.read_text()
for key in ['CFBundleShortVersionString','CFBundleVersion']:
 text,count=re.subn(r'(<key>'+key+r'</key>\s*<string>)[^<]+(</string>)',lambda m:m[1]+version+m[2],text)
 if count!=1:raise SystemExit('Cannot locate '+key)
p.write_text(text)
p=root/'desktop/src-tauri/Cargo.toml';text,count=re.subn(r'(\[package\][\s\S]*?\nversion = ")[^"]+("\n)',lambda m:m[1]+version+m[2],p.read_text(),count=1)
if count!=1:raise SystemExit('Cannot locate Cargo package version')
p.write_text(text)
p=root/'desktop/src-tauri/Cargo.lock';text,count=re.subn(r'(\[\[package\]\]\nname = "joynite"\nversion = ")[^"]+("\n)',lambda m:m[1]+version+m[2],p.read_text(),count=1)
if count!=1:raise SystemExit('Cannot locate Joynite in Cargo.lock')
p.write_text(text)
print('Joynite version set to',version)
