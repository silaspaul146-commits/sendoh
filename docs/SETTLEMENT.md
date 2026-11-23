# Close and settle

Settlement answers three questions with server-computed figures:

- **How much did we raise?** Mobile Money confirmed by MeSomb, plus cash the organizer recorded. The two are always shown separately.
- **What will reach my phone?** Confirmed Mobile Money, minus the collection fees MeSomb reported, minus Sendoh's settlement fee and any payout cost. Cash is not sent: the organizer already holds it, and no Sendoh fee applies to it.
- **Did my contribution count?** A member's position includes their confirmed Mobile Money and the cash recorded for them. Members can flag a cash record they disagree with.

## Flow

1. **Collection page (organizer).** Shows the amount raised, split into Mobile Money and cash. "Target reached" shows while the collection is open. The page offers "Edit cash records" and "Review settlement".
2. **Review.** Leads with "You receive X on MTN MoMo ··· 123". Fees expand on tap. One line covers the difference: "You already hold N FCFA in cash." It has one "Close and send" button.
3. **Sending → Delivered.** The same screen follows the payout. It shows "Delivered" only after the MeSomb lookup matches the amount, operator and receiver. A problem appears only when one exists. There is never a second Send button while a payout is unresolved.
4. **Member.** "Your 5,000 FCFA share is paid", with Mobile Money and cash recorded by the organizer shown separately, and a quiet "Flag a cash error" link.

## Rules

- Closing is blocked while any payment is still confirming, and while MeSomb has not reported fees for every payment.
- The settlement row is the payout reservation. It commits, together with the collection becoming CLOSED, before the deposit is sent. Only that request sends. Recovery (background worker, `/settlement/refresh`) only looks the payout up. A committed payout is never sent again, whatever happens.
- Delivery failure moves the settlement to REVIEW. The funds are retained and nobody is charged again.
- Closed and settled collections stay readable on the public link and in a member's view. Joining and contributing require an open collection.

## API

- `GET /api/v1/collections/{id}/settlement`: organizer overview. Returns `raised`, `blockers`, `quote`, `destination` and `settlement`.
- `POST /api/v1/collections/{id}/cash`: `{entries:[{participant_id, amount}]}`, while open. An amount of 0 removes the record. Members are notified of cash recorded in their name.
- `POST /api/v1/collections/{id}/cash/flag`: a member disputes their cash record. The organizer is notified once per record version.
- `POST /api/v1/collections/{id}/settlement`: requires the `Idempotency-Key` header and `{consent:"CLOSE_AND_SEND", payout_amount}`. The amount must equal the current quote.
- `POST /api/v1/collections/{id}/settlement/refresh`: a lookup only. It never sends money.

## Configuration (off by default)

Settlement is unavailable rather than free until both settings are present on Render.

### Settlement fee policy (adopted 23 Nov 2026)

```
SENDOH_SANDBOX_SETTLEMENT_PAYOUTS=1
SENDOH_SANDBOX_SETTLEMENT_FEE_POLICY={"version":"settle-2026-11-v1","sendoh_bps":100,"sendoh_min":75,"sendoh_cap":2000,"payout_bps":0,"payout_fixed":0}
```

The model:
- Sendoh fee = 1% of confirmed Mobile Money, rounded up to a whole FCFA.
- The fee is never below 75 FCFA. The minimum applies below 7,500 raised.
- The fee is never above 2,000 FCFA. The cap applies above 200,000 raised.
- Cash is not charged.
- MeSomb's collection fee is whatever MeSomb reported on each payment; Sendoh does not set it.

Organizer receives = Mobile Money − MeSomb fees − Sendoh fee.

| Mobile Money raised | MeSomb fees (about 2%, as observed) | Sendoh fee | Organizer receives | Total cost |
|---:|---:|---:|---:|---:|
| 5,000 | 100 | 75 (minimum) | 4,825 | 3.5% |
| 50,000 | 1,000 | 500 | 48,500 | 3.0% |
| 300,000 | 6,000 | 2,000 (cap) | 292,000 | 2.7% |

The MeSomb fees come from one sandbox payment: 20 FCFA on 1,000 FCFA. They are not a published MeSomb tariff, so verify them before going live.

The payout cost stays 0. A non-zero payout cost is refused until MeSomb's payout fee contract is verified. In sandbox, the organizer's receiving number must be one of `MESOMB_TEST_PHONES`.

### Request and Pay fee policy (same Sendoh rule)

```
SENDOH_SANDBOX_PERSON_PAYMENTS=1
SENDOH_SANDBOX_PERSON_FEE_POLICY={"version":"person-2026-11-v1","collect_bps":200,"collect_fixed":0,"payout_bps":0,"payout_fixed":0,"sendoh_bps":100,"sendoh_min":75,"sendoh_cap":2000}
```

The recipient always gets the exact amount. The payer covers the fees:

| Recipient gets | Sendoh fee | MeSomb fee (2% model) | Payer pays |
|---:|---:|---:|---:|
| 1,000 | 75 | 22 | 1,097 |
| 10,000 | 100 | 207 | 10,307 |
| 100,000 | 1,000 | 2,062 | 103,062 |

The 75 FCFA minimum makes small transfers costly: about 10% on 1,000 FCFA. Revisit the minimum for person-to-person payments after the pilot. In sandbox, both people must be among `MESOMB_TEST_PHONES`.

## Recurring collections (rounds)

- Turn on "Repeats in rounds" when creating a collection, for a njangi or tontine.
- Contributions, cash and settlement belong to the current round. Every total and member position is for that round.
- After a round is settled, the collection page offers "Start next round" (recurring collections only). Members start again at 0 FCFA and are notified.
- Earlier rounds stay settled. They are listed in `history` in the settlement overview.
- `POST /api/v1/collections/{id}/rounds` with `{from_round}`. Sending it twice opens the round once.
- Migration `c9f6e4ab0015` adds `recurring` and `round`. Existing data is round 1.

## Who receives (rotating beneficiaries)

- Each round is paid to the organizer by default, or to one joined member chosen on the review screen ("Change who receives") or when starting the next round.
- The payout goes to the beneficiary's own receiving number. Only the beneficiary can set it; until then the review shows a blocker.
- The beneficiary is notified "You received …". The organizer sees "… delivered to Aïcha's MTN MoMo". Other members see who it was delivered to.
- `POST /api/v1/collections/{id}/beneficiary` with `{participant_id}` (null means the organizer). `POST .../rounds` accepts `beneficiary_participant_id`.
- Migration `d2a7f5bc0016` adds the beneficiary columns.

## Not yet

- **Real money.** These are MeSomb sandbox payouts only.

Migration `b8e5d3fa0014` adds the CLOSED/SETTLED statuses, `cash_records`, `settlements` and `notifications.settlement_id`. Its downgrade refuses to discard settlement or cash evidence.
