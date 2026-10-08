# Sendoh identity update — phase 1

This update builds on the UI/cloud update applied on 8 October 2026. It is a source
update, not a deployment or a prebuilt APK. Payments remain disabled.

## What is implemented

- OTP verification leads to full name, a unique username, and an optional photo.
- Usernames are lowercase, 3–24 ASCII letters/numbers/underscores, starting with a
  letter. Database uniqueness prevents two accounts claiming the same username.
  Usernames cannot be renamed in this release. Existing accounts choose one on
  their next login; existing collections and IDs are preserved.
- A photo is optional. Profile lets users edit their name and replace/remove the
  photo later. Only the owner currently receives this photo from the API.
- The server validates image bytes, crops a 256-pixel JPEG thumbnail, removes EXIF,
  and stores it in the existing database. Input is limited to 200 KB/4 megapixels.
  No Cloudinary, Firebase Storage, local Render disk or new billing account is
  required. This is a small-pilot storage decision; move thumbnails behind an
  object-storage interface if database size/traffic grows.
- Access tokens last at most 12 hours. Refresh sessions have a fixed 30-day
  lifetime and rotate on use. Reuse revokes the whole device session. Logout
  revokes access and refresh tokens for that device. Only hashes live server-side.
- Flutter saves the refresh token in Keychain/Keystore-backed secure storage.
  Access tokens stay in memory. A network failure offers retry, not a fake login.
  If a refresh response is lost after server rotation, phone verification may be
  needed again; the app does not weaken replay detection to avoid that prompt.
- Optional Profile > Device unlock uses biometrics or the operating system's PIN.
  It is an app lock over an existing server session, not an independent identity
  credential. No custom Sendoh PIN or Google login is implemented yet.
- Cloud authentication no longer accepts legacy developer bearer tokens.
- Website describes Collections, Requests, P2P and Near2P, and labels availability.
  Its generated WhatsApp/social preview now uses the same broader message.
- SMS rejects a provider-level failure even when the HTTP response is 200.

## Apply to your existing repository

Extract Sendoh_Identity_Update.zip into its own folder. In PowerShell from that
folder, run:

```powershell
python .\Sendoh_Identity_Update.py --project C:\Users\IHIMBRU\Desktop\sendoh --check
python .\Sendoh_Identity_Update.py --project C:\Users\IHIMBRU\Desktop\sendoh --apply
```

Conflicts stop the whole update. Use `--export proposed-update` to compare local
edits rather than overwriting them. The script backs up replaced files and creates
a list of the exact Git paths to stage. It does not touch credentials, .env,
databases, signing keys, native projects or deploy anything itself.

## Check and push

```powershell
cd C:\Users\IHIMBRU\Desktop\sendoh\apps\organizer_flutter
flutter pub get
flutter analyze
flutter test
cd ..\guest_web
npm ci
npm run typecheck
npm run build
cd ..\..\services\backend
$env:SENDOH_ENV="development"
.\.venv\Scripts\python.exe -m pip install -r requirements.lock
.\.venv\Scripts\python.exe -m pytest -q
cd ..\..
git status --short
Get-Content .\sendoh-identity-paths.txt | ForEach-Object { git add -- $_ }
git add -- apps/organizer_flutter/pubspec.lock
git diff --cached --stat
git commit -m "Add Sendoh profile identity and secure returning sessions"
git push
```

Stop if any check fails. `pubspec.lock` is resolved by Flutter, not fabricated by
this updater. Review staged files before committing; no broad `git add .` is needed.
The generated path-list text is an installation helper, not application code.

## Cloud rollout order

1. Render first: keep your existing Neon DATABASE_URL and HTTPS PUBLIC_WEB_URL.
   The existing build command must include `python -m alembic upgrade head` after
   installing requirements.lock. Migration b38e1c9d2002 adds columns/tables while
   retaining existing users and collections. Do not reset the database.
2. Wait for Render to be live and `/health` to return OK. Verify the migration ran.
   The new APK requires the new refresh/profile API; do not distribute it first.
3. Vercel redeploys the updated website from the push. API_INTERNAL_URL continues
   pointing to your HTTPS Render backend.
4. GitHub Actions resolves plugins, generates native projects, configures their
   permissions, analyzes/tests Flutter and builds the Android APK. Install the APK
   only when those checks pass. Android release INTERNET permission is included.
5. For a local APK, run `powershell -File .\scripts\build_android.ps1` from the
   repository root. `configure_mobile.py` updates the generated Android activity,
   biometric permission/theme and disables token backup. Original native files
   receive .sendoh-backup copies. The script also adds iOS photo/Face ID usage text.
   iOS still requires a Mac, signing and an actual device test before distribution.

