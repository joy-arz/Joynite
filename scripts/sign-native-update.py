#!/usr/bin/env python3
import argparse, json, os, pathlib, re, subprocess, tempfile
p=argparse.ArgumentParser();p.add_argument('archive',type=pathlib.Path);p.add_argument('--tools',type=pathlib.Path,required=True);p.add_argument('--version',required=True);args=p.parse_args()
secret=os.environ.get('JOYNITE_SPARKLE_PRIVATE_KEY')
local=pathlib.Path.home()/'.joynite/signing/native.key'
if not secret and not local.exists():
    print('No native signing key available; installer built without update-feed metadata.');raise SystemExit(0)
with tempfile.TemporaryDirectory(prefix='joynite-sign-') as temporary:
    key=pathlib.Path(temporary)/'key'
    key.write_text(secret or local.read_text());key.chmod(0o600)
    signer=str(args.tools/'sign_update')
    output=subprocess.check_output([signer,'--ed-key-file',str(key),str(args.archive)],text=True)
    match=re.search(r'edsignature="([^"]+)"',output,re.IGNORECASE)
    if not match:raise SystemExit('Sparkle did not return an update signature.')
    signature=match[1]
    subprocess.run([signer,'--verify','--ed-key-file',str(key),str(args.archive),signature],check=True,capture_output=True)
    metadata={'version':args.version,'asset':args.archive.name,'signature':signature,'length':args.archive.stat().st_size}
    args.archive.with_suffix('.signature.json').write_text(json.dumps(metadata,indent=2)+'\n')
print('Native update archive signed and signature verified.')
