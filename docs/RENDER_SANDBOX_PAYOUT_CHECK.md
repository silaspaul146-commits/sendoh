# Render sandbox payout check

This backend-only increment creates a protected one-shot diagnostic, not a customer Pay endpoint. It submits one fixed 1,000 XAF MTN sandbox deposit to the official success test number 600000001. It uses the existing MeSomb keys on Render. No Flutter, guest checkout, business fee policy or customer payment status is changed.

## Guarantees and limits
- Enabled only with existing sandbox configuration, non-production environment and a new dedicated 64-character lowercase hexadecimal access token.
- One persisted probe per MeSomb application hash. The Neon reservation commits before dispatch. Concurrent/repeated create calls return that same attempt.
- Timeout, process crash, redeployment or changing the token cannot grant a repeat dispatch for that application. Do not delete the row. A crash before sending can leave an unresolved reservation; this is deliberate.
- Status refresh is GET to MeSomb, never a deposit. Database lease limits concurrent checks; subsequent checks are throttled for 10 seconds.
- Fixed destination/amount; caller cannot override them. No submission on build/startup. Routes are excluded from OpenAPI, but authentication is the actual protection.
- Output is allowlisted provider evidence. delivery_confirmed remains false: this diagnostic is not a receipt and cannot settle a customer obligation.
- A new server reference is generated. It does not replay or resolve the older desktop attempt 85db26f3-5494-475f-9168-eba1b3861877. Render previously returned zero matches for that older reference. Keep its journal.
- Existing sandbox confirmation is an operator declaration. Credentials must continue to belong to the sandbox MeSomb application; never switch that application live during this diagnostic.

## Apply
Extract the ZIP to Desktop/Sendoh_Render_Payout_Check.
From Desktop/sendoh, run git apply --check on Sendoh_Render_Payout_Check.patch. If successful, apply it.
From services/backend run python -m pytest -q.

Stage only:
services/backend/app/main.py
services/backend/app/payout_probe.py
services/backend/migrations/versions/c05f8d6e9009_sandbox_payout_probe.py
services/backend/tests/test_sandbox_payout_probe.py
services/backend/tests/test_sandbox_payout_probe_migration.py
docs/RENDER_SANDBOX_PAYOUT_CHECK.md
Commit and push main. The existing migration start command installs c05f8d6e9009.

## Render configuration
KEEP Build Command: pip install -r requirements.lock
KEEP Start Command: python -m alembic upgrade head && python -m uvicorn app.main:app --host 0.0.0.0 --port $PORT
Do not place a diagnostic command in either field.

Generate a separate temporary diagnostic token locally:
python -c "import secrets; print(secrets.token_hex(32))"
Add its value on Render under Environment:
SENDOH_SANDBOX_DIAGNOSTIC_TOKEN
Save/redeploy. Do not paste the token into chat or commit it. This token protects only this diagnostic; do not reuse MeSomb credentials as its value.

## Run
From the extracted directory:
python .\run_check.py
Enter the diagnostic token at the hidden prompt. The script calls Render, not MeSomb directly, and prints the saved attempt and lookup result.
If pending/empty, wait at least 10 seconds and use:
python .\run_check.py --status-only
Never delete a reservation to trigger another payout.
Send the JSON output to the engineer, without the token. No signed provider request, API credentials or headers are printed.
After recording the result, remove SENDOH_SANDBOX_DIAGNOSTIC_TOKEN on Render and redeploy to disable the endpoint. Evidence remains in Neon.

## Validation
Tests cover authorization, disabled/live configuration, caller override rejection, commit-before-dispatch, concurrent and repeated creates, interrupted dispatch, bounded evidence, read-only refresh throttling, migration upgrade/downgrade and evidence preservation. SQLite/mocked-provider tests do not prove an actual sandbox payout or PostgreSQL race behavior. External execution remains the next verification step.
