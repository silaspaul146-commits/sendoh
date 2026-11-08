# Sendoh settlement foundation

This backend-only increment follows the guest checkout integration. It does not change approved UI, enable transfers, mark requests paid, or activate Near2Pay.

## Included
- Verified collection gross, provider fee, net and verification timestamp persist as exact decimal evidence.
- Collection totals continue to use gross contributions. Provider fee is not Sendoh revenue.
- Existing successful payments retain unknown accounting until a successful detailed provider lookup; no inferred tariff and no fabricated zero fee.
- Duplicate reconciliation keeps one success event. Conflicting subsequent accounting is flagged for review and does not overwrite saved evidence.
- The payment API adds accounting metadata using decimal strings. Existing fields remain unchanged. Recipient delivery remains explicitly unconfirmed.
- Internal MeSomb deposit transport matches the installed official Python SDK 2.1.2: payment/deposit/, receiver, body trxID. It sends one request and does not automatically retry ambiguous outcomes. It has no public endpoint or active caller.
- Migration b94e7c5d8008 follows a83d6b4c7007 and adds nullable columns. Downgrade refuses to discard verified accounting evidence.

## Validation
Backend suite: 201 passed, 3 skipped. Tests cover successful accounting, repeated reconciliation, conflicting fees, legacy unknown fees, invalid decimals, transport signing/body validation, ambiguous payout responses and migration preservation. Tests use SQLite and mocked provider transport. No real or sandbox payout was initiated by this package, and no PostgreSQL migration was executed here.

## Apply and deploy
Run git apply --check before applying. If the check fails, stop and share the output; do not force it.
Run python -m pytest -q from services/backend.
Commit the patch files and push to main after tests pass. Your Render build currently runs pip install -r requirements.lock && python -m alembic upgrade head; verify the migration command still appears in the deployed service settings/logs. No new secrets, Flutter build or Vercel change is required.

After deployment, the connected Neon database should report b94e7c5d8008 in alembic_version.
Existing payment evidence is enriched at the next due reconciliation, not at migration time. The existing worker may schedule terminal payment checks up to a day apart. Do not create another charge to obtain accounting.

Read-only checks:

```sql
SELECT version_num FROM alembic_version;
SELECT id, amount, status, confirmed_gross, confirmed_provider_fee,
       confirmed_net, accounting_verified_at, review_reason
FROM provider_payments
WHERE id = '7c994af8-f4e7-486a-b2f2-4517add40c2a';
```
Expected after verified reconciliation of the previously observed transaction: gross 1000, provider fee 20, net 980. These are observed values for that transaction, not a promised tariff.

## Next integration gate
MeSomb must confirm sandbox deposit capability for the application and the recipient-credit/fee response contract. The web documentation has inconsistent examples (deposit section lists collect path/payer while its example uses receiver); the installed official SDK resolves the outgoing transport, but does not prove incoming accounting semantics.

Then implement:
1. Recipient-owned verified payout destination, immutable server-issued quote with explicit payer total/recipient amount/provider charges/Sendoh charge. Exact Sendoh pricing remains a product decision; no guessed business model.
2. Durable payment order with independently persisted collection and payout legs. Commit and atomically claim each leg before dispatch. A timeout goes to lookup/reconciliation, never blind resubmission. Funded-but-undelivered remains a recoverable obligation, not a success.
3. Request settlement locks the obligation against cancellation/expiry races and becomes paid only after verified delivery.
4. Pay shares that engine and verifies recipient identity before payer authorization.
5. Near2Pay uses expiring scoped QR and short-code sessions, recipient/amount confirmation, explicit authorization, shared status and replay protection. It can reference a collection or request. No proximity-triggered debit or offline success.
6. Durable payer/recipient notifications linked to the exact order.

Official reference: https://docs.mesomb.com/development/payment
SDK cross-check: installed pymesomb==2.1.2, PaymentOperation.make_deposit.
