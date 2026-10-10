# Sendoh phase 3 — Push alerts and notification inbox

This update builds on the installed Identity and Invitations updates. It adds the notification bell, unread count, persistent inbox, opt-in mobile push, and a retry queue in Neon. It does not add payments or change OTP delivery. Apply it to your existing `sendoh` repository, not to the extracted updater folder.

## 1. Apply the full source update

Extract `Sendoh_Notifications_Update.zip` to your Desktop. In PowerShell:

```powershell
cd C:\Users\IHIMBRU\Desktop\Sendoh_Notifications_Update
python .\Sendoh_Notifications_Update.py --project C:\Users\IHIMBRU\Desktop\sendoh --check
python .\Sendoh_Notifications_Update.py --project C:\Users\IHIMBRU\Desktop\sendoh --apply
```

If Windows extracted an extra containing folder, open the folder actually containing `Sendoh_Notifications_Update.py` first. Run only the commands inside code blocks; do not copy the PowerShell prompt.

The updater checks the phase-two baseline, accepts Dart formatting-only differences using your installed Dart SDK, and backs up replaced files. If it reports a conflict, no project source is changed. Run `--export proposed-update` and merge that file; do not blindly overwrite your local changes. Re-running the updater is safe. `update-files/` contains every complete replacement file for inspection.

It does not replace `.env`, `config.dart`, signing keys, databases, or generated Android/iOS projects. Your previous `create_collection.dart` compatibility fix remains in place. The build now invokes bootstrap through `bash`, avoiding the earlier executable-permission error.

## 2. Verify locally

Keep these test commands pointed at a development/test database, never your Neon deployment database.

```powershell
cd C:\Users\IHIMBRU\Desktop\sendoh\services\backend
$env:SENDOH_ENV="development"
.\.venv\Scripts\python.exe -m pip install -r requirements.lock
.\.venv\Scripts\python.exe -m pytest -q

cd C:\Users\IHIMBRU\Desktop\sendoh\apps\organizer_flutter
flutter pub get
dart format lib/main.dart lib/notifications.dart lib/push_service.dart test/notifications_test.dart
flutter analyze
flutter test
```

The new Flutter dependencies are `firebase_core: 3.15.2` and `firebase_messaging: 15.2.10`. Commit the resulting `pubspec.lock`. Newer-package notices alone are not test failures. Do not run a bulk major-version upgrade during this rollout.

The package was verified with backend tests and migration checks. Flutter syntax was parsed, but Flutter analysis, widget tests, APK compilation, and actual device delivery could not be run in the authoring environment. Your local Flutter checks and GitHub Actions must pass before installing the APK. Real push delivery must then be tested with the Firebase project below.

## 3. Create the no-card Firebase configuration

Open https://console.firebase.google.com/ and create a project on **Spark**. Google Analytics is optional and unnecessary here. Do not enable Blaze, Cloud Functions, Firebase phone authentication, or paid hosting for this feature. Firebase Cloud Messaging itself is a no-cost product on Spark without payment information.

Register an **Android app** in that project. Use your actual Android application ID from `apps/organizer_flutter/android/app/build.gradle` or `build.gradle.kts` (`applicationId`). The existing generated default is normally `com.example.sendoh_organizer`; confirm it rather than renaming an existing app. Firebase project ID, Android package/application ID, and Firebase app ID are different values.

Download the app's `google-services.json` as a reference file outside the repository. This build generates the required Android Firebase resources from GitHub variables; **do not also install the Google Services Gradle plugin or copy google-services.json into android/app**. The build helper stops if it detects that competing configuration.

From the Android app entry in the downloaded JSON, copy these public client identifiers:

| GitHub JSON field | Value in google-services.json |
| --- | --- |
| FIREBASE_PROJECT_ID | project_info.project_id |
| FIREBASE_MESSAGING_SENDER_ID | project_info.project_number, as a quoted string |
| FIREBASE_ANDROID_APP_ID | matching client.client_info.mobilesdk_app_id |
| FIREBASE_ANDROID_API_KEY | matching client.api_key entry's current_key |

### GitHub: public client configuration

In the repository connected to your deployments, open **Settings → Secrets and variables → Actions → Variables → New repository variable**.

Name: `SENDOH_FIREBASE_CONFIG`

Value: the following JSON with every placeholder replaced. These four fields must belong to the same Firebase project and Android app.

