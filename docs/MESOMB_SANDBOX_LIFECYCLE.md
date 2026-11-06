# Sendoh: MeSomb sandbox lifecycle, increment 2

Apply after Sendoh_MeSomb_Foundation.patch. No Flutter/guest UI changes are included.
This increment connects backend endpoints, not the existing checkout buttons.
Registered app users and verified web guests use the same authenticated actor model.

## Implemented

- Durable sandbox attempts before dispatch, with stable external UUID references.
- Payer, participant, collection and beneficiary attribution.
- Request fingerprint/idempotency and one unresolved attempt per payer/collection.
- Signed asynchronous collect; all provider initiation outcomes await retrieval.
- Leased recovery worker every 15 seconds, exponential backoff up to one hour.
- Final records rechecked daily for later refund/correction evidence.
- Signed webhook verification, five-minute tolerance and durable event deduplication.
- Webhooks schedule trusted API retrieval; webhook payloads never directly credit totals.
- Monotonic verified transitions and uniquely recorded status effects.
- Sandbox totals independent from both legacy simulations and live-money totals.
- Original payment records and status events retained following refunds.
- Actor-scoped detail/history and status refresh endpoints.
- Additive Alembic migration a83d6b4c7007 after f72c5a3b6006.

## Not yet delivered

No real MeSomb sandbox call has been performed by the development assistant.
No live settlement, provider fee quote, payout, request fulfilment or UI integration.
No new push-notification presentation; verified changes currently write organizer activity.
The former simulate endpoints remain restricted to their separate TestPayment records.
Public/participant summaries add sandbox_collected_amount/sandbox_paid_amount;
collected_amount remains real-money-only and zero in this increment.

## Local checks (PowerShell, after applying the patch)

    cd "$env:USERPROFILE\Desktop\sendoh\services\backend"
    python -m pytest -q

Tests create isolated databases; they must not be pointed at Neon production.
Validation used Python 3.12 and SQLite with requirements.txt dependencies. PostgreSQL
locking behaviour and the deployed Render worker still require staging verification.

## Deployment sequence

1. Keep SENDOH_MESOMB_MODE disabled or unset for the first deployment.
2. Commit the foundation and this increment, including migration and requirements.
3. Apply migration against the intended staging Neon database before starting new code.
   Use the existing Render deployment migration mechanism if it actually runs there.
   Confirm its logs; the presence of preDeployCommand in a file is not evidence it ran.
   Required migration command from services/backend: python -m alembic upgrade head.
   Do not run an unconfigured desktop migration and assume it migrated Neon.
4. After deployment, create a MeSomb webhook endpoint for the SANDBOX application:
   https://YOUR-EXISTING-RENDER-API/api/v1/webhooks/mesomb
   Subscribe to relevant payment transaction and refund events available in the dashboard.
   Store its generated signing secret privately in Render.
5. Configure the variables below, then enable sandbox mode and redeploy.
6. Confirm /health reports mesomb_sandbox_enabled=true and payments_enabled=false.
7. Exercise backend endpoints with an authenticated staging account before wiring clients.

## Render environment variables (values stay private)

SENDOH_MESOMB_MODE=sandbox
MESOMB_SANDBOX_CONFIRMED=1
MESOMB_APPLICATION_KEY=<sandbox application key>
MESOMB_ACCESS_KEY=<sandbox access key>
MESOMB_SECRET_KEY=<sandbox secret key>
MESOMB_WEBHOOK_SECRET=<endpoint signing secret, distinct from API secret>
MESOMB_TEST_PHONES=<comma-separated documented MeSomb test numbers>

Only staging/development is allowed. Do not change SENDOH_ENV or existing OTP settings.
IMPORTANT: the sandbox label and allowlist are local guards, not a provider sandbox
switch. MeSomb decides mode from the authorized application/account. Use only the
confirmed test application and provider-documented test numbers, never live keys.
The API application key and webhook secret must belong to the same application.

## API contract

POST /api/v1/provider-payments
Authorization: existing Sendoh bearer access token
Idempotency-Key: a stable unique key for this one payment attempt

    {
      "collection_id": "existing-collection-uuid",
      "amount": 1000,
      "method": "MTN",
      "payer_phone": "PROVIDER_DOCUMENTED_TEST_NUMBER"
    }

For the guest journey, supply collection_token instead of collection_id. An existing
verified session and accepted membership are required. Do not submit both identifiers.
The sandbox payment number is distinct from the verified Sendoh identity phone.
Amounts are whole XAF. Sandbox calls explicitly use fees_included=true; this is NOT
an approved live fee policy. Capture real sandbox responses to confirm amount/fees/
trxamount semantics before production accounting or fee quoting.

GET /api/v1/provider-payments/{id}
POST /api/v1/provider-payments/{id}/refresh (empty body; respects retry schedule)
GET /api/v1/me/provider-payments (latest 100 payer/beneficiary records)

The organizer may read contribution records. Other users may not. A receipt flag
only describes a SANDBOX record; it is never proof of actual payment or settlement.
There is deliberately no client endpoint to simulate/force/cancel a provider outcome.

## First actual sandbox acceptance test

1. Use an existing collection and registered test member. Initiate one payment.
2. Repeat identical request/key: same attempt, only one provider collection.
3. Query until backend verification establishes the outcome; record provider reference.
4. Check matching MeSomb dashboard transaction and separate sandbox collection total.
5. Verify a failed scenario contributes zero; verify pending remains pending.
6. Repeat through collection_token as a verified guest identity.
7. Deliver/replay a valid provider webhook; totals/status effects must not duplicate.
8. Restart the staging backend while an attempt is pending; recovery resumes on startup.

Do not change the frontend to call these routes until the account's sandbox contract
has been verified. UI changes still require the user's mockup approval.

## Operational limits

If no provider transaction is found after an ambiguous initiation, the attempt stays
pending and blocks another attempt for that payer/collection. It must be investigated,
not reset automatically: the provider could have debited before responding.
No blind collect retry is available. Unknown status or mismatched amount/identity is
left unresolved with a review_reason. Account changes do not reconcile old attempts
against a different application. Refund/conflicting outcomes retain event history.

The worker runs while the web process runs. Render sleep/outage delays reconciliation;
durable attempts resume when it wakes. This is not a promise of continuous processing
on a sleeping free service. A continuously running worker/service is a production gate.
Unmatched early callbacks still wake pending attempts; later outcomes are recovered by
polling even if callbacks are delayed or missing. Payloads are hashed, not stored with
unnecessary customer data. Expected financial attributes are checked on API retrieval.
