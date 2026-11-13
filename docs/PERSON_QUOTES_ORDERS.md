# Person payment quotes and prepared orders

This increment follows receiving destination migration d16a9e7fa010 and adds e27ba08fb011. It implements backend review terms and durable preparation for Request and Pay. It does not initiate either payment leg, enable Flutter payment buttons, mark requests paid, or issue receipts. No new diagnostic endpoint/token is introduced.

## What is now implemented

- POST `/api/v1/person-payments/quotes` accepts `request_id` plus `payer_method`, or `recipient_id`, `amount`, `payer_method`. A request's beneficiary and amount come from the server. Client overrides are rejected.
- Quotes bind payer identity/phone, MeSomb application, recipient, immutable receiving destination, payer operator, explicit fee-policy snapshot, amount breakdown and expiry. Lifetime is at most 300 seconds and never past request expiry.
- GET `/api/v1/person-payments/quotes/{id}` is private to the payer.
- POST `/api/v1/person-payments/orders` takes `quote_id`, `consent=ACCEPT_QUOTED_TOTAL` and the existing `Idempotency-Key` header. Replays recover the same order; conflicting keys fail. Only one READY order is permitted per request.
- Acceptance rechecks request status, amount, ownership, receiving consent, payer identity, application and policy. PostgreSQL row locks serialize request cancellation/acceptance and recipient consent changes; uniqueness guards catch conflicting inserts. PostgreSQL concurrency has not been executed locally.
- GET `/api/v1/person-payments/orders` returns the latest 100 payer-owned orders; GET by ID recovers a specific order. Both preserve accepted terms after configuration changes.
- POST `/api/v1/person-payments/orders/{id}/cancel` cancels an unstarted order. Request cancellation/decline atomically invalidates its unstarted orders. Expired preparation no longer blocks a replacement quote/order.

`READY` means prepared, not funded. Collection and delivery independently remain `NOT_STARTED`. API responses explicitly report `receipt_available=false` and `execution_available=false`. Database constraints prevent accidentally using this schema as completed execution.

## Fee policy and arithmetic

There are NO default prices and no tariff inferred from the prior 1,000/980/20 sandbox response. Without both existing sandbox MeSomb configuration and an explicit valid `SENDOH_SANDBOX_PERSON_FEE_POLICY`, quote creation returns 503. Existing checkout and collection functionality remain independent.

Policy JSON requires every field: `version`, `collect_bps`, `collect_fixed`, `payout_bps`, `payout_fixed`, `sendoh_bps`, `sendoh_min`, `sendoh_cap`. Rates are integer basis points; fixed/minimum/cap amounts are integer XAF. For example, 200 basis points means 2%. Policy values are a sandbox engineering model, not provider-authoritative fee quotes. Do not enable a live tariff from these test fixtures.

Arithmetic assumes provider percentage fees rounded UP to whole XAF, collect fee applied to the total payer debit, and payout fee applied to recipient principal:

1. Sendoh fee = capped/floored percentage of recipient principal.
2. Delivery cost = fixed delivery charge + rounded percentage of principal.
3. Required collection net = principal + delivery cost + Sendoh fee.
4. Total debit = smallest integer whose net after collection fee covers that required net.

The cap applies to the Sendoh fee, not all provider costs. Provider fees are not Sendoh revenue. No principal is deducted to fund fees. The accepted policy snapshot and amount breakdown are immutable through the API.

Tests use a SYNTHETIC policy (2% collect, 1% payout, 75 XAF Sendoh minimum) solely to verify calculations. These are NOT approved prices or verified MeSomb rates. Actual provider rounding, tariffs, service differences, fee treatment and payout costs must be verified before execution is enabled. Until then, leave the new policy variable unset on Render. Do not disable existing collection payments.

## Product integration still required

Next: extend these prepared orders with durable, separately reconciled collection/delivery attempts. A funding claim must atomically recheck expiration, request state, destination consent and payer authorization immediately before dispatch. Do not dispatch from READY without this claim; current implementation contains no dispatch route.

Expected collection net is a quote, not spendable funds. Actual confirmed net must cover principal and delivery costs before payout. A collected-but-undelivered payment remains an unresolved obligation; no automatic new charge, false receipt or paid request.

The future delivery phase must prevent request cancellation once funding starts and must preserve payout reference across ambiguous outcomes. Product notifications and paid state follow verified completion, not order creation. Existing push messages continue for request create/cancel/decline only.

Frontend remains unchanged. Wire the existing approved review screen to these terms only when execution/recovery are ready, with mockup approval for any new receiving-account setup screen.

## Validation and deployment

Backend suite covers rounding boundaries, minimum/cap, absent/invalid policy, private access, tampered amounts, fee changes, receiving destination changes, phone changes, expiry, idempotent replay, cancel/decline invalidation, separate not-started states and migration preservation. Tests do not prove external payout success or PostgreSQL race handling.

Run the full backend suite before committing. Existing Render Alembic startup applies the schema; no new build/start command. Downgrade refuses to drop quote/order evidence. No new APK is needed for this backend increment.
