# Sendoh foundation

## Hosted staging

The repository includes Render, Neon, Vercel, and Android build configuration.
Follow [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md) for the exact setup order.

M0 and the collection-creation portion of M1. This is a staging-ready source
project; real-money payments remain disabled.

## Implemented

- Flutter organizer source: brand-matched phone onboarding, six-box verification, Home / Activity / Profile, three-step creation form, optional target and deadline, contribution modes, initial participants, review, API submission, collection detail and copy link.
- FastAPI: private collection list/detail, atomic creation/publication with initial participants, caller-scoped idempotency, public-safe collection view, activity, profile and health.
- SQLAlchemy models, Alembic migrations, local SQLite and hosted Neon PostgreSQL configuration, OpenAPI export.
- Next.js public experience: branded Sendoh marketing homepage for WhatsApp sharing, social preview metadata, and a focused guest collection journey covering identity, amount, review, provider choice, explicit payment-unavailable stop, and unavailable/not-found states.
- Render Blueprint, Vercel configuration, centralized Flutter API endpoint, Infobip-ready OTP delivery, and an automated Android APK artifact.
- Automated backend tests and CI definitions for PostgreSQL, guest web and Flutter.

## Explicitly not implemented

Configured production SMS credentials, participant management after creation,
configuration editing, payment authorization, payment collection, participant
claiming, fee quotes, Requests, P2P Pay, closing, cash registration,
reconciliation, settlement, offline sync, push notifications and production
hardening.

Requests and Pay remain IN the first-release roadmap; their absence here reflects milestone order, not a scope cut. No financial success is simulated. The public page does not offer a payment button.

## 1. Backend

Use Python 3.12. From `services/backend`:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.lock
export SENDOH_ENV=development
export DATABASE_URL=sqlite:///./sendoh.db
export PUBLIC_WEB_URL=http://localhost:3000
alembic upgrade head
python -m app.seed
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

The seed command creates one local identity and prints its random bearer credential once. Paste it into the Flutter development connection screen. It is hashed in the database and held in app memory. It is NOT an OTP session and has no production verification claim. Do not commit or share it. Hosted staging uses the guarded configuration described in `docs/DEPLOYMENT.md`.

For PostgreSQL, start `docker compose up -d postgres` from the repository root and use:

```bash
export DATABASE_URL=postgresql+psycopg://sendoh:sendoh@localhost:5432/sendoh
alembic upgrade head
```

The Compose password is local-only and its port is bound to loopback. Never run tests against a database containing valuable data: the integration fixture creates and drops the application tables.

Interactive API documentation is at `/docs`. The exported contract is `contracts/openapi/sendoh.json`.

## 2. Guest web

From `apps/guest_web`:

```bash
npm ci
npm run dev
```

The server fetches from `http://127.0.0.1:8000`; set `API_INTERNAL_URL` to override it. This is a server-side request, so no broad browser CORS exception is required. Open the link copied from the organizer app.

The root page explains Sendoh for public and WhatsApp visitors. Collection URLs
under `/c/[token]` bypass the marketing story and open the contribution flow
directly.

For a physical phone in local development, configure `PUBLIC_WEB_URL` with a reachable development host, not localhost. For hosted staging, use the HTTPS Vercel URL.

## 3. Flutter organizer

Install a stable Flutter SDK with Dart >=3.4, then run from the repository root:

```bash
./scripts/bootstrap_flutter.sh
cd apps/organizer_flutter
flutter run --dart-define=API_URL=http://10.0.2.2:8000
```

The bootstrap script generates Android/iOS platform boilerplate, preserves the authored Dart files and assets, resolves dependencies, runs analysis and the widget tests. Generated package identifiers are placeholders; choose the production application identifier before distribution.

- Android emulator: use `http://10.0.2.2:8000`.
- iOS simulator: use `http://127.0.0.1:8000`; local HTTP may require a development-only transport exception. Production requires HTTPS.
- Physical device: use the computer's reachable development host.

The Android debug manifest permits local HTTP; no release HTTP exception is supplied. Release builds use the HTTPS endpoint in `lib/config.dart`; debug builds can still override it with `--dart-define=API_URL=...`.

Local-only API settings, development-token entry, and local OTP instructions
are guarded by Flutter debug mode and do not appear in the release APK.

Flutter 3.24.5 analysis and Chrome-hosted widget tests passed in the authoring environment. The Linux `flutter_tester` binary is incompatible with that managed container, so the same tests were run on Flutter's Chrome platform. Run the bootstrap checks on the development computer before distributing a native build. Native sharing currently consists of copy-link, not a WhatsApp integration.

## Test commands

```bash
cd services/backend
SENDOH_ENV=development python -m pytest -q
alembic check
```

Set `TEST_DATABASE_URL` to a disposable PostgreSQL database to exercise the concurrent idempotency test. SQLite validation does not prove PostgreSQL concurrency behavior.

```bash
cd apps/guest_web
npm run build
npm run typecheck
```

## Decisions and limits

Read `docs/IMPLEMENTATION_STATUS.md` for exact verification evidence and `docs/DECISIONS.md` for adopted defaults and unresolved choices. The current collection API returns all organizer collections without pagination. OTP authentication is implemented, but rate limiting still requires production hardening.

Reference documentation used for implementation:
- https://docs.flutter.dev/reference/flutter-cli
- https://docs.sqlalchemy.org/en/20/orm/session_transaction.html
