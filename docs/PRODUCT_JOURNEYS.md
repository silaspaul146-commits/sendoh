# Sendoh product journeys

The promise: when two people open Sendoh, each can tell what happened to the same payment and whether they need to do anything next. Nobody should have to send a screenshot to prove they paid.

**Status labels**
- **Verified:** an automated end-to-end test covers it in this repository.
- **Implemented:** the code exists but has no end-to-end test.
- **Unverified:** needs staging, a device or provider access.
- **Not built:** missing.

No automated test proves MeSomb moved real money. Every payment test uses a fake provider.

Last updated: 24 Nov 2026 (milestones "one contribution, two phones", "Request and Pay" and "Send and Near2Pay").

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

## 2. Request and Pay (milestone 2)

*Marie wants to know her payment reached Alain and that she can't pay twice. Alain wants to know whether the money has actually arrived.*

### Steps

| Step | Alain (requester) | Marie (payer) | Evidence |
|---|---|---|---|
| Request | Home → Request: Marie, 5,000, "Saturday dinner". He must have set his receiving details first. | Sees "Alain asked you for 5,000 FCFA, for Saturday dinner", with Review payment or Decline | Verified (backend journey; receiving-gate widget test) |
| Review | — | "Alain receives on MTN MoMo ••• 123", her method, fees and total, all from the server quote. The destination is Alain's own consented one. | Verified (backend quote; checkout widget test) |
| Approve | "Marie is paying" | "Approve on your phone", then "Confirming your payment" | Verified (backend phase) |
| Collected, not yet delivered | "Marie paid · on its way to you". No "received", no notification, no receipt. | "Paid · delivering to Alain. Please don't pay again." | Verified (backend journey; widget and headline tests) |
| Leave and reopen | — | Reopens the same order. A repeat approval returns the same payment, and a second quote for the request is refused. | Verified (backend journey; checkout recovery tests) |
| Delivery verified | "Paid · you received 5,000 FCFA". "You received" notification; can reopen the receipt. | "Paid · delivered to Alain". Can reopen the receipt. | Verified (backend journey; widget test) |
| Delivery fails | "Delivery needs attention" | "Your payment was collected and is held safely". No second charge. | Verified (backend journey) |
| Declined | "Marie declined", plus a notification | "You declined this request". Payment is no longer possible. | Verified (backend journey; headline test) |

### Still unverified

- A real sandbox payout end to end.
- A two-phone device walkthrough.
- Settlement payouts and Request/Pay need the Render settings in `docs/SETTLEMENT.md`.

## 3. Send and Near2Pay (milestone 3)

*Marie wants to be sure she's paying the right person, once. Alain wants to know when 2,500 FCFA is actually his.*

### Steps

| Step | Marie (payer) | Alain (recipient) | Evidence |
|---|---|---|---|
| Entry | Home → Send → "Send to a Sendoh user", or "Pay someone nearby" | Scanner → "Show my code" | Verified (widget tests) |
| Find | A handle, a scanned QR code or a typed short code all lead to the same preview: name, @handle, "Check this is the person you mean", and a way to back out | Shows a QR code and a short code that refreshes every 2 minutes | Verified (backend: same person from all three; widget tests) |
| Identify only | Scanning or typing creates no order and moves no money. An expired code asks for a new one. | — | Verified (backend journey) |
| No receiving details | "Alain hasn't set where they receive money yet. Nothing has been charged." Offers "Let Alain know"; no pay button. | Gets "Marie wants to pay you. Set where you receive money", once per day, which opens Receiving details | Verified (backend journey; widget tests) |
| Review once | Amount, "Alain receives on MTN MoMo ••• 238", her method, the quoted fee and the total | — | Verified (backend quote; checkout tests) |
| Approve, then interruption | Approve on your phone → Confirming → "Paid · delivering to Alain". Reopening resumes the same order; a duplicate tap or callback does nothing new. | Nothing until the payment starts; then "Marie sent you 2,500 FCFA · On its way to you" | Verified (backend journey) |
| Delivered | "Delivered" in Activity, with a receipt | "Received" in Activity, with a receipt; one "You received" notification | Verified (backend journey; Activity line tests) |

Person-to-person screens use teal only. Orange stays with collection progress.

### Still unverified

- The camera on a device, including the "Camera access is off" message, which shows when permission is denied.
- A two-device scan.
- A real sandbox payout.

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
