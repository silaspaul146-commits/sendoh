#!/usr/bin/env bash
set -euo pipefail
apk="${1:?Supply release APK path}"
sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
aapt=$(find "$sdk/build-tools" -name aapt -type f | sort -V | tail -1)
if [[ -z "$aapt" ]]; then echo 'Android aapt not found'; exit 1; fi
badging=$("$aapt" dump badging "$apk")
if ! grep -q "application-label:'Sendoh'" <<< "$badging"; then
  echo 'APK does not contain the Sendoh app label'; exit 1
fi
resources=$("$aapt" dump resources "$apk")
if ! grep -q 'mipmap/sendoh_launcher' <<< "$resources"; then
  echo 'APK does not contain Sendoh launcher resources'; exit 1
fi
# Verify the merged manifest actually references the branded icon resource.
python3 - "$apk" "$aapt" <<'PY'
import re,subprocess,sys
apk,aapt=sys.argv[1:]
resources=subprocess.check_output([aapt,'dump','resources',apk],text=True)
manifest=subprocess.check_output([aapt,'dump','xmltree',apk,'AndroidManifest.xml'],text=True)
m=re.search(r'resource (0x[0-9a-fA-F]+) [^\s]*:mipmap/sendoh_launcher',resources)
if not m or not re.search(r'android:icon[^\n]*=@'+re.escape(m[1]),manifest):
    raise SystemExit('Merged APK icon does not reference sendoh_launcher')
print('Verified APK: Sendoh label and branded launcher resource.')
PY