The original UI/cloud documents describe an earlier release. This document is the
authority for this update's identity behavior and rollout.

## Receive OTP on the phone (no credit card to begin testing)

The existing Infobip adapter is retained. Infobip's official signup documentation
confirms a 60-day trial with no credit card at signup. The trial is restricted to
verified recipient numbers and limited SMS credit; it is not a permanent free
production SMS plan. Confirm Cameroon MTN and Orange delivery from your account
before inviting testers. Do not assume a trial can message arbitrary users.

Create the trial yourself and verify your testing number. In Render Environment:

| Key | Value |
| --- | --- |
| SENDOH_ENV | staging |
| OTP_PROVIDER | infobip |
| INFOBIP_BASE_URL | Your account's HTTPS API base URL |
| INFOBIP_API_KEY | Your private API key with SMS sending permission |
| INFOBIP_SENDER | ServiceSMS for the trial, subject to your account's setup |

Remove ALLOW_STAGING_LOG_OTP when switching away from log mode. Keep credentials in
Render only. Redeploy, request a fresh OTP in the app, and enter the SMS code. The
app never receives the OTP in an API response. Delivery can still fail due to
trial restrictions or mobile-network configuration; check provider reports.

SMS is not activated by this ZIP. It needs your account and credentials. No paid
plan, card requirement, subscription or provider charge was authorized or created.
If the account asks for a card before testing, stop and we will evaluate a local
provider's prepaid/mobile-money onboarding. Do not promise free public SMS without
confirmed terms. Broad OTP abuse controls and delivery monitoring remain a gate
before public authentication rollout.

Sources checked 8 October 2026:
- https://www.infobip.com/docs/essentials/getting-started/create-an-account
- https://www.infobip.com/docs/tutorials/send-your-first-sms-message-using-infobip-api
- https://www.infobip.com/docs/essentials/api-essentials/response-status-and-error-codes
- https://pub.dev/packages/flutter_secure_storage/versions/9.2.4
- https://pub.dev/packages/image_picker/versions/1.1.2
- https://pub.dev/packages/local_auth/versions/2.3.0

## Acceptance checks on a real phone

Package validation completed: 48 backend tests passed, one PostgreSQL-specific
test skipped locally (CI supplies PostgreSQL); fresh Alembic upgrade and schema
comparison passed; web TypeScript/build passed; rendered social preview inspected;
updater backups/conflict/idempotence and native configuration repeat-run checks
passed. Flutter SDK was unavailable here and its download failed, so Flutter
analysis, widget tests, Android compilation, biometrics and iOS execution are NOT
reported as passed. The included GitHub workflow/local commands must pass those
checks, followed by the device checks below. Exact pixel fidelity of the running
mobile screens has not been verified.

1. New phone -> OTP -> name/username/photo -> Home. Try an already-used username.
2. Home and Profile display the saved photo/name; Profile displays @username.
3. Edit/remove the photo, restart, and confirm the saved change remains.
4. Restart without device unlock: restore session without another SMS.
5. Enable Device unlock, background/reopen, cancel unlock, then unlock with device
   biometrics/PIN. Navigate into a collection before backgrounding too.
6. Sign out, restart: phone authentication is required. Reinstalling/recovering a
   device must not be treated as proof of ownership; use OTP again when needed.
7. Existing name-only account: same account/collections, prompted to choose username.
8. Turn off network during restore: retry is available; no false authenticated UI.
9. Test both MTN and Orange SMS with registered trial recipients. Never post codes.

## Next stages, in order

1. This identity slice, then physical-device/cloud verification.
2. Participant identity and invitations: organizer can find an exact username or
   verified phone; link participant IDs to accounts; preserve private rosters.
   Legacy manually typed names remain unverified until claimed with proof.
3. Registered-user inbox and notification outbox, then FCM push delivery.
4. Guest scoped OTP verification/invitation claims. Contributor identity and payer
   identity stay separate. Never let guests select another person's name as proof.
5. Requests and P2P intent/review/status screens without money movement.
6. Near2P QR -> resolve recipient -> confirm identity -> Request/P2P intent. Later,
   optional proximity discovery uses short-lived identifiers and explicit consent,
   never a public live map or phone-number broadcast. QR is not authentication.
7. CamPay integration LAST: provider-confirmed ledger, idempotency, callbacks,
   reconciliation and failure handling. No wallet or user-facing reversals.

Payment integration is last. Existing guest attribution/invitations, push,
Requests/P2P and Near2P are not implemented by this phase-1 package. Google account
linking, full bilingual copy, lost-photo picker recovery and pixel/device visual
QA remain follow-up work. Do not market those features as available yet.
