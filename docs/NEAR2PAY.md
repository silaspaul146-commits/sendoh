# Near2Pay

Find the right person in person, without typing a phone number. Then pay or request as usual.

## How it works

1. **The person being paid** opens "Get paid nearby". It shows a QR code and a 6-character code (e.g. `K7M-4QX`), optionally with an amount.
2. **The payer** scans the QR code, or types the code.
3. **The payer confirms the person** ("Is this the right person?"), then continues to the normal Pay checkout: quote, fees, approval and verified delivery. They can also choose Request instead.

A code only identifies someone. It never authorizes or starts a payment.

## Safety

- Codes expire after 2 minutes. Showing a new code retires the previous one.
- Only hashes of codes are stored.
- Short codes avoid 0, O, 1, I and L.
- Ten failed lookups in 10 minutes block that payer for a while, so codes can't be guessed.
- Your own code is refused.

## API

- `POST /api/v1/near/codes` with `{amount?}` returns `{qr, short_code, amount, expires_at, lifetime}`.
- `POST /api/v1/near/resolve` with `{code}` (the QR text or the short code) returns `{person, amount, expires_at}`.

Migration `e4b8a6cd0017` adds `near_codes` and `near_attempts`.

## Status

- **Backend:** built and tested.
- **App screens:** wait for mockup approval (canvas "Sendoh Near2Pay"). The scanner needs a camera package (`mobile_scanner`) and the Android camera permission.
