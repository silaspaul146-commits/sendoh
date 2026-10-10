"""Configure generated native projects for Sendoh identity plugins.

Run after flutter create. Original native files get a sibling .sendoh-backup.
No signing configuration, package identifiers or credentials are replaced.
"""
from pathlib import Path
import re
import shutil
import plistlib

ROOT = Path(__file__).resolve().parents[1] / 'apps/organizer_flutter'

def save(path, content):
    old = path.read_bytes()
    new = content if isinstance(content, bytes) else content.encode()
    if old == new:
        return
    backup = path.with_name(path.name + '.sendoh-backup')
    if not backup.exists():
        shutil.copy2(path, backup)
    path.write_bytes(new)
    print('Configured', path.relative_to(ROOT))

def configure(root=ROOT):
    manifest = root / 'android/app/src/main/AndroidManifest.xml'
    if manifest.exists():
        value = manifest.read_text()
        for permission in ('INTERNET', 'USE_BIOMETRIC', 'POST_NOTIFICATIONS'):
            name = 'android.permission.' + permission
            if name not in value:
                value = re.sub(r'(<manifest\b[^>]*>)',
                    r'\1\n    <uses-permission android:name="' + name + '" />', value, count=1)
        # Never restore encrypted refresh tokens from an Android device backup.
        if 'android:allowBackup=' in value:
            value = re.sub(r'android:allowBackup="[^"]*"', 'android:allowBackup="false"', value)
        else:
            value = value.replace('<application', '<application android:allowBackup="false"', 1)
        for name in ('firebase_messaging_auto_init_enabled', 'firebase_analytics_collection_enabled'):
            if name not in value:
                value = value.replace('</application>',
                    f'    <meta-data android:name="{name}" android:value="false" />\n    </application>')
        save(manifest, value)
        for gradle in (root / 'android/app/build.gradle', root / 'android/app/build.gradle.kts'):
            if gradle.exists():
                value = gradle.read_text()
                value = value.replace('minSdk = flutter.minSdkVersion', 'minSdk = Math.max(23, flutter.minSdkVersion)')
                value = value.replace('minSdkVersion flutter.minSdkVersion', 'minSdkVersion Math.max(23, flutter.minSdkVersion)')
                value = re.sub(r'(\bminSdk(?:Version)?\s*(?:=\s*)?)(\d+)',
                    lambda m: m[1] + str(max(23, int(m[2]))), value)
                save(gradle, value)
        activities = list((root / 'android/app/src/main').rglob('MainActivity.kt')) + list((root / 'android/app/src/main').rglob('MainActivity.java'))
        if not activities:
            raise RuntimeError('No MainActivity found. Configure FlutterFragmentActivity manually before building.')
        for path in activities:
            value = path.read_text()
            if 'FlutterFragmentActivity' not in value and 'FlutterActivity' not in value:
                raise RuntimeError(f'Custom activity requires manual review: {path}')
            save(path, value.replace('FlutterActivity', 'FlutterFragmentActivity'))
        for path in (root / 'android/app/src/main/res').glob('values*/styles.xml'):
            value = path.read_text()
            value = re.sub(r'(<style\s+name="LaunchTheme"\s+parent=")[^"]+',
                           r'\1Theme.AppCompat.DayNight.NoActionBar', value)
            save(path, value)
    info = root / 'ios/Runner/Info.plist'
    if info.exists():
        value = plistlib.loads(info.read_bytes())
        value.setdefault('NSPhotoLibraryUsageDescription', 'Choose an optional Sendoh profile photo.')
        value.setdefault('NSFaceIDUsageDescription', 'Unlock your existing Sendoh session securely.')
        value['FirebaseMessagingAutoInitEnabled'] = False
        save(info, plistlib.dumps(value, sort_keys=False))

if __name__ == '__main__':
    configure()
