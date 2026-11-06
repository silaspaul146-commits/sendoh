# MeSomb integration checkpoint

Base: b9b880c. Reviewed 5 November 2026. Stage: provider transport foundation.

## Existing journeys preserved

Registered Flutter users and web guests already converge on authenticated backend
identities. Guests verify a phone, provide a name and join a collection; they are
not anonymous payers. Both currently use TestPayment. MoneyRequest is independent
and cannot yet be paid. P2P checkout and QR resolution are not operational.

## Added in this increment

- Backend-only MeSomb client using pymesomb 2.1.2 signing and bounded HTTPX transport.
- Asynchronous collect initiation and external-reference lookup.
- Explicit fee treatment; no assumed Sendoh or provider pricing.
- No automatic retries for initiation, including network failures.
- Transaction checks for amount, currency, country, method, payer, type and provider ID.
- Conservative status mapping; unknown/intermediate states never fulfil obligations.
- Mock transport tests; no real provider credentials or transactions used.

This module is not wired into any endpoint. Existing configuration, Flutter,
guest checkout, collection totals and notifications are unchanged. No migration
is included. Installing this increment does not enable real payments.

## Next implementation boundary

Persist each provider payment attempt BEFORE making a network call. Store its
Sendoh payer, purpose, collection/participant, beneficiary, mode, external reference,
request fingerprint, provider ID, amounts and reconciliation state. Serialize
duplicate initiation. An ambiguous attempt remains unresolved; absence from lookup
does not authorize another collect. Preserve existing TestPayment records separately.

Bind each lookup result to the expected application and external reference; reject
zero/multiple ambiguous matches. Validate retrieved transaction details before an
atomic state change. Confirm amount/fees/trxamount semantics with sandbox fixtures
before using validate_transaction in an accounting path.

Add signed webhook receipt and event deduplication, persistent reconciliation work,
and exactly-once business effects. Reconcile after missed callbacks and process
out-of-order events conservatively. Preserve refund evidence and accounting
adjustments even if user-requested refunds are outside the initial product scope.

Only verified LIVE success contributes to real collected totals. Provider sandbox
records need their own mode and must remain distinct from live receipts and totals.

Future request fulfilment needs a payment relationship and paid-state migration.
P2P/Near2Pay additionally need a verified beneficiary and payout lifecycle. A debit
into the application's MeSomb account is not proof of recipient settlement.

## Account and contract questions before first provider transaction

1. Is the application's authorized test mode still available? Documentation says
   verification submission changes test-mode availability; a UI toggle alone does
   not control integration code. Confirm actual account state with MeSomb.
2. Confirm enabled MTN/Orange test scenarios and documented test numbers.
3. Confirm duplicate X-MeSomb-TrxID behaviour and delayed external-reference lookup.
   The SDK sends trx_id as this header. It is not assumed to guarantee idempotency.
4. Confirm payer debit, credited amount, fees, refunds and settlement semantics.
5. Confirm permission and account structure for collecting on behalf of organizers
   and subsequently paying recipients. No production routing assumption is made.

Credentials and webhook signing secrets belong on the backend, never in Flutter,
guest JavaScript, source control, screenshots or chat.

## Validation

Executed with a fresh Python 3.12 environment using requirements.txt and pymesomb
2.1.2, not an exact recreation of requirements.lock:

    python -m pytest -q tests/test_mesomb_provider.py tests/test_payments.py tests/test_money_requests.py

Result: 46 passed, one existing Starlette/httpx deprecation warning.
No provider network test, deployed environment test or full frontend test performed.

## References

- https://docs.mesomb.com/development/payment
- https://docs.mesomb.com/development/authentication
- https://docs.mesomb.com/development/statues
- https://docs.mesomb.com/development/test-mode
- https://docs.mesomb.com/development/webhooks/verifying-signatures
- https://pypi.org/project/pymesomb/2.1.2/
- https://mesomb.com/en/challenge/reglement

Challenge Track A permits an authorized test integration. Submission requires an
accessible demo, integration evidence and a 60–90-second video by 17 December 2026
at 23:59 Cameroon time. First demo should cover both registered-user and guest
contributions and the resulting attribution, progress and notifications.
