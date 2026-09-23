# Implementation status

## Delivered

M0 source foundation, development phone onboarding and the collection-creation/public-contribution experience. This is not production payment or production authentication completion.

Backend operations include development auth/profile/session endpoints plus health, organizer collection creation/list/detail, public collection detail and activity. See the generated OpenAPI file for the exact implemented contract.

The collection creation service commits collection, participants, activity and idempotency result together. A unique actor/key constraint serializes PostgreSQL retries; mismatched payloads conflict. Private reads scope queries by organizer. Input validation forbids caller-supplied organizer identity and non-integer money.

Development dependency versions are pinned in requirements.lock, package-lock.json and pubspec.lock.

## Verification

Backend SQLite suite: 23 passed. One PostgreSQL concurrency test skipped locally because PostgreSQL is unavailable; CI is configured to run it with PostgreSQL 16.

Alembic upgrade applied successfully to an empty SQLite database. Alembic metadata check found no model drift. PostgreSQL runtime migration remains a CI check, not a locally claimed result.

Flutter 3.24.5 analysis: no issues. Two widget tests passed on Flutter's Chrome platform. The managed Linux container's native `flutter_tester` executable segfaulted before loading tests; this was an engine/runtime incompatibility, not a test assertion. No APK was packaged.

Guest web: TypeScript check and optimized Next.js production build passed. Browser QA passed at 320, 390 and 1280 pixels across collection, identity, amount, review, provider and payment-unavailable screens. It verified invalid-phone handling, confirmation gating, private-roster absence, no horizontal overflow, all state fixtures, zero page errors and zero write/payment requests.

## Next increment

Run the native Flutter checks on the development computer and inspect the organizer flow on a physical target. Replace development authentication with the selected real OTP/session implementation. Add participant management and resource-versioned edits. Integrate provider quote, authorization, verification and receipt endpoints before enabling payment controls; keep Requests and Pay in the release backlog.

PostgreSQL migration SQL generated successfully in offline mode; this is compilation, not execution against PostgreSQL. The local test runner emitted two upstream deprecation warnings without test failures.

## Development phone onboarding increment

Added development-only phone challenge/verification, profile name creation,
expiring sessions and sign-out; Flutter onboarding follows the auth board.
See ONBOARDING_UPDATE.md for setup, fidelity limitations and test status.
Legacy accounts and collection links are preserved. SMS, profile photos and
persistent mobile sessions remain pending. Guest payment screens stop before any
authorization and explicitly state that no request or charge occurred.
