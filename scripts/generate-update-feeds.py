#!/usr/bin/env python3
"""Build release feeds only after every required signed artifact is present."""
import argparse, datetime, hashlib, json, pathlib, re, urllib.parse, xml.etree.ElementTree as ET

def create_feeds(directory,version):
    if not re.fullmatch(r'(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)',version):raise ValueError('Official releases require a stable semantic version')
    directory=pathlib.Path(directory)
    files={p.name:p for p in directory.rglob('*') if p.is_file()}
    base=f'https://github.com/joy-arz/Joynite/releases/download/v{version}/'
    def url(name):return base+urllib.parse.quote(name)
    def signed(path):
        signature=files.get(path.name+'.sig')
        if signature is None or not signature.read_text().strip():raise ValueError('Missing signature for '+path.name)
        return {'url':url(path.name),'signature':signature.read_text().strip()}
    def one(suffix):
        matches=[p for p in files.values() if p.name.endswith(suffix)]
        if len(matches)!=1:raise ValueError(f'Expected one {suffix} package; got {len(matches)}')
        if suffix in {'-setup.exe','.AppImage','.deb'} and '_'+version+'_' not in matches[0].name:raise ValueError('Package version does not match release: '+matches[0].name)
        return matches[0]
    platforms={'windows-x86_64':signed(one('-setup.exe')),'linux-x86_64-appimage':signed(one('.AppImage')),'linux-x86_64-deb':signed(one('.deb'))}
    platforms['linux-x86_64']=platforms['linux-x86_64-appimage']
    mac_target=json.loads(one('updater-platform.json').read_text())['platform']
    if mac_target not in {'darwin-aarch64','darwin-x86_64'}:raise ValueError('Invalid shared macOS architecture')
    platforms[mac_target]=signed(one('.app.tar.gz'))
    native=json.loads(one('.signature.json').read_text())
    if native['version']!=version:raise ValueError('Native signature version does not match release')
    archive=files.get(native['asset'])
    if archive is None or archive.stat().st_size!=native['length'] or not native['signature']:raise ValueError('Native signature archive is missing or changed')
    now=datetime.datetime.now(datetime.timezone.utc)
    manifest={'version':version,'notes':f'Joynite {version}. Signed official update. Your library stays in place.','pub_date':now.isoformat().replace('+00:00','Z'),'platforms':platforms}
    (directory/'latest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    ET.register_namespace('sparkle','http://www.andymatuschak.org/xml-namespaces/sparkle')
    ns='{http://www.andymatuschak.org/xml-namespaces/sparkle}'
    rss=ET.Element('rss',{'version':'2.0'});channel=ET.SubElement(rss,'channel');ET.SubElement(channel,'title').text='Joynite updates'
    item=ET.SubElement(channel,'item');ET.SubElement(item,'title').text=f'Joynite {version}';ET.SubElement(item,ns+'version').text=version;ET.SubElement(item,ns+'shortVersionString').text=version;ET.SubElement(item,ns+'minimumSystemVersion').text='14.0'
    ET.SubElement(item,'enclosure',{'url':url(archive.name),'length':str(native['length']),'type':'application/octet-stream',ns+'edSignature':native['signature']})
    ET.ElementTree(rss).write(directory/'appcast.xml',encoding='utf-8',xml_declaration=True)
    return manifest

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('directory');parser.add_argument('--version',required=True);args=parser.parse_args()
    manifest=create_feeds(args.directory,args.version)
    print('Generated signed-update feeds for '+', '.join(sorted(manifest['platforms'])))
