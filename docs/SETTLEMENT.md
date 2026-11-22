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

Settlement is unavailable rather than free until both of these are set on Render:

```
SENDOH_SANDBOX_SETTLEMENT_PAYOUTS=1
SENDOH_SANDBOX_SETTLEMENT_FEE_POLICY={"version":"...","sendoh_bps":...,"sendoh_min":75,"sendoh_cap":2000,"payout_bps":0,"payout_fixed":0}
```

`sendoh_bps` is the Sendoh settlement rate in basis points (100 = 1%). **It is a business decision and is not yet approved.** The 1% used in the mockups and tests is illustrative only. A non-zero payout cost is refused until MeSomb's payout fee contract is verified. In sandbox, the organizer's receiving number must be one of `MESOMB_TEST_PHONES`.

## Not yet

- **Recurring collections and "Start next round".** This needs contributions tracked per round. It will show on the settled collection page only for recurring collections.
- **Real money.** These are MeSomb sandbox payouts only.

Migration `b8e5d3fa0014` adds the CLOSED/SETTLED statuses, `cash_records`, `settlements` and `notifications.settlement_id`. Its downgrade refuses to discard settlement or cash evidence.
