# Guest provider checkout — approved journey, first integration increment

## Included
- Guest collection checkout uses provider payment create, detail, refresh and history.
- Client-selected simulator outcomes are removed from the guest proxy.
- Amount, operator and payer phone are reviewed together; the browser persists the idempotency envelope before dispatch.
- Recovery is scoped to authenticated user and collection in sessionStorage. Reload retains the envelope; closing the tab may remove it, but pending provider records remain discoverable from backend history.
- Backend history supports collection filtering, payer-only access and stable cursor pagination.
- Visible checkout polls pending status every five seconds; server reconciliation still respects its retry schedule.
- The collection page displays confirmed provider sandbox totals separately from live totals.
- Network errors do not automatically route a saved guest session into authentication.
- Current layout, brand tokens and identity/membership flow are retained.

## Fee contract
Current collection submission uses fees_included=True. Payer total equals the contribution; provider fees reduce collection proceeds. No unverified tariff or invented zero-fee quote is displayed. Exact provider fee/net persistence and server-issued quotes are NOT implemented by this increment.

## Tests
TypeScript check, Next production build, guest proxy contract tests, and targeted backend history/lifecycle tests pass. Browser/device walkthrough is outstanding because Chromium could not launch under the workspace process restrictions. No real external transaction was initiated by automated tests.

## Deployment
Requires backend and guest web deployment. No migration, new environment variable, Flutter change or APK build.
Apply with git apply --check first. Never force an incompatible patch.

## Acceptance on staging
1. Open an active collection link in a private browser; verify the guest phone using the currently configured OTP delivery.
2. Join as that identity. Choose MTN and the documented sandbox success number 600000001.
3. Review contribution and submit once.
4. Verify status becomes confirmed; return to collection and verify the gross contribution appears exactly once.
5. Reload during pending: recover the attempt without a new collection request.
6. Inspect receipt/history and use another authenticated guest to confirm histories remain private.
7. Check 360px, 390px and tablet widths, keyboard focus, long collection names and enlarged text.
8. Existing OTP_PROVIDER=log still requires the staging administrator's code; real SMS is not enabled by this patch.

## Remaining approved increments
- Persist gross, provider fees and net; establish quote/receipt contracts.
- Verify MeSomb sandbox deposit capability and recipient destination ownership.
- Implement separately reconciled collection and disbursement legs with ambiguity recovery.
- Bind money-request settlement to recipient delivery.
- Connect Pay and contextual Near2Pay QR/short-code sessions to that engine.
- Durable payer/beneficiary push notifications and webhook delivery recovery.

Do not show recipient-delivery success based only on collection success. Requests, Pay, Near2Pay and recipient payouts remain unchanged in this package.