```json
{
  "PUSH_ENABLED": true,
  "FIREBASE_PROJECT_ID": "your-real-project-id",
  "FIREBASE_MESSAGING_SENDER_ID": "123456789012",
  "FIREBASE_ANDROID_APP_ID": "1:123456789012:android:abcdef0123456789",
  "FIREBASE_ANDROID_API_KEY": "your-real-client-api-key"
}
```

These are Firebase *client* identifiers embedded in the APK, not permission to send messages. Do not paste a service-account private key here. Keep your existing `SENDOH_STAGING_API_URL` set to `https://sendoh.onrender.com` if you use that variable.

If `SENDOH_FIREBASE_CONFIG` is absent, CI builds an inbox-only APK. A configuration added after an APK was built requires a new build (re-running that workflow also works).

### Render: private sender credentials

In Firebase Project settings → Service accounts, generate a private service-account key for this project. Keep the downloaded private JSON outside the repository. Use the service account's FCM HTTP v1 permissions; a dedicated sender can use the **Firebase Cloud Messaging API Admin** role (`roles/firebasecloudmessaging.admin`). The Firebase Cloud Messaging API must be enabled for that project. Do not enable the obsolete legacy API.

In the backend Render service's Environment settings add:

| Key | Value |
| --- | --- |
| SENDOH_PUSH_ENABLED | 1 |
| FIREBASE_SERVICE_ACCOUNT_JSON | Entire private service-account JSON, including braces |

The private key is only for Render. Never put it in Flutter, Vercel, GitHub source, the client variable, or a screenshot. Keep existing database, HTTPS public web URL, staging/auth, and OTP settings unchanged. Generating a key may be restricted on managed organization accounts; do not bypass an organization policy.

Save the values. They become active when the new backend code is deployed. With `SENDOH_PUSH_ENABLED` omitted or `0`, the inbox works and the sender is off. With it set to `1`, missing/invalid key material intentionally prevents startup. `/health` showing `push_configured: true` means credentials loaded; only a device test confirms provider authorization and delivery.

## 4. Commit and deploy

After the local checks pass and the GitHub variable is configured:

```powershell
cd C:\Users\IHIMBRU\Desktop\sendoh
git status --short
git remote -v
Get-Content .\sendoh-notifications-paths.txt | ForEach-Object { git add -- $_ }
git add -- apps/organizer_flutter/pubspec.lock
git diff --cached --stat
git commit -m "Add push notifications and private notification inbox"
git push
```

The generated path list stages only this update's source files. Review the staged changes before committing. Do not stage backup folders, downloaded keys, or the updater directory. Use the remote you already connected to Render and Vercel; no new repository is needed.

Render must run `python -m alembic upgrade head` against its existing Neon database before starting the updated app. With your existing build command, this remains:

```text
pip install -r requirements.lock && python -m alembic upgrade head
```

Start command remains:

```text
python -m uvicorn app.main:app --host 0.0.0.0 --port $PORT
```

The new migration is `d50a3e1f4004`, following phase two's `c49f2d0e3003`. It adds tables and an invitation version column; existing users and invitations are retained. Do not delete or re-create the Neon database.

Check https://sendoh.onrender.com/health after deployment. Expect `status: ok`, `version: 0.4.0`, and `push_configured: true` when configured. Payments remain disabled. The guest website has no source changes in this phase; Vercel may rebuild on the repository push as usual.

Then open the latest successful GitHub Actions run → Artifacts → `sendoh-android-staging`. Download and extract it, then install `app-release.apk`. Deploy the backend migration before installing this APK. Keep your existing signing setup: an APK signed by a different key cannot update an installed app in place.

## 5. Test with two registered accounts

Use Android devices with Google Play services and internet access.

1. Sign in as account B. Tap the bell → **Enable push alerts**, and grant the phone's notification permission. The app must report successful registration.
2. Put B's app in the background. From account A, invite B by the existing verified phone or username flow.
3. B should receive a generic Sendoh alert. Tap it, unlock if required, then open the inbox item to review the invitation. Accept it.
4. Account A should see the acceptance in its inbox. If A enabled push and is backgrounded, A should also receive an alert.
5. Repeat for decline and cancellation. A cancelled/reissued invitation must not let an old notification authorize acceptance of the wrong invitation.
6. While the app is foregrounded, a received push refreshes the unread badge/inbox; it does not display a second system popup.
7. Disable push, then send another invitation: the persistent inbox must still update on refresh/resume, without a new push for that registration.
8. Log out of B, then send B another invitation: that session's future queued pushes must be suppressed. An alert already delivered to the operating system cannot be recalled.
9. Test an ordinary closed-app launch from a notification. Android **Force stop** is different: reopen the app before expecting delivery again.

