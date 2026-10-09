# Sendoh phase 2: participant identity and invitations

This source update builds on your deployed phase-one identity update. It adds
organizer invitations and recipient acceptance. It does not deploy itself or
contain a compiled APK. Payments remain disabled.

## What changes

| Area | Implemented behaviour |
| --- | --- |
| Organizer | Open an active collection, then Invite by username or phone. Use an exact username or Cameroon phone number. |
| Existing manual participant | Open Participants, select the name, then Invite this person. The same participant ID and expected amount are kept. Names alone are not identity proof. |
| Registered recipient | Open Home > Invitations & joined collections (also the envelope icon). Review the organizer, collection and your own expected amount; accept or decline. |
| New phone | The invitation is reserved for that phone. After signup, OTP verification and profile completion, it appears in that account's inbox. No local OTP command is needed for this feature. |
| Joined member | Sees collection details and their own expectation. Does not gain organizer controls or access to other participants. |
| Organizer status | Name only/unverified, Invited, Joined, Declined, Cancelled or Expired. Unpaid is a separate payment label. Acceptance never records a contribution. |
| Invitation lifecycle | Expires after 14 days. Organizer may cancel a pending invite. Cancelled/expired invites can be issued again; declined invitations cannot be resent by this endpoint. |
| Privacy | Guest pages never receive the roster. Only the intended authenticated account/verified phone can respond. A collection link is not membership proof. Username invitations do not disclose the target's full phone number. |

Duplicate username/phone invitations resolve to the same participant. Two manual
rows are never silently merged. Repeated requests use idempotency keys. The server
limits organizers to 20 invitation attempts per minute, including failed lookups,
and 200 participant rows per collection. Lists currently return up to 200 entries;
pagination is a follow-up before larger rollouts.

New screens reuse the existing Sendoh palette, logo and components. Exact visual
matching against the earlier image boards has not been verified in this update;
those attachments are not available in the current workspace.

## Apply from the extracted update folder

Extract Sendoh_Invitations_Update.zip. Open PowerShell in the folder containing
Sendoh_Invitations_Update.py, then run these commands one at a time:

```powershell
python .\Sendoh_Invitations_Update.py --project C:\Users\IHIMBRU\Desktop\sendoh --check
python .\Sendoh_Invitations_Update.py --project C:\Users\IHIMBRU\Desktop\sendoh --apply
```

This updates your existing repository, not the extracted folder. It backs up
replacements, leaves .gitignore and config.dart alone, and preserves your deployed
URLs, secrets and native signing configuration. Formatting-only Dart changes are
compared with your installed Dart formatter in temporary files; genuine code edits
still stop the update. If a conflict remains, export with `--export proposed-update`
and inspect it. Do not force-overwrite unrelated changes.

## Verify locally

```powershell
cd C:\Users\IHIMBRU\Desktop\sendoh\services\backend
$env:SENDOH_ENV="development"
.\.venv\Scripts\python.exe -m pytest -q

cd ..\..\apps\organizer_flutter
flutter pub get
dart format lib/main.dart lib/invitations.dart test/invitations_test.dart
flutter analyze
flutter test
```

Stop on a failed check. No new Python/Flutter dependency is introduced. The web
application has no phase-two file changes; this update does not resolve the three
high-severity npm audit findings reported during phase one. Review those separately
before wider public promotion; do not use a blind `npm audit fix --force`.

Validation performed while preparing the package: 63 backend tests passed; two
PostgreSQL-specific concurrency tests skipped locally and are included for the
existing PostgreSQL CI job. Fresh migration, schema comparison, legacy-row
preservation and upgrade/downgrade amount-constraint checks passed. Dart syntax
was parsed successfully. Flutter SDK was unavailable here: Flutter analysis,
widget tests, APK build and physical-device checks must pass locally/in CI.

## Commit and push the update

After the checks pass:

```powershell
cd C:\Users\IHIMBRU\Desktop\sendoh
git status --short
Get-Content .\sendoh-invitations-paths.txt | ForEach-Object { git add -- $_ }
git diff --cached --stat
git commit -m "Add account-bound collection invitations and member views"
git push
```

The path-list file is an installation helper, not application source. Review any
other working-tree edits separately. This update does not need a new pubspec.lock;
if pub get changed it, review that diff before deciding to stage it.

## Cloud rollout: backend first, then APK

1. Render must deploy the new backend code and run `python -m alembic upgrade head`
   against the existing Neon database. Keep your existing Render build command:
   `pip install -r requirements.lock && python -m alembic upgrade head`.
2. Migration `c49f2d0e3003` follows phase one's `b38e1c9d2002`. It adds invitation
   fields and a rate-limit table. Existing user/collection/participant IDs remain.
   Existing participant names become UNVERIFIED; they are never auto-linked.
   Do not reset Neon or run destructive downgrade commands to undo a UI issue.
3. Wait for Render to be live. Open https://sendoh.onrender.com/health and check
   `status: ok` and `version: 0.3.0`. Check that the build's migration step succeeded.
4. Wait for backend, web and Flutter GitHub Actions checks to pass. Download the
   new `sendoh-android-staging` artifact and install its APK only after step 3.
   The existing workflow builds from the pushed source; no new signing secret or
   external service is required. iOS remains source-compatible in intent, but
   still requires a Mac build, signing and device verification.
5. Vercel may redeploy from the same push. Its API_INTERNAL_URL remains the HTTPS
   Render URL. Guest public collection pages continue to omit private rosters.

Everything added is stored in Neon or runs in the existing backend/app. No credit
card, new provider account, local background server or new cloud environment
variable is needed. Keep your phase-one cloud OTP provider configuration.

## Test with two accounts before sharing the APK widely

1. Account A creates a collection. Invite account B by exact username.
2. B opens Invitations & joined collections and reviews the correct organizer.
3. B accepts. It moves into Joined; A refreshes and sees Joined and B's username.
   Collected money stays zero. B cannot open A's management view.
4. A invites B again by verified phone. There is still one participant row.
5. In a separate collection, B declines. It leaves the pending inbox; A sees
   Declined and cannot resend it. In another, cancel before B accepts and confirm
   B cannot accept the stale invitation.
6. Add a manual participant with a different expected amount. Link that row to B.
   Verify the amount and row count are preserved.
7. Invite a new phone, then sign up using that number through cloud OTP. After
   profile completion, verify the pending invitation appears for that account.
8. Open the guest link in an incognito browser: no member names or phones appear.
9. Test narrow screens, large text and offline/retry. Acceptance may have reached
   the server if a response was lost; refresh before assuming it failed.

## What remains, in order

- Phase 3: durable notification outbox, registered-user activity notifications,
  device registration and FCM push. This phase's inbox is the initial recipient
  entry point, not background notification delivery. Users refresh/open it today.
- Phase 4: scoped guest OTP and invitation claims. For now a non-user phone invite
  needs signup to accept; the public link does not let a guest claim someone else.
  Payer and credited contributor identity will remain separate.
- Requests and P2P intent/review/status flows.
- Near2P: scan QR, confirm resolved identity, then request/P2P; optional consented
  proximity discovery after that.
- CamPay/payment integration LAST, with provider-confirmed status, idempotency,
  callbacks and reconciliation. No payment-success behaviour is simulated here.

No invitation SMS or push is sent by this package. It does not change OTP delivery,
implement guest claims, or add money movement. Let invitees know via your usual
WhatsApp conversation while in-app invitations are being tested.
