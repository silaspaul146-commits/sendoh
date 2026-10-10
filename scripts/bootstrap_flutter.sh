#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../apps/organizer_flutter"
# Generate platform boilerplate without overwriting the authored app/test files.
task_backup=$(mktemp -d)
cp -R lib test pubspec.yaml analysis_options.yaml "$task_backup/"
flutter create --project-name sendoh_organizer --platforms=android,ios .
rm -rf lib test
cp -R "$task_backup/lib" "$task_backup/test" "$task_backup/pubspec.yaml" "$task_backup/analysis_options.yaml" .
rm -rf "$task_backup"
# HTTP permission is debug-only. Release traffic must use HTTPS.
mkdir -p android/app/src/debug
cat > android/app/src/debug/AndroidManifest.xml <<'XML'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <uses-permission android:name="android.permission.INTERNET" />
  <application android:usesCleartextTraffic="true" />
</manifest>
XML
flutter pub get
python3 ../../scripts/configure_mobile.py
flutter analyze
flutter test --reporter expanded
