# Request/Pay sandbox execution backend

Prerequisite: Quotes/Orders patch, migration e27ba08fb011. This patch adds migration f38cb19fc012. It does not modify Flutter, guest web, or Near2Pay scanning. It does not enable live payments.

## Implemented behavior

POST `/api/v1/person-payments/orders/{id}/execute` accepts an already prepared order from its authenticated payer. It rechecks consent expiry, current phone identity, receiving destination, tariff snapshot, application and request eligibility. It commits an execution and a unique collection leg before calling MeSomb. Repeated calls recover that execution, not another debit.

POST `/api/v1/person-payments/orders/{id}/refresh` reconciles due legs and may dispatch the FIRST delivery after funding becomes verified. It is NOT a read-only endpoint: it can initiate the payout leg. GET the order to read saved state without triggering work. The existing background reconciliation loop also advances funded orders.

Collection and delivery use separate durable UUID references. Provider submission responses never establish success. Lookup must bind amount, operator, currency, country, phone and provider transaction identity. Provider transaction IDs are globally claimed per application across existing collection payments and new person-payment legs. The migration backfills previously saved collection IDs.

Only confirmed collection net sufficient to cover the quoted recipient amount, quoted delivery cost and Sendoh fee can advance to delivery. Lower net, contradictory results or unexpected evidence put the order in REVIEW. The recipient amount is never reduced to accommodate fees.

A delivery leg is committed before the payout request. A timeout or process crash after either reservation never permits resubmission of that leg. A crash before actual dispatch can leave a permanently unresolved attempt; manual provider investigation is required. This favors avoiding duplicate charges over assuming the provider did not receive a request.

State progression is COLLECTING -> FUNDED -> DELIVERING -> SUCCEEDED. Collection failure becomes FAILED and permits a new request-payment attempt. Delivery failure retains the successful collection and moves to REVIEW, without another charge. Unknown lookup remains pending or under review. A later refund revokes receipt availability and requires review; no automatic reversal is implemented.

Request responses derive PROCESSING, PAYMENT_REVIEW or PAID from their execution. The legacy money_requests database status remains PENDING; clients MUST use the API status, not query that column as proof of settlement. A request cannot be cancelled/declined while execution is active or completed. Unstarted prepared orders remain cancellable.

Completion, failure and review notifications are committed with state changes, using unique event keys. Payment push bodies include the recipient and amount. The payer and beneficiary may read an executed order; only the payer may initiate. Direct-pay notification deep links and Flutter receipt rendering remain to be connected in the frontend increment.

## Provider contract boundary

This first delivery verifier accepts only DEPOSIT evidence whose amount and trxamount both equal recipient principal and whose fees equal zero, with matching CM/XAF/operator/receiver/provider ID. Nonzero delivery quotes are rejected BEFORE collection. Other payout evidence is held for review, not accepted based on a guessed field mapping.

The installed official pymesomb 2.1.2 source moves trxID from the body to X-MeSomb-TrxID before signing. The transport now follows that behavior; no duplicate trxID remains in the signed deposit body. This change has mock-transport coverage, not proof of live provider success.

Official references reviewed 12 November 2026:
- https://docs.mesomb.com/development/payment
- https://docs.mesomb.com/development/webhooks/event-catalog
- https://docs.mesomb.com/introduction/fees-and-settlement

The API documentation and prior observed collection payload are not sufficient evidence for all payout fee conventions. A real sandbox payout response still needs to be matched to this strict verifier. Confirmed collection does not establish provider balance availability, payout permissions or production suitability.

## Configuration and rollout

Default: execution OFF. Installing this patch does not submit payments. No new diagnostic token is required and Render build/start commands are unchanged.

Controlled execution requires all existing sandbox configuration, an explicitly configured SENDOH_SANDBOX_PERSON_FEE_POLICY, and SENDOH_SANDBOX_PERSON_PAYMENTS=1. Both authenticated payer and recipient phone identities must be in MESOMB_TEST_PHONES. Do not add real phones merely to bypass this gate. Existing auth identities are not proof that a real mobile-money account can receive funds. Test account identity selection must respect provider-documented scenario numbers and Sendoh's unique-phone constraint.

Leave execution OFF until the fee policy and sandbox identities are deliberately configured for validation. Do not copy synthetic test rates into production. Disabling the flag stops new collection/delivery dispatch; reconciliation of existing references continues while the MeSomb configuration remains available.

The quote fee model assumes explicit whole-XAF rounding and is not a provider tariff API. Live fee coverage, payouts with nonzero fees, available-balance controls, PostgreSQL concurrency runs, operational review tooling, real SMS and device end-to-end recovery remain release requirements.

## Installation

Run apply.py --project PATH --check, then apply.py --project PATH, then the full backend test suite. The installer detects already-applied patches and stops safely on a mismatched source. Stage only changed-files.txt and review before committing. Existing startup migration installs f38cb19fc012. Downgrade refuses to discard execution evidence.

Automated validation uses SQLite and mocked provider responses. No external payout was executed by this development environment. Passing these tests does not certify a real sandbox or live transfer.
