# Sendoh product journeys

The promise: when two people open Sendoh, each can tell what happened to the same payment and whether they need to do anything next. Nobody should have to send a screenshot to prove they paid.

**Status labels**
- **Verified:** an automated end-to-end test covers it in this repository.
- **Implemented:** the code exists but has no end-to-end test.
- **Unverified:** needs staging, a device or provider access.
- **Not built:** missing.

No automated test proves MeSomb moved real money. Every payment test uses a fake provider.

Last updated: 24 Nov 2026 (milestone "one contribution, two phones").

## 1. Collect: one contribution, two phones (milestone 1)

*Marie wants to know whether her 5,000 FCFA counted. Alain wants to know whether to remind her.*

### Steps

| Step | Alain (organizer, app) | Marie (guest web or app) | Evidence |
|---|---|---|---|
| Create "Family trip" (60,000 goal, 5,000 share) | The card shows 0 FCFA of 60,000, 0%, 0 contributors, the end date and a copy-link button. | — | Verified (backend journey test, Home widget test) |
| Share and open the link | Copy link from the card | Sees purpose, organizer, share and deadline before any personal details | Verified (public view test). Real WhatsApp share is unverified. |
| Verify and join | Nothing changes: 0 contributors, 0 FCFA | Stays inside the same collection through verification; a valid session is reused | Verified (backend). Browser walkthrough is unverified. |
| Review | — | Credited to, organizer, method with masked number, contribution, fees (0, taken from the collection), total to approve. All from the backend quote. | Verified (quote endpoint, proxy test, Flutter checkout test) |
| Submit | Shows "5,000 FCFA awaiting confirmation". Bar unchanged, still 0 contributors, no reminder offered. | Sees "Approve on your phone", then "Confirming your payment". The page stays still; a second charge is refused. | Verified (backend journey, state tests) |
| Leave and come back | — | The same attempt is recovered (same key, same payment) | Verified (backend history, Flutter timeout recovery). Browser reload is unverified. |
| Verified success | Sees 5,000 of 60,000, 8%, 1 contributor, "Marie contributed +5,000 FCFA". "Collected this month" includes it. | Sees "Your share is paid" and can reopen the receipt | Verified (backend journey, Home widget test) |
| Duplicate checks or callbacks | Counted once | Counted once | Verified (one SUCCEEDED event, one notification) |
| Lookup error (e.g. HTTP 403) | Still pending | Still "Confirming your payment"; no second charge | Verified (backend journey) |
| Definite failure | Totals unchanged | Amount unchanged; a new attempt is allowed | Verified (backend journey) |
| Partial (2,000 of 5,000) | Member shows as Partial and can be reminded for the 3,000 left | Sees "3,000 FCFA left" | Verified (backend journey) |

### Still unverified

- A real MeSomb payment on staging.
- The browser and device walkthrough.
- WhatsApp link previews.

## 2. Request and Pay (next priority)

*The requester wants to know if they were paid. The payer wants to know their payment reached them.*

- **Implemented:** create, notify, decline, cancel and expiry. A requester must set receiving details first. A quote binds payer, recipient, amounts and fees. Execution runs separate collection and delivery legs; "PAID" only follows verified delivery.
- **Verified in the backend:** person execution tests cover duplicate dispatch, ambiguous outcomes, delivery failure kept as an obligation, and refund review.
- **Gaps:**
  - The requester's and payer's screens need the same three distinct states as collections: requested, paid by sender, delivered to recipient.
  - A two-phone walkthrough is unverified.
  - A real sandbox payout has not been demonstrated end to end.

## 3. Send and Near2Pay

- **Implemented:**
  - Send by username.
  - Near2Pay with a short-lived QR code or a typed code. A code only identifies the person or collection.
  - A personal code opens "Pay <name>" in the reviewed checkout. A collection code opens "Contribute to <collection>".
  - "Payment received" appears only after verified delivery.
- **Verified:** backend tests and Flutter widget tests.
- **Unverified:** the camera on a device. The Android build in CI could not be checked locally because of network access.

## 4. Settlement and recurring rounds

- **Implemented:**
  - Cash recorded separately from Mobile Money confirmed by MeSomb. Cash already held is never paid out.
  - A review leading with "You receive", and "Close and send" that sends exactly once.
  - "Delivered" only after MeSomb evidence.
  - Rounds, with earlier rounds kept in history.
  - Rotating beneficiaries.
- **Verified in the backend:** settlement tests, including timeout without resend, failure kept in review, rounds and beneficiaries.
- **Unverified:** a real sandbox payout. Settlement needs the Render settings described in `docs/SETTLEMENT.md`.

## 5. Reminders

- **Implemented:** reminders target accepted members with an outstanding share, with a 24-hour cooldown. They are suppressed while a payment is confirming.
- **Verified:** backend reminder tests and the partial-contribution journey.

## 6. Activity, notifications and receipts

- **Home "Recent activity":** built only from confirmed contributions (`/me/home`).
- **Notifications:** contribution confirmed (organizer), contribution receipt (payer), settlement, cash, rounds, Near2Pay received.
- **Receipts:** guest receipt with masked number; app record for each payment.
- **Unverified:** push delivery with the app closed, on a device.

## Historical defects, checked on this branch

| Observation | Current state | Evidence |
|---|---|---|
| Guest checkout reached `/test-payments/.../simulate` | The guest web no longer contains any test-payment route. The proxy only allows provider payment actions, and the simulator's money is excluded from all totals. | grep, proxy tests |
| Reconciliation logged HTTP 403 | The payment stays PENDING (`PROVIDER_LOOKUP_HTTP_403`) and recovers when a later lookup succeeds. The cause is provider-side (keys or permissions) and is still unknown. | Backend journey test. The Neon row for `2df2f4d4…` is still not supplied. |
| Guests joined but organizers saw unpaid | Fixed: every screen reads the shared `position` and `totals`, not the legacy simulator fields | Contract tests |
