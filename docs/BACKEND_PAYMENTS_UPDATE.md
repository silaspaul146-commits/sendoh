# Backend-connected test contribution flow

Built against commit b9ce553. Applies to the existing Sendoh project, not a new application.

## What changes

Both Flutter and guest web now use the same server ledger for collection payment attempts.
The steps follow the supplied contribution boards: amount, review, method, pending attempt,
result, receipt, collection and history. Guest identity stays bound to the verified account;
a public collection link never grants permission to impersonate a participant.

- `POST /api/v1/test-payments`: create a PENDING intent with an Idempotency-Key.
- `POST /api/v1/test-payments/{id}/simulate`: payer selects a test final result.
- `GET /api/v1/test-payments/{id}`: payer or collection organizer reads the saved record/receipt.
- `GET /api/v1/me/test-payments`: private history, optionally filtered by collection ID/token.
- `GET /api/v1/collections/{id}/test-payments`: organizer-only history.
- History is paginated, 50 entries per page. Pending records can be reopened.
- Success creates organizer activity and durable notification/push jobs for the organizer and payer.
- Duplicate identical results do not add totals, activity or notification jobs twice.
- A final result cannot be changed. Failed/cancelled retries create new attempts.
- A timeout never automatically replays a POST. The client retains the same creation key and body
  while on that screen; history recovers saved attempts after closing/reloading.
- Successful amounts feed `test_collected_amount`, `test_paid_amount` and test Paid/Partial/Unpaid statuses.
  `collected_amount` remains the real-money total, currently zero. Public views never expose the roster.
- An organizer may contribute as their own verified profile. They cannot simulate another person's payment.
- Minimum-total rules are enforced server-side. Expected totals permit partial/extra contributions.
- Test fees are zero. Fees in the supplied boards are examples, not approved provider pricing.

## Scope and limitations

No CamPay integration, mobile money debit, real settlement, wallet, reversal, cash recording,
Requests or P2P implementation is included in this update. These remain separate plan items.
This connects the contribution golden path; it does not claim exact pixel parity for every supplied board.
Test UI and receipts are explicitly labelled. Do not present test receipts as proof of real payment.
Push delivery is best effort; the durable inbox/history remain available when permission or delivery fails.
The organizer page refreshes on foreground push updates and can be refreshed manually.
Guest totals reload when returning from checkout; reopen a collection to refresh unauthenticated totals.
Test endpoints are disabled in production even when the flag is set. History remains readable by its owners.
No new packages or native/signing changes are required.

## Apply locally

Extract this ZIP and open PowerShell in its Sendoh_Backend_Payments_Update folder:

```powershell
python .\Sendoh_Backend_Payments_Update.py --project C:\Users\IHIMBRU\Desktop\sendoh --check
python .\Sendoh_Backend_Payments_Update.py --project C:\Users\IHIMBRU\Desktop\sendoh --apply
```

The updater checks original hashes (including CRLF normalization), backs up replaced files,
and stops without changes if a file differs. Formatting-only Dart edits are compared using your
installed `dart format`. Use `--export proposed-update` to inspect conflicts; do not force old files over local work.
It writes sendoh-backend-payments-paths.txt for staging only the intended files.

## Local checks (run these yourself)

```powershell
cd C:\Users\IHIMBRU\Desktop\sendoh\services\backend
$env:SENDOH_ENV="development"
$env:OTP_PROVIDER="local"
.\.venv\Scripts\python.exe -m pytest -q

cd ..\..\apps\guest_web
npm ci
npm run typecheck
npm run build

cd ..\organizer_flutter
flutter pub get
dart format lib/payment_demo.dart lib/invitations.dart lib/main.dart lib/notifications.dart
dart fix --apply --code=curly_braces_in_flow_control_structures
flutter analyze
flutter test
```

Source inspection, Python parsing and patch packaging were performed here. Flutter, web builds,
database tests and device testing are left to you as requested. The included backend tests cover
persistence, replay, conflicting outcomes, identity, authorization, minimum totals and migration preservation.

## Commit and deploy

After the checks pass:

```powershell
cd C:\Users\IHIMBRU\Desktop\sendoh
Get-Content .\sendoh-backend-payments-paths.txt | ForEach-Object { git add -- $_ }
git diff --cached --stat
git commit -m "Connect collection test payments across backend Flutter and guest web"
git push
```

Render: set `SENDOH_TEST_PAYMENTS=1` on staging. Keep existing OTP/Firebase settings.
The backend build must run `python -m alembic upgrade head` against the configured Neon database
before starting this backend. Expected new revision: e61b4f2a5005.
Verify /health returns `test_payments_enabled: true` and `payments_enabled: false`.
Vercel redeploys the guest web from the same pushed commit; retain API_INTERNAL_URL.
Then install the newly built GitHub Actions APK. The old APK still has the local-only demo.
Do not downgrade this database migration if you want to retain test payment history.

## End-to-end acceptance

1. Create a collection with expected contribution 3000 FCFA. Invite/join with a second verified account.
2. In the app, contribute 1000 via MTN, review, save the attempt and simulate success.
3. Organizer: test total 1000, member Partial, one activity entry and one payment notification.
4. Same contributor: open their guest collection link, verify identity, join/continue, open saved history.
   The app payment and reference must appear. No duplicate membership should be created.
5. In guest web, contribute another 2000 via Orange and simulate success. Both views now show test total 3000
   and the member is Test Paid. Real total remains zero.
6. Reopen the receipt after closing the browser/app. Reference and amount must match.
7. Simulate failure and cancellation on separate attempts. History records both; totals remain 3000.
8. Start an attempt, leave before deciding, then reopen it through history and complete it once.
9. Try another account's payment ID: unrelated accounts get 404. An organizer can read a member's record
   but cannot choose its result. Extra payer/participant identity fields are rejected.
10. Disable SENDOH_TEST_PAYMENTS: creating or completing test payments must fail; saved history remains.
