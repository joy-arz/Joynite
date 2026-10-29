import json,pathlib,plistlib,tomllib
root=pathlib.Path(__file__).resolve().parent.parent
versions={
 'native':plistlib.loads((root/'macos/Info.plist').read_bytes())['CFBundleShortVersionString'],
 'native build':plistlib.loads((root/'macos/Info.plist').read_bytes())['CFBundleVersion'],
 'shared':json.loads((root/'desktop/src-tauri/tauri.conf.json').read_text())['version'],
 'frontend':json.loads((root/'desktop/package.json').read_text())['version'],
 'frontend lock':json.loads((root/'desktop/package-lock.json').read_text())['version'],
 'frontend lock package':json.loads((root/'desktop/package-lock.json').read_text())['packages']['']['version'],
 'backend':tomllib.loads((root/'desktop/src-tauri/Cargo.toml').read_text())['package']['version']}
if len(set(versions.values()))!=1:raise SystemExit('Release versions differ: '+repr(versions))
print('All application release versions match:',next(iter(versions.values())))
