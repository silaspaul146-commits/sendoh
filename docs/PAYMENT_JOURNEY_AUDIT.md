# Sendoh payment journey audit — 7 November 2026

Scope: source review of the available working copy and user-confirmed deployed MeSomb transaction. This is not a device walkthrough or proof that the installed APK matches the working copy.

## Immediate defects and this increment

- Organizer participant totals, remaining amounts, and Paid/Partial/Unpaid filters read legacy TestPayment data despite successful ProviderPayment records. Switch these existing widgets to provider sandbox fields.
- Joined summaries exposed only legacy simulation totals. Add separate provider contribution and pending fields, retain live_available=false, and use provider data for personal contribution status.
- Organizer and joined detail initially displayed navigation snapshots. Fetch fresh detail on opening; existing return-from-checkout refresh remains.
- Regression: joined and organizer amounts agree after reconciliation, pending is distinguishable, refund removes the contribution. Provider totals stay separate from live and legacy totals.
- Layout and navigation structure are preserved. Flutter must be analyzed and tested on the user's environment; no Flutter SDK exists here.

## Journey inventory

| Journey | Current implementation | Remaining work |
|---|---|---|
| Registered collection contribution | MeSomb attempt, persisted retry key, polling, provider verification, receipt | Verify on device, fee accounting, notify payer and organizer |
| Organizer collection | Overall provider total supported; participant rows used wrong source | This increment repairs rows and initial refresh; test background updates |
| Joined collection | Checkout supported; personal status used simulator-only summary | This increment repairs summary and personal status |
| Guest web contribution | Guest proxy still uses /test-payments and client-selected /simulate outcomes | Replace with provider create/detail/refresh using same identity and membership checks; preserve browser draft across reload |
| Money request | Create, send, receive, cancel, decline, expiry | Authorized recipient checkout; request-payment binding; prevent cancellation/payment races; confirmed settlement states |
| Pay / P2P | Exact username resolution and review UI; checkout is a placeholder | Recipient payout destination verification, server quote, collection leg, disbursement leg, independent reconciliation |
| Near2Pay | Existing people flow; scanner placeholder, backend rejects QR resolution | Signed/expiring QR identity resolution, real scanner, recipient confirmation; reuse Pay engine |
| Notifications | Invitation/request push exists; provider reconciliation creates only organizer Activity | Durable deduplicated notifications for payer and beneficiary, clear amount/status/name, correct deep links |
| History | Provider endpoint returns latest 100 across collections, filtered on client | Server-side purpose/collection filters and cursor pagination; durable receipt access |
| Session/authentication | Refresh-token retry and saved-session restoration exist | Device checks for timeout, app resume, expired/revoked refresh token; do not treat network failure as logout |
| Collection close/settlement | Collection states exist | Verified disbursement, fees, settlement receipt; contribution success must not imply organizer payout |

## Critical product distinction

The observed 1,000 contribution credits the MeSomb application with 980 after 20 provider fees. It does not prove 980 was disbursed to an organizer or another user. Enabling Pay by routing a collection to a recipient ID would falsely imply delivery.

Proposed payment lifecycle: created -> collecting -> collected -> disbursing -> delivered. Uncertain or failed disbursement must retain its own recoverable state and must never recollect the payer. Requests become paid according to the agreed delivery contract, not a client tap. Near2Pay identifies a recipient; it is not a different money movement system.

## Implementation sequence

1. Deploy and verify the collection read-model repair with the existing successful payment.
2. Persist gross, provider fee, net, currency, and purpose; establish one backend quote and receipt contract. Keep Sendoh revenue separate; no agreed pricing rates were available in this audit.
3. Wire guest checkout into existing collection payment lifecycle. Remove client-selected outcomes from that journey. Provide mockups for the changed checkout states before implementing visual changes.
4. Add verified payout destinations and MeSomb disbursement integration, including ambiguous-outcome recovery, duplicate protection, and reconciliation.
5. Bind request payments to the shared engine; connect Pay, then Near2Pay identity scanning.
6. Connect durable payment notifications and deep links. Verify webhook activation and signed delivery; keep polling recovery independent.
7. Device acceptance: success, failure, pending, lost network after submit, app termination, repeated taps, duplicate webhook, refund, expired request, wrong payer, and recipient payout failure.

## Release gates

- Current APK build and Render revision identified.
- No duplicate debits or duplicate contribution credit.
- All affected screens agree with server state after reopen/resume.
- No provider secret in client builds or logs.
- No “delivered” receipt without verified recipient delivery.
- Full backend and Flutter tests pass; guest production build and proxy tests pass.
- Cold starts and sleeping background workers evaluated on actual hosting.
- User approves mockups before changed layouts or new screen states are implemented.

This increment does not implement guest checkout, request payment, P2P disbursement, Near2Pay scanning, or provider push notifications.
