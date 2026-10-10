"""Run with python scripts/test_configure_brand.py; no Flutter SDK required."""
import json
from pathlib import Path
import shutil
import tempfile
import unittest
import xml.etree.ElementTree as ET
from configure_brand import configure, ROOT


class BrandTests(unittest.TestCase):
    def test_android_ios_assets_and_idempotence(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / 'apps/organizer_flutter'
            shutil.copytree(ROOT / 'assets/brand', root / 'assets/brand')
            manifest = root / 'android/app/src/main/AndroidManifest.xml'
            manifest.parent.mkdir(parents=True)
            original = '<manifest xmlns:android="http://schemas.android.com/apk/res/android"><application android:label="Sendoh" android:icon="@mipmap/ic_launcher"></application></manifest>'
            manifest.write_text(original)
            (root / 'ios/Runner').mkdir(parents=True)
            configure(root)
            snapshot = {str(p.relative_to(root)): p.read_bytes() for p in root.rglob('*') if p.is_file()}
            configure(root)
            self.assertEqual(snapshot, {str(p.relative_to(root)):p.read_bytes() for p in root.rglob('*') if p.is_file()})
            for path in (root / 'android').rglob('*.xml'):
                ET.parse(path)
            app = ET.parse(manifest).getroot().find('application')
            self.assertEqual(app.attrib['{http://schemas.android.com/apk/res/android}icon'], '@mipmap/sendoh_launcher')
            self.assertEqual(len(app.findall('meta-data')),1)
            self.assertFalse(list((root / 'android').rglob('*.sendoh-backup')))
            self.assertEqual((Path(directory) / 'sendoh-backup-native-config/brand/android/app/src/main/AndroidManifest.xml').read_text(), original)
            folder = root / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
            for entry in json.loads((folder / 'Contents.json').read_text())['images']:
                self.assertTrue((folder / entry['filename']).is_file())
            self.assertTrue((root / 'android/app/src/main/res/mipmap-xxxhdpi/sendoh_launcher.png').is_file())


if __name__ == '__main__':
    unittest.main()