Registered users need to opt in on a built APK before new events can be pushed to that device. Earlier invitations are backfilled into the inbox without a burst of historical pushes. A phone-only invite for someone who has not registered has no push destination: they use the guest link, or see the pending invite after registering and verifying that phone.

Push uses internet data. It is not an SMS OTP provider and does not change the current OTP authentication setup. Browser/guest push is not implemented in this phase.

## 6. Operational behavior and limits

- New invitation → invitee notification. Accept/decline → organizer notification. Cancel → invitee notification.
- Inbox entries and queued push jobs are stored in Neon in the same transaction as the invitation event.
- The existing Render process drains the queue. No Cloud Functions, extra paid worker, or scheduler is required.
- Render free web services can sleep after inactivity. Pending retries wait until the service wakes; this is not an always-on instant-delivery guarantee. A request that creates an invitation normally wakes the backend as part of that request.
- Temporary provider failures retry with backoff, up to six normal attempts. Unregistered tokens are disabled. Jobs older than 24 hours, read invitations, expired/revoked sessions, and stale invitation generations are skipped. Tokens and provider response bodies are not written to logs.
- Delivery is at least once, not mathematically exactly once: a crash after provider acceptance can cause a duplicate OS alert. Stable notification IDs/tags reduce duplicates; the inbox is deduplicated.
- Token rotation replaces the old registration for that login session. Up to five active session/device registrations are allowed per account. Logout revokes its session's registration; other sessions remain signed in.
- Notification taps open the authenticated inbox and fetch current server state. They never trust a notification payload as payment or membership authorization.
- Foreground live refresh depends on push; with push disabled, pull to refresh or resume the app to fetch new updates. There is no permanent polling loop.
- No automatic historical queue/inbox pruning is added in this pilot. Define a retention policy before a large rollout.

If the bell says push is not configured: verify the GitHub variable, build a new APK, verify Render `push_configured`, and install that APK. If registration succeeds but delivery fails: inspect safe `sendoh.push` error codes in Render logs. `PROVIDER_AUTH` indicates service-account permissions/API/project setup; `UNREGISTERED` requires a current token from reopening/enabling the app. Generic UI authentication failures require signing in again.

## iOS source support

The Flutter service includes iOS branches and APNs readiness checks, but an iOS push build has not been signed or device-tested here. Use the same Firebase project, register the real iOS bundle ID, and add `FIREBASE_IOS_APP_ID`, `FIREBASE_IOS_API_KEY`, and `FIREBASE_IOS_BUNDLE_ID` to the client JSON. In Xcode enable Push Notifications and Background Modes → Remote notifications/Background fetch, configure APNs credentials in Firebase, keep Firebase method swizzling enabled, and use a correctly provisioned device build. Review the Firebase plugin's minimum deployment target with your Xcode project.

Apple signing/APNs distribution requirements are separate from free FCM; this phase does not purchase Apple membership or promise a no-cost iOS distribution path. Android is the current no-card rollout target.

## What remains after this phase

Guest identity/participant claim verification, requests and P2P flows, and Near2P (QR first, opt-in proximity afterward) still need their own implementation and tests. Payment integration remains last. Notification events for those features should be added when their business flows exist. This phase does not imply those features are complete.

The new screen reuses existing Sendoh colors, typography helpers, and cards. The previously attached design boards were unavailable in this environment, so no pixel-exact comparison with them is claimed. The earlier guest-web dependency audit findings also need a separate targeted dependency review; this update does not resolve them.

## Sources checked for setup

- Firebase Spark and no-cost FCM: https://firebase.google.com/docs/projects/billing/firebase-pricing-plans
- Flutter FCM and Apple setup: https://firebase.google.com/docs/cloud-messaging/flutter/get-started
- FCM HTTP v1 authorization: https://firebase.google.com/docs/cloud-messaging/send/v1-api
- Render free-service behavior: https://render.com/docs/free

Checked 9 October 2026. This package pins its Flutter Firebase versions; APIs in the newest online documentation may differ from that pinned generation.
