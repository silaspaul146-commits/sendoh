# Guest identity, invitation navigation and prompt push delivery

Based on GitHub main commit 5102998. Includes the existing default-on push behaviour.
Payments remain disabled. No new provider or credit card is required.

## What changes

- New successful API mutations wake the push queue immediately. Durable jobs are
  committed with notifications and retried on provider errors. The inbox remains
  available even if a push is delayed or denied. Historical backfills do not create
  a burst of old alerts; already-read or superseded invitations are not pushed.
- OS permission and explicit opt-outs still apply. No system can guarantee the
  device receives a push before the inbox becomes visible. Render must be awake.
- Push taps retain the notification ID and open the specific authenticated
  invitation preview. Organizers still open collection details for join/decline.
- After sending an invitation, the organizer can copy its personal web link.
  The UUID/version in the link is only a locator, never authentication.
- Guests verify their own phone before private invitation details are returned.
  Wrong accounts receive no invitation data. Old link versions cannot accept a
  newly issued invitation. Guests can join without an app or username; a verified
  identity is retained, and a full Sendoh profile can be completed later.
- Public collection contribution previews also verify identity. They use only the
  current person's participant expectation. A pending personal invitation is linked.
  Manual-name rows are not automatically claimed. No roster is exposed publicly.
- Contribution preview currently supports SELF attribution only. Paying on behalf
  of another person, payment intents, reconciliation and actual money movement are
  NOT implemented in this patch. No contribution or paid status is recorded.
- The guest proxy uses an HttpOnly, SameSite=Strict cookie, Secure over HTTPS;
  access/refresh tokens are not returned to browser JavaScript. The browser session
  expires after the backend access-token lifetime; it does not refresh silently.
- Launcher generator replaces legacy Flutter PNGs as well as the new launcher
  resources and sets the label to Sendoh. CI checks the finished APK's label and
  merged icon resource before uploading. Toolchain versions are unchanged.

## OTP during testing

The existing OTP provider is reused. With staging-log, the page says to obtain the
code from the test administrator. This is not SMS delivery, and the guest flow is
not ready for unattended public onboarding until a real verification provider is
configured. Push OTP is not used to claim an unverified phone number.

## Apply (PowerShell, from the extracted Sendoh_Guest_Identity_Update folder)

    python .\Sendoh_Guest_Identity_Update.py --project C:\Users\IHIMBRU\Desktop\sendoh --check
    python .\Sendoh_Guest_Identity_Update.py --project C:\Users\IHIMBRU\Desktop\sendoh --apply

If a conflict is reported, use --export proposed-update and review it. Do not force
custom edits away. The updater backs up replaced files before writing any changes.

## Verify and push

    cd C:\Users\IHIMBRU\Desktop\sendoh\services\backend
    $env:SENDOH_ENV="development"
    .\.venv\Scripts\python.exe -m pytest -q

    cd C:\Users\IHIMBRU\Desktop\sendoh\apps\guest_web
    npm ci
    npm run build
    npm run typecheck
    node --test scripts/test-guest-proxy.cjs

    cd C:\Users\IHIMBRU\Desktop\sendoh\apps\organizer_flutter
    flutter analyze
    flutter test

Use Flutter 3.35.7, matching CI. Then:

    cd C:\Users\IHIMBRU\Desktop\sendoh
    Get-Content .\sendoh-guest-identity-paths.txt | ForEach-Object { git add -- $_ }
    git diff --cached --stat
    git commit -m "Verify guest identity and open specific invitations from push"
    git push

## Deployment order

1. Wait for Render to deploy the commit; /health should show version 0.5.0.
2. Wait for Vercel's deployment. API_INTERNAL_URL remains https://sendoh.onrender.com.
3. Wait for GitHub Actions tests, APK build and branding check to succeed.
4. Install the APK from THIS run. No schema migration or new secret is required.
   Generated icon resources are produced by configure_mobile.py during CI.

If the installed icon is still stale, confirm you installed the latest artifact
and inspect Android App info. Do not uninstall merely to clear an icon cache:
that removes the locally saved session and requires phone verification again.

## Acceptance tests

- Two registered accounts: invite, receive push, tap, see that invitation, accept.
- New guest: invite by phone, copy link, open browser, verify that phone, enter name,
  join. Organizer should see Joined and a verified identity. No payment recorded.
- Forward that link to a different verified phone: it must not reveal/claim the
  invitation. Switch phone using the guest page's sign-out control.
- Cancel and resend: old versioned link must fail; new link must work.
- Open a public collection, verify own phone, check the personal expected amount
  and link to a pending invitation. Other participants must not appear.
- Turn push off, reopen: opt-out remains off; inbox remains available.
- Confirm Sendoh label/logo on the latest APK; background and cold-start push taps.

## Validation and limits

Backend suite passed: 83 tests, three PostgreSQL-only skips. Guest production build, TypeScript, proxy boundary/cookie tests, native
icon generator tests and Dart syntax checks passed. No Flutter SDK is available
in the authoring environment: analyzer/widget tests/full APK check require CI.
An attempted local browser-to-backend smoke run was blocked by the environment's
network-interface restriction; full browser/device acceptance is not claimed.
Reference colours and existing components were reused. Pixel-exact comparison of
all screens has not been completed.

Next: explicit on-behalf attribution and its consent/record model, then requests
and P2P, Near2P QR and opt-in proximity. Real payment integration remains last.
