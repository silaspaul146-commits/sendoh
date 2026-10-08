# Sendoh UI and cloud update

This update connects the existing Sendoh product flows to one consistent visual
system and separates hosted staging from local-development helpers.

## What changed

- `/` on the guest web is now a public Sendoh story page suitable for a shared
  WhatsApp link. It explains the problem, the collection flow, and Sendoh's
  trust principles using the approved teal, warm neutral, orange, and status
  colours.
- `/c/<token>` remains the focused guest contribution experience. Marketing
  content does not interrupt a contributor who opens a collection link.
- Guest pages share a small Sendoh header and footer, and retain the supplied
  screen hierarchy, spacing, cards, labels, summaries, and payment states.
- The organizer app now shows the intended Collect, Request, and Pay hierarchy.
  Collections remains the active priority; Request and Pay are clearly marked
  as later features.
- Release APKs use `https://sendoh.onrender.com` by default. Local IP addresses
  are only supplied explicitly with `--dart-define` during local development.
- Development-token and local OTP controls are compiled into debug builds only.
- The backend root now identifies the API and points to `/health` and `/docs`
  instead of returning an unexplained 404.

## OTP: local versus hosted staging

For an OTP challenge created by a locally running backend, run this from the
repository root in PowerShell:

```powershell
.\scripts\get_dev_otp.ps1 -ChallengeId "YOUR-CHALLENGE-ID"
```

The helper sets `SENDOH_ENV=development`, selects
`services\backend\.venv\Scripts\python.exe`, and runs in the correct folder.

For a challenge created by the APK against `https://sendoh.onrender.com`, do
not query local SQLite. Open the Render service logs and search for
`SENDOH_STAGING_OTP`; the matching log line contains the staging code. This is
temporary until a real SMS provider is connected.

## Production boundaries

- No `.env` file, credential, database, Android/iOS generated project, or
  signing key is included in the update.
- Staging OTP logging stays behind `OTP_PROVIDER=log` and
  `ALLOW_STAGING_LOG_OTP=1` on Render. It must be disabled when real SMS is
  enabled.
- Payment remains unavailable until CamPay initiation, callback validation,
  idempotency, and provider-confirmed success are implemented and tested.
- A contribution must never be shown as successful merely because initiation
  returned successfully.

## Hosted values

Render:

```text
PUBLIC_WEB_URL=https://sendoh.vercel.app
CORS_ORIGINS=https://sendoh.vercel.app
ALLOWED_HOSTS=sendoh.onrender.com
```

Vercel:

```text
API_INTERNAL_URL=https://sendoh.onrender.com
NEXT_PUBLIC_SITE_URL=https://sendoh.vercel.app
```

GitHub Actions repository variable:

```text
SENDOH_STAGING_API_URL=https://sendoh.onrender.com
```

