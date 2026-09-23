# UI fidelity update

## What changed

- Applied the accepted Sendoh palette and spacing system consistently across the Flutter organizer and Next.js guest journey.
- Rebuilt onboarding around the clean three-person illustration, Sendoh mark and six-box verification entry.
- Reworked organizer Home, Activity and Profile, three-step collection creation, creation success/share, collection Overview/Contributions, filters and participant detail.
- Built the guest golden path: collection → identity → amount → review → payment method → explicit unavailable stop.
- Kept contribution, provider cost and Sendoh fee separate. No guessed fee or total is shown.
- Kept the participant roster private on public collection pages.
- Added gated sample-only fixtures for processing, pending, unknown, successful, failed and receipt states. They are unavailable unless `SENDOH_DESIGN_PREVIEW=1`.

## Safety boundary

Payments are still disabled. The guest journey makes no write request and cannot display a real success or receipt. Provider authorization, callback verification, reconciliation and a trusted fee quote must exist before the final action can be enabled.

## Verification record

- Backend: 23 passed, 1 PostgreSQL-only concurrency test skipped under SQLite.
- Guest web: TypeScript check and optimized production build passed.
- Browser QA: 320/390/1280-pixel layouts, full guest flow, validation, confirmation reset/gate, Orange/MTN selection, private-roster absence, no overflow, zero page errors, and zero write requests.
- Flutter: analysis passed with no issues; 2 widget tests passed on the Chrome platform.
- Native Flutter tests still need to run on the development computer because the managed container's Linux `flutter_tester` executable crashed before loading tests.

## Design review fixtures

To inspect non-production states locally:

```bash
cd apps/guest_web
SENDOH_DESIGN_PREVIEW=1 npm run dev
```

Open `/design-preview`. Never set this flag in production.
