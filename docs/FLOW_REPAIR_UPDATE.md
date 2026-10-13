# Sendoh flow repair update

This cumulative update includes the guest-identity files. Apply it to the existing Sendoh project, not a new Flutter project. It preserves the working launcher icon, native build toolchain, credentials and environment files. No new database migration is introduced.

## What changes

- Home shows joined collections separately from collections you organize. Returning from invitations refreshes Home.
- Participant rows and organizer cards display the linked member's saved avatar, with initials as a fallback.
- Share a general collection link in your group. Recipients verify their phone, enter a name if needed, and join as themselves. They do not need to install the app or choose a username for this guest flow. A minimal identity account is stored behind the scenes.
- A personal invitation is bound to a particular account or phone. Its URL is a locator, not permission to impersonate its recipient. A different verified account cannot view/accept that invitation. The general collection link is deliberately open to other verified people joining as themselves.
- Matching pending invitations are reused when that recipient joins through the general link.
- Manual names remain unverified placeholders. Names are never automatically matched. After a person joins, the organizer can open the manual participant and choose “Link to a joined member”. The authenticated membership is retained, the placeholder is removed, and its expected amount is retained. This is an explicit organizer identity decision. Do not select a different person.
- Saved sessions remain on a Welcome back/retry screen on network errors. Device unlock is not repeated within one restore attempt after it succeeds. Actual expired/revoked sessions still require OTP. Biometrics cannot revive an expired server session.
- Mobile performs a bounded, read-only health wake-up before API calls. Mutation requests are not automatically replayed on timeout.
- A GitHub workflow pings staging every ten minutes. Scheduled runs can be delayed or disabled by GitHub; this is not an always-on guarantee. Render free-tier sleep and cold starts still exist. https://render.com/docs/free
- Push queue wakes promptly after successful mutations. Notifications with a participant ID open the invitation detail.
- Guest web and joined-collection mobile screens have a local payment demo: amount, review, method, success/failure/cancel, demo receipt. Demo receipts are visibly marked and are not saved as financial records. Collected totals never change. No CamPay calls or actual charges.

## Push OTP for testing

On Render add `SENDOH_STAGING_PUSH_OTP=1`. Keep `SENDOH_ENV=staging`, `OTP_PROVIDER=log`, and the existing Firebase configuration. Redeploy.

Only a device already registered by a signed-in account, with an active session family and notification permission, can receive the testing code for that account's phone. No caller-supplied push token is accepted at login. A first-time user, signed-out device, expired device, or failed push submission falls back to the existing staging log delivery. Push provider acceptance does not guarantee handset delivery; retry after the resend interval if needed. This is not production SMS verification.

To test: sign into phone A once and allow push; leave A signed in in the background. On a second device or guest browser request an OTP for A's phone. Look for the code notification on A. Do not sign out of A first: sign-out revokes its device registration. First-time onboarding still needs the admin-provided staging code until SMS is integrated.

## Apply and deploy (PowerShell)

From the extracted Sendoh_Flow_Repair_Update folder:

```powershell
python .\Sendoh_Flow_Repair_Update.py --project C:\Users\IHIMBRU\Desktop\sendoh --check
python .\Sendoh_Flow_Repair_Update.py --project C:\Users\IHIMBRU\Desktop\sendoh --apply
```

If a real conflict is reported, export with `--export proposed-update` and merge it. Do not force-overwrite unrelated changes.

Run locally:

```powershell
cd C:\Users\IHIMBRU\Desktop\sendoh\services\backend
$env:SENDOH_ENV="development"
.\.venv\Scripts\python.exe -m pytest -q
cd ..\..\apps\guest_web
npm ci
npm run typecheck
npm run build
node scripts/test-guest-proxy.cjs
cd ..\organizer_flutter
flutter pub get
dart format lib
flutter analyze
flutter test
```

Use Flutter 3.35.7 for parity with CI. Keep your pinned native Gradle/AGP/Kotlin configuration.

```powershell
cd C:\Users\IHIMBRU\Desktop\sendoh
Get-Content .\sendoh-flow-repair-paths.txt | ForEach-Object { git add -- $_ }
git diff --cached --stat
git commit -m "Repair Sendoh membership sessions and payment demo"
git push
```

Wait for Render and Vercel to deploy, then install the NEW GitHub Actions APK. No APK is included in this source update.

## Two-person acceptance checklist

Use organizer A and member B with different verified phone numbers.

1. A creates a collection with a manual placeholder for B. Share its general link through WhatsApp. B opens the web link, verifies their own number, enters their name and joins.
2. A sees a joined profile plus the unverified placeholder. Open the placeholder, link it to B, and confirm there is one remaining member and the original expected amount. Names alone must never silently merge.
3. B signs into the app using the same phone. Home shows that collection under Collections you joined. A sees B's uploaded photo. An unlinked placeholder has initials rather than an invented photo.
4. Invite B by account/phone to a different collection. Copy the personal link from its participant sheet. Try it while verified as A: A cannot accept it as B. B can accept. Repeat acceptance: no duplicate row.
5. Close and reopen B's app with device lock enabled. Unlock once, then reach Home. Turn network off and reopen: retry screen, not mandatory OTP. Reconnect and retry. Sign-out, true expiry or revocation still requires sign-in.
6. Open a joined collection and tap Try contribution demo. Repeat success, failure and cancel. Open the demo receipt. Real collected totals must remain unchanged. Repeat in the guest web.
7. Test push OTP using the two-device instructions above. New users still use staging logs.
8. Open a notification: verify it opens the relevant invitation. Return Home and check joined collections refresh.
9. Let staging sleep or redeploy; reopen. Mobile shows a connection wait and preserves the account. The scheduled ping is best effort.

## Validation and remaining limits

Before packaging: backend 88 passed, 3 skipped; guest web TypeScript/build and proxy security test passed. Dart syntax parsed successfully. Flutter SDK setup was rejected by automatic approval review after it attempted a cloud metadata request; Flutter analyze/tests and APK build were not run here. Run them locally/CI.

Reference boards reviewed: existing-user authentication, contribution/organizer management, and the combined organizer/contributor flow. This update improves their flow and branding consistency; it is NOT a verified pixel-perfect reproduction of all boards. That requires rendered device comparisons. The complete requests, P2P, Near2P, settlement and cash screens remain later work. Real payments remain last.

Guest browser sessions currently expire with their access cookie and may request another OTP later; mobile has refresh-session restoration. The demo is local UI, not a persisted payment simulator. A general link currently permits verified self-joining; a configurable invite-only collection policy is not included.
