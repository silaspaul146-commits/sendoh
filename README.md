# Sendoh foundation

M0 and the collection-creation portion of M1. This is a development source project, not a production application or an APK.

## Implemented

- Flutter organizer source: development connection, Home / Activity / Profile, three-step creation form, optional target and deadline, contribution modes, initial participants, review, API submission, collection detail and copy link.
- FastAPI: private collection list/detail, atomic creation/publication with initial participants, caller-scoped idempotency, public-safe collection view, activity, profile and health.
- SQLAlchemy models, a frozen Alembic foundation migration, PostgreSQL development configuration, OpenAPI export.
- Next.js public collection landing page with unavailable and not-found states.
- Automated backend tests and CI definitions for PostgreSQL, guest web and Flutter.

## Explicitly not implemented

OTP/SMS authentication, production sessions, token rotation/revocation, participant management after creation, configuration editing, payment collection, participant claiming, fee quotes, Requests, P2P Pay, closing, cash registration, reconciliation, settlement, offline sync, push notifications and production deployment.

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

The seed command creates one local identity and prints its random bearer credential once. Paste it into the Flutter development connection screen. It is hashed in the database and held in app memory. It is NOT an OTP session and has no production verification claim. Do not commit or share it. Startup requires `SENDOH_ENV=development` and intentionally fails without it.

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

For a physical phone, configure `PUBLIC_WEB_URL` with a reachable development host, not localhost. Only use this build on a trusted development network. No public deployment is included.

## 3. Flutter organizer

Install a stable Flutter SDK with Dart >=3.4, then run from the repository root:

```bash
./scripts/bootstrap_flutter.sh
cd apps/organizer_flutter
flutter run --dart-define=API_URL=http://10.0.2.2:8000
```

The bootstrap script generates Android/iOS platform boilerplate, preserves the authored Dart files, resolves dependencies, runs analysis and the widget test. Generated package identifiers are placeholders; choose the production application identifier before distribution.

- Android emulator: use `http://10.0.2.2:8000`.
- iOS simulator: use `http://127.0.0.1:8000`; local HTTP may require a development-only transport exception. Production requires HTTPS.
- Physical device: use the computer's reachable development host.

The Android debug manifest permits local HTTP; no release HTTP exception is supplied. The development token is entered interactively, never compiled into the application.

Flutter source and platform build were NOT executed in the authoring environment because Flutter/Dart were unavailable. Run the bootstrap checks before relying on the app. Native sharing currently consists of copy-link, not a WhatsApp integration.

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

Read `docs/IMPLEMENTATION_STATUS.md` for exact verification evidence and `docs/DECISIONS.md` for adopted defaults and unresolved choices. The current collection API returns all organizer collections without pagination, intended for local validation only. There are no rate limits or real authentication flows yet.

Reference documentation used for implementation:
- https://docs.flutter.dev/reference/flutter-cli
- https://docs.sqlalchemy.org/en/20/orm/session_transaction.html
