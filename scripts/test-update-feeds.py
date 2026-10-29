import importlib.util,json,pathlib,tempfile,unittest
spec=importlib.util.spec_from_file_location('feeds',pathlib.Path(__file__).with_name('generate-update-feeds.py'));module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
class ReleaseFeedTests(unittest.TestCase):
 def prepare(self,root):
  for name in ['Joynite_0.6.0_x64-setup.exe','Joynite_0.6.0_amd64.AppImage','Joynite_0.6.0_amd64.deb','Joynite.app.tar.gz']:
   (root/name).write_bytes(b'fixture');(root/(name+'.sig')).write_text('fixture-signature')
  (root/'updater-platform.json').write_text(json.dumps({'platform':'darwin-aarch64'}))
  (root/'Joynite-0.6.0-arm64.zip').write_bytes(b'native fixture')
  (root/'Joynite-0.6.0-arm64.signature.json').write_text(json.dumps({'version':'0.6.0','asset':'Joynite-0.6.0-arm64.zip','signature':'fixture-signature','length':14}))
 def test_complete_official_release_produces_matching_feeds(self):
  with tempfile.TemporaryDirectory() as tmp:
   root=pathlib.Path(tmp);self.prepare(root);manifest=module.create_feeds(root,'0.6.0')
   self.assertEqual(manifest['version'],'0.6.0');self.assertIn('linux-x86_64-deb',manifest['platforms']);self.assertIn('darwin-aarch64',manifest['platforms']);self.assertIn('edSignature',(root/'appcast.xml').read_text())
 def test_partial_unsigned_release_never_produces_a_feed(self):
  with tempfile.TemporaryDirectory() as tmp:
   root=pathlib.Path(tmp);self.prepare(root);(root/'Joynite_0.6.0_amd64.deb.sig').unlink()
   with self.assertRaises(ValueError):module.create_feeds(root,'0.6.0')
   self.assertFalse((root/'latest.json').exists())
 def test_mismatched_version_and_prerelease_are_rejected(self):
  with tempfile.TemporaryDirectory() as tmp:
   root=pathlib.Path(tmp);self.prepare(root)
   with self.assertRaises(ValueError):module.create_feeds(root,'0.7.0')
   with self.assertRaises(ValueError):module.create_feeds(root,'0.6.0-rc.1')
if __name__=='__main__':unittest.main()
