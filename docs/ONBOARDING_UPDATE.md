# Phone onboarding increment — development only

## Implemented

Welcome → Cameroon phone number → verification → name → organizer home.
Returning phone users with a completed profile enter home directly. Profile names
appear on their public collection pages. Original development tokens still access
their original collections. Phone accounts are separate; there is no automatic
ownership transfer, and no collection or existing user is deleted by migration.

Codes expire after five minutes, allow five attempts, can be resent after 60 seconds,
and are consumed once. Resending invalidates the previous challenge. Sessions expire
after twelve hours and are revoked by sign-out. Credentials remain in app memory;
restarting the app requires signing in again. Legacy development tokens remain valid
after disconnecting and are not phone sessions.

The backend intentionally refuses startup outside SENDOH_ENV=development. There is
no SMS provider. Codes are written to the API computer's .dev-otp directory, never
returned by HTTP, and can be read by the local command shown in the app. This is for
local testing only, not proof of phone ownership in production. Do not expose this
API publicly. Production needs real delivery, infrastructure rate limits, secure
session persistence/refresh and an authentication security review.

## Apply on Windows

Stop the backend and Flutter app first. Place Sendoh_Onboarding_Update.py in the
project root (the folder containing apps and services). In Command Prompt:

```bat
python Sendoh_Onboarding_Update.py --project . --check
python Sendoh_Onboarding_Update.py --project . --apply
```

The updater verifies every changed file before writing, stops on local edits, and
backs up replaced files. It does not change .env, databases, Android/iOS projects,
or unrelated files. It accepts Windows line endings. If it reports conflicts, keep
your changes and compare with the proposed files using --export proposed-update.
Do not delete your database or rerun seed/bootstrap.

Activate your existing backend virtual environment, then:

```bat
cd services\backend
set SENDOH_ENV=development
python -m alembic upgrade head
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Keep your existing DATABASE_URL and PUBLIC_WEB_URL settings. In another terminal:

```bat
cd apps\organizer_flutter
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=API_URL=http://192.168.1.118:8000
```

Use your computer's current Wi-Fi IP if it has changed. The welcome settings button
also lets you change the API URL. For wireless debugging, keep your existing adb
connection. Restart the guest web development server to pick up written-month dates.

On the verification screen, expand **Get development code** and copy the displayed
command. Run it from services/backend, with the virtual environment active and
SENDOH_ENV=development. Enter that code in the app within five minutes. Code files
left by expired/resend challenges may be deleted after testing; do not commit them.

## UI fidelity and remaining work

The welcome screen now uses the clean three-person illustration derived from the
supplied board rather than cropping the board itself. Branding, spacing, cream canvas,
teal actions and six individual paste-friendly verification boxes follow the accepted
reference. Home, creation, collection detail and contribution screens now use the same
visual system. Optional profile photo upload and legal documents are still pending.
No placeholder Terms/Privacy consent is represented as legally complete.

Requests, P2P, digital collection, final cash reconciliation and settlement are still
pending. Existing rules remain: settlement fees deducted from collection funds,
cash registration at the end, no wallet or reversal feature.

## Verification

Backend tests cover auth, profile, account isolation, code limits and expiry, session
revocation, collection rules and migration preserving an existing organizer/link.
PostgreSQL concurrency tests require TEST_DATABASE_URL and were not run locally.
Flutter 3.24.5 analysis passed with no issues. Both widget tests passed on Flutter's
Chrome platform. The managed Linux container's native `flutter_tester` executable
segfaulted before test loading, so the native test command must still be rerun on the
development computer before merging.

## Continuous development

These changes have not been pushed to GitHub. Work locally in your own clone and
review the diff before committing. GitHub access is separate from the email used
for ChatGPT. You do not need to use the ChatGPT account owner's GitHub account.
Once this project is connected to your authorized repository, subsequent changes
can be delivered as branches/PRs and obtained with git pull.
