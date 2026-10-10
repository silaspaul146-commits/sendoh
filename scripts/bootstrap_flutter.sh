#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../apps/organizer_flutter"
# Native projects are tracked. Never run flutter create over an existing one.
if [[ ! -f android/app/src/main/AndroidManifest.xml ]]; then
  echo "Missing tracked Android project. Restore it before building."
  exit 1
fi
for stem in android/settings.gradle android/build.gradle android/app/build.gradle; do
  if [[ -f "$stem" && -f "$stem.kts" ]]; then
    echo "Conflicting Gradle files: $stem and $stem.kts. Review the duplicate."
    exit 1
  fi
done
mkdir -p android/app/src/debug
cat > android/app/src/debug/AndroidManifest.xml <<'XML'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <uses-permission android:name="android.permission.INTERNET" />
  <application android:usesCleartextTraffic="true" />
</manifest>
XML
flutter --version
java -version
flutter pub get
python3 ../../scripts/configure_mobile.py
flutter analyze
flutter test --reporter expanded
