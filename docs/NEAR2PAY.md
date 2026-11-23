# Near2Pay

Two people standing together can pay or contribute without exchanging phone numbers. Near2Pay reuses the existing checkouts, fees, payment status and receipts.

## Receive: "Get paid nearby"

- **Who can show a code.** Anyone can show a personal code: Near2Pay on Home, then "Get paid nearby". An organizer can show a code for an open collection, using "Nearby" on the collection page.
- **What the screen shows.** A large QR code and a short code such as `K7M-4QX`, which the payer can type if their camera is unavailable. The code refreshes on its own every 2 minutes.
- **Amount.** The receiver can set an amount ("Requested amount · Edit") or leave it for the payer to enter.
- **Receiving details.** A personal code requires receiving details first, since only the receiver can say where money goes.
- **"Payment received".** It appears only after the payout is verified, i.e. after the `PERSON_RECEIVED` notification. A collection code shows "Contribution received" only after MeSomb confirms the contribution.

## Pay: scan or type

- **Scanning.** Daniel scans with the camera, or taps "Enter code instead". Scanning only resolves the code: no order, quote or charge is created.
- **Personal code.** It opens the existing Pay checkout titled "Pay Aïcha Ngono": recipient, amount, fees and total, then "Pay …". "Wrong person? Scan again" returns to the scanner. With no amount on the code, Daniel enters one first.
- **Collection code.** It opens "Contribute to Family Support · Organized by Aïcha". A non-member taps "Join and contribute"; joining is explicit and never pays. Then the existing contribution checkout credits Daniel's own share.
- **No silent switching.** A collection code never opens a personal payment, and a personal code never opens a contribution.
- **Problems are explained.** An expired code says "Nothing was paid". Camera off falls back to typing. After too many tries, the payer is told to wait or use a username.

## Trustworthy outcome

- **Status updates in place.** Both checkouts poll quietly, so the page isn't reloaded.
- **Reopening resumes the same payment.** Both checkouts save their request key before submitting; nothing is sent twice.
- **Collections.** The member's status and the orange progress bar change once, when the contribution is confirmed. Pending money is shown separately and never counts as progress.

## Safety

- Codes expire after 2 minutes, and showing a new one retires the previous one.
- Only hashes of codes are stored.
- Short codes avoid 0, O, 1, I and L.
- After 10 failed lookups in 10 minutes, that payer is blocked from trying more codes for a while.
- Your own code is refused, and a closed collection's code stops working.

## API

- `POST /api/v1/near/codes` with `{amount?, collection_id?}` returns `{qr, short_code, purpose, collection_id, amount, expires_at, lifetime, created_at}`.
- `POST /api/v1/near/resolve` with `{code}` returns one of:
  - `{purpose:"PERSON", person, amount}`
  - `{purpose:"COLLECTION", collection:{id,name,token,expected_amount}, organizer, membership, amount}`

Migrations `e4b8a6cd0017` and `f6c1b9de0018`.

## App

- **Packages:** `qr_flutter` 4.1.0 and `mobile_scanner` 6.0.2.
- **Permissions:** Android `CAMERA` permission, and the iOS `NSCameraUsageDescription` string.
