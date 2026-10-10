"""Install canonical Sendoh launcher assets without changing build/signing config."""
import json
from pathlib import Path
import re
import shutil

ROOT = Path(__file__).resolve().parents[1] / 'apps/organizer_flutter'


def configure(root=ROOT):
    root = Path(root)
    assets = root / 'assets/brand'
    backup = root.parent.parent / 'sendoh-backup-native-config/brand'

    def write(path, value):
        data = value if isinstance(value, bytes) else value.encode('utf-8')
        if path.exists() and path.read_bytes() == data:
            return
        if path.exists():
            original = backup / path.relative_to(root)
            original.parent.mkdir(parents=True, exist_ok=True)
            if not original.exists():
                shutil.copy2(path, original)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    manifest = root / 'android/app/src/main/AndroidManifest.xml'
    if manifest.exists():
        res = manifest.parent / 'res'
        for density, size in [('mdpi',48), ('hdpi',72), ('xhdpi',96), ('xxhdpi',144), ('xxxhdpi',192)]:
            write(res / f'mipmap-{density}/sendoh_launcher.png', (assets / f'icon-{size}.png').read_bytes())
        write(res / 'drawable-nodpi/sendoh_foreground.png', (assets / 'adaptive-foreground.png').read_bytes())
        write(res / 'values/sendoh_icon.xml', '<resources><color name="sendoh_icon_background">#FBF9F6</color></resources>\n')
        write(res / 'mipmap-anydpi-v26/sendoh_launcher.xml', '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android"><background android:drawable="@color/sendoh_icon_background"/><foreground android:drawable="@drawable/sendoh_foreground"/></adaptive-icon>\n')
        # Android notification status-bar icons use a white silhouette.
        write(res / 'drawable/sendoh_notification.xml', '''<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="24dp" android:height="24dp" android:viewportWidth="40" android:viewportHeight="60">
<path android:pathData="M29,15 L25,10 C17,1 3,8 5,19 C6,24 12,29 20,37" android:strokeColor="#FFFFFFFF" android:strokeWidth="7" android:strokeLineCap="round"/>
<path android:pathData="M11,45 L15,50 C23,59 37,52 35,41 C34,36 28,31 20,23" android:strokeColor="#FFFFFFFF" android:strokeWidth="7" android:strokeLineCap="round"/>
</vector>\n''')
        text = manifest.read_text()
        def application(match):
            tag = match[0]
            for attribute in ('icon', 'roundIcon'):
                pattern = rf'android:{attribute}="[^"]*"'
                replacement = f'android:{attribute}="@mipmap/sendoh_launcher"'
                tag = re.sub(pattern, replacement, tag) if re.search(pattern, tag) else tag[:-1]+' '+replacement+'>'
            return tag
        text = re.sub(r'<application\b[^>]*>', application, text, count=1)
        name = 'com.google.firebase.messaging.default_notification_icon'
        metadata = f'<meta-data android:name="{name}" android:resource="@drawable/sendoh_notification" />'
        pattern = r'<meta-data\b[^>]*android:name="'+re.escape(name)+r'"[^>]*/>'
        if re.search(pattern, text):
            text = re.sub(pattern, lambda _: metadata, text)
        else:
            text = text.replace('</application>', metadata+'\n</application>')
        write(manifest, text)
    runner = root / 'ios/Runner'
    if runner.exists():
        folder = runner / 'Assets.xcassets/AppIcon.appiconset'
        images = []
        for idiom, sizes in [('iphone', [(20,2),(20,3),(29,2),(29,3),(40,2),(40,3),(60,2),(60,3)]),
                             ('ipad', [(20,1),(20,2),(29,1),(29,2),(40,1),(40,2),(76,1),(76,2),(83.5,2)]),
                             ('ios-marketing',[(1024,1)])]:
            for size, scale in sizes:
                pixels = int(size*scale)
                filename = f'sendoh-{pixels}.png'
                write(folder / filename, (assets / f'icon-{pixels}.png').read_bytes())
                images.append({'idiom':idiom, 'size':f'{size}x{size}', 'scale':f'{scale}x', 'filename':filename})
        write(folder / 'Contents.json', json.dumps({'images':images,'info':{'version':1,'author':'xcode'}}, indent=2)+'\n')
    print('Sendoh launcher and notification icons configured.')


if __name__ == '__main__':
    configure()
