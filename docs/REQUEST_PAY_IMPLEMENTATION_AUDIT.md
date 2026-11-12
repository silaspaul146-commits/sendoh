# Request and Pay: implementation audit and receiving consent increment

## Findings from current code, 12 November 2026

| Journey | Existing implementation | Remaining implementation |
| --- | --- | --- |
| Collections | Authenticated MeSomb collection attempts; durable reference, reconciliation and fee evidence; totals derived from successful attempts | Organizer settlement and recipient delivery are separate, unfinished operations |
| Guest collection checkout | Existing guest identity and collection-token checkout integration | End-to-end release verification, including failure recovery |
| Request | Create, list, read, cancel, decline, expiry, idempotency and push outbox | Payment execution, processing/paid states, delivery receipt |
| Pay | Resolve exact username and prepare a Flutter draft | Gateway currently opens an unavailable dialog; no direct-payment execution endpoint |
| Near2Pay | UI entry point | Scanner gateway is a placeholder; QR identity resolution explicitly rejects requests |
| Recipient payout | Internal deposit transport and protected diagnostic | Verified payout contract, durable product settlement orders and reconciliation |

Evidence locations: `app/people.py`, `app/models.py`, `app/mesomb_payments.py`, `app/providers/mesomb.py`, `lib/money_requests.dart`. This is code inspection, not a claim that all journeys have passed device tests.

The current provider payment model requires a collection and participant. Do not fabricate a collection to route person payments. A request's `recipient_id` identifies the debtor: the payment beneficiary is its `requester_id`.

## Implemented in this increment

Recipient-owned receiving consent, stored as immutable versions. The account owner explicitly chooses MTN or Orange for their existing authenticated Cameroon phone identity. The caller cannot specify another phone or owner. Login phone identity does not prove wallet availability or operator ownership; `provider_verified` remains false.

- GET `/api/v1/me/receiving-destination`: owner's masked destination and version.
- POST same path: `method`, `expected_version`, `consent=RECEIVE_ON_MY_AUTHENTICATED_PHONE`. Initial version is zero. Identical replay is idempotent; stale conflicting updates are rejected. Previous versions remain recorded.
- POST `/api/v1/person-payments/preflight`: either `recipient_id` plus positive integer `amount`, or `request_id` alone. Request amounts and beneficiaries are server-derived; only the debtor can prepare payment. Cancelled/declined/expired requests are rejected. Payer receives no destination phone or internal destination ID.

Phone identity changes invalidate old receiving consent until the recipient consents again. The destination is not automatically inferred from a username, payer input or phone prefix.

Preflight is not a quote, payment reservation or permission to charge. It returns `quote=null`, `can_pay=false` and explicit missing capabilities. It never contacts MeSomb, initiates payments, changes requests or claims delivery. No new environment variables, tokens or diagnostic commands.

Migration: `d16a9e7fa010`, after existing `c05f8d6e9009`. The prior Render payout patch's source migration must be present, although its diagnostic token need not remain enabled. Downgrade refuses to discard saved consent.

## Next product increment

1. Recipient setup using existing profile design; obtain approval for any additional screen. The current patch does not alter Flutter or enable payment buttons.
2. Durable expiring fee quote binding payer, beneficiary, destination version, principal, currency and fee-policy version. No live tariff is inferred from the one observed 20 XAF fee on 1,000 XAF.
3. Two-leg order: separately persist payer collection and recipient delivery. Require verified funding and sufficient net funds for recipient principal plus payout cost. Do not reduce principal to cover fees or mistake provider fees for Sendoh revenue.
4. Lock/request state transition on acceptance to prevent competing payment/cancel/expiry; unique obligation guard; snapshot destination; authorize payer and replay the same order.
5. Reconcile both legs independently. Unknown dispatch outcomes permit lookup, never blind resubmission. Collected-but-undelivered funds remain an explicit recoverable obligation. Terminal delivery drives request completion, receipt, activity and durable notifications exactly once.
6. Connect existing Request/Pay review and checkout screens, then use the same order flow for expiring Near2Pay QR and short-code fallback. Recipient identity and amount require explicit confirmation. QR alone never charges.

## Release blockers, not hidden defaults

- Recipient payout has not been demonstrated successfully in the supplied deployment results.
- Live fee quote/payout funding policy is not implemented or approved for this MeSomb flow.
- Log-delivered staging OTP is not production SMS verification.
- Full PostgreSQL concurrency tests and device end-to-end payment recovery remain required.

Do not call this the completed Request/Pay integration. It supplies the recipient destination and preflight prerequisite without changing existing working collection checkout.
