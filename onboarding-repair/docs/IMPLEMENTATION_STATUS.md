# Implementation status

## Delivered

M0 source foundation and partial M1 collection creation. This is not completion of the full M1 authentication milestone.

Backend operations: GET health, GET me, POST collections, GET collections, GET private collection, GET public collection, GET activity. See the generated OpenAPI file for the exact implemented contract.

The collection creation service commits collection, participants, activity and idempotency result together. A unique actor/key constraint serializes PostgreSQL retries; mismatched payloads conflict. Private reads scope queries by organizer. Input validation forbids caller-supplied organizer identity and non-integer money.

Development dependency versions are pinned in requirements.lock and the guest package-lock.json. Flutter dependency resolution must occur where Flutter is available.

## Verification

Backend SQLite suite: 14 passed. One PostgreSQL concurrency test skipped locally because PostgreSQL is unavailable; CI is configured to run it with PostgreSQL 16.

Alembic upgrade applied successfully to an empty SQLite database. Alembic metadata check found no model drift. PostgreSQL runtime migration remains a CI check, not a locally claimed result.

Flutter and Dart are not installed in the authoring environment. Flutter source has not been compiled, analyzed, visually inspected in an emulator or packaged as an APK. A bootstrap script and initial widget test are provided for that next verification step.

Guest web verification results are recorded at packaging time below.

## Next increment

Run Flutter checks with the SDK and fix any platform issues. Replace development authentication with the selected real OTP/session implementation. Add participant management and resource-versioned edits. Then implement the guest identity and provider payment slice; keep Requests and Pay in the release backlog.

Guest web: Next.js production build passed; TypeScript check passed. A live API-to-Next.js integration check created a collection, rendered its public page and organizer name, verified the private participant name was absent, and rendered the invalid-link state.

PostgreSQL migration SQL generated successfully in offline mode; this is compilation, not execution against PostgreSQL. The local test runner emitted two upstream deprecation warnings without test failures.

## Development phone onboarding increment

Added development-only phone challenge/verification, profile name creation,
expiring sessions and sign-out; Flutter onboarding follows the auth board.
See ONBOARDING_UPDATE.md for setup, fidelity limitations and test status.
Legacy accounts and collection links are preserved. SMS, profile photos and
persistent mobile sessions remain pending. No payment capability was added.
