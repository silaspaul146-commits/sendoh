# Sendoh experience update

This patch follows the working notifications APK. It does not change CI, Flutter,
Gradle, Kotlin, signing, Firebase credentials, backend or database migrations.

## Changes

- After a complete authenticated profile reaches the app, push registration now
  defaults on. The OS permission prompt is requested once per installation when
  required. Explicit per-account opt-outs are preserved. Denied permission does
  not block the inbox or sign-in. Resume retries token registration.
- A registration/network failure no longer saves an explicit opt-out.
- Notification settings remain available and explain OS permission requirements.
- Launcher assets reuse public/sendoh-mark.svg with the existing cream background.
  Android has legacy/adaptive icons and a white notification silhouette. iOS has
  the AppIcon asset set. No new package/plugin is required.
- configure_mobile.py invokes configure_brand.py. All native backups remain
  outside Android/iOS source trees. Build toolchain files are unchanged.

## Existing behaviour, not new functionality

Secure persisted sessions and device biometric/PIN unlocking already exist.
Enable Device unlock from the profile to protect a returning session. Phone OTP
is still needed for first sign-in, an expired/revoked session or recovery.
Push OTP is not added: a token from an unverified installation does not establish
ownership of the entered phone number. Staging OTP remains in Render logs.
This patch does not claim that every screen matches every reference board.

## Apply and verify (PowerShell)

From the extracted update folder:

    python .\Sendoh_Experience_Update.py --project C:\Users\IHIMBRU\Desktop\sendoh --check
    python .\Sendoh_Experience_Update.py --project C:\Users\IHIMBRU\Desktop\sendoh --apply

If a real conflict is reported, stop and export with --export proposed-update.
Do not replace custom code blindly. Formatting-only Dart differences are accepted
when the installed Dart formatter can compare them.

From the real project root:

    python .\scripts\test_configure_brand.py
    python .\scripts\configure_mobile.py
    cd .\apps\organizer_flutter
    flutter analyze
    flutter test

Use the same Flutter 3.35.7 SDK as CI. Older local SDKs do not reproduce CI.
The package was checked with Python icon/resource tests, image inspection, Dart
syntax parsing and updater apply/reapply checks. Flutter runtime/build validation
must still pass in GitHub Actions; no local Flutter build is claimed.

Commit the patch paths and push:

    cd C:\Users\IHIMBRU\Desktop\sendoh
    Get-Content .\sendoh-experience-paths.txt | ForEach-Object { git add -- $_ }
    git diff --cached --stat
    git commit -m "Default push registration and add Sendoh app icons"
    git push

Native icon files are generated during CI by configure_mobile.py; they do not
need to be individually staged. Download/install the new APK after CI succeeds.
No Render/Vercel environment changes or migration are required for this patch.

## Device acceptance checks

- Existing account: reopen app, restore session; verify optional Device unlock.
- Fresh installation/account: finish profile; permit the single OS prompt.
- Deny permission: app/inbox still work; reopening must not repeatedly ask.
- Turn alerts off, close/reopen: opt-out stays off.
- With a second account/device, send an invitation while recipient app is in the
  background; check visible push, then tap to open the authenticated inbox.
- Confirm launcher logo, unread/read inbox behaviour, logout/account switching.
- Foreground messages update the inbox; this patch does not add foreground banners.
- iOS push still needs Apple/APNs setup and device testing; Android success does
  not establish iOS push delivery.

## Implementation position and next work

Identity, invitations and notification inbox are implemented. Android release APK
building and authenticated push-device registration were demonstrated in the
shared logs. End-to-end push delivery remains unconfirmed until the device check.

Next: guest identity and participant attribution, including invitation-specific
links, verified identity binding and preventing someone selecting another person's
name as proof of identity. Then requests/P2P, Near2P QR and opt-in proximity.
Payment integration remains last. Invitation alerts should ultimately open a
specific invitation preview instead of the whole list; that flow still needs work.
