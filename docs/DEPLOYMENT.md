# Sendoh staging deployment

This repository is prepared for the following staging topology:

- Flutter Android/iOS client -> Render FastAPI service
- Vercel Next.js guest web -> Render FastAPI service
- Render FastAPI service -> Neon PostgreSQL

Current hosted staging endpoints:

- Backend: `https://sendoh.onrender.com`
- Guest web and public Sendoh page: `https://sendoh.vercel.app`

If either hostname changes, update `SendohConfig.apiBaseUrl`, Vercel's
`API_INTERNAL_URL`, Render's public URL variables, and the GitHub
`SENDOH_STAGING_API_URL` variable.

## 1. Put the repository on GitHub

Use a private repository. Never commit `.env`, provider credentials, APK signing
keys, Neon passwords, Infobip keys, or future CamPay credentials.

## 2. Create Neon PostgreSQL

Create a staging project and copy its pooled connection string. Keep the
`sslmode=require` and `channel_binding=require` query parameters. The backend
automatically selects the installed psycopg v3 SQLAlchemy driver.

## 3. Deploy the backend on Render

Create a Blueprint from the repository's `render.yaml`. Set the prompted values:

| Variable | Staging value |
| --- | --- |
| `DATABASE_URL` | Neon pooled connection string |
| `PUBLIC_WEB_URL` | `https://sendoh.vercel.app` |
| `CORS_ORIGINS` | `https://sendoh.vercel.app` |
| `ALLOWED_HOSTS` | `sendoh.onrender.com` |

The pre-deploy command applies Alembic migrations before the new service starts.
Confirm that `https://<render-host>/health` returns `status: ok`.

Staging initially uses `OTP_PROVIDER=log`. Request a code in the app, then find
the single `SENDOH_STAGING_OTP` entry in the Render service logs. This is only a
temporary bridge while Infobip is being validated. Production startup refuses
this mode.

## 4. Deploy the guest web app on Vercel

Import the same GitHub repository and set **Root Directory** to
`apps/guest_web`. Add this environment variable to Preview and Production:

```text
API_INTERNAL_URL=https://sendoh.onrender.com
NEXT_PUBLIC_SITE_URL=https://sendoh.vercel.app
```

Leave `SENDOH_DESIGN_PREVIEW` unset. Redeploy after changing environment
variables. Then update `PUBLIC_WEB_URL` and `CORS_ORIGINS` on Render with the
actual Vercel URL.

## 5. Build the Android APK

The API endpoint is centralized in `apps/organizer_flutter/lib/config.dart`.
The GitHub Actions workflow builds and uploads `sendoh-android-staging` after
every successful push. Download `app-release.apk` from the workflow's Artifacts
section.

To build on Windows instead:

```powershell
cd C:\Users\IHIMBRU\Desktop\sendoh
.\scripts\build_android.ps1 -ApiUrl "https://sendoh.onrender.com"
```

The output is:

```text
apps\organizer_flutter\build\app\outputs\flutter-apk\app-release.apk
```

The generated Flutter project retains both Android and iOS platform support.
An installable iOS build requires macOS, Xcode, and an Apple signing identity.

## Local OTP versus hosted staging OTP

A local challenge and a Render challenge are stored in different places.

For a challenge requested from a locally running backend, use this from the
repository root:

```powershell
.\scripts\get_dev_otp.ps1 -ChallengeId "YOUR-CHALLENGE-ID"
```

For a challenge requested by a release APK connected to
`https://sendoh.onrender.com`, do not run `app.dev_otp` locally. Open the Render
service logs and find the corresponding `SENDOH_STAGING_OTP` entry. The local
development controls are excluded from Flutter release builds.

## 6. Enable Infobip after delivery testing

Set these Render variables and redeploy:

```text
OTP_PROVIDER=infobip
INFOBIP_BASE_URL=https://xxxxx.api.infobip.com
INFOBIP_API_KEY=<secret>
INFOBIP_SENDER=ServiceSMS
```

The trial sender and permitted destination numbers are controlled by the
Infobip account. Test delivery separately to MTN and Orange Cameroon before
inviting external testers.

## Production gate

Before real users or money:

- use an always-on Render plan;
- replace the staging database with an isolated production Neon database;
- enable real SMS and disable logged OTPs;
- configure a custom domain and HTTPS;
- add rate limiting and monitoring;
- finish CamPay webhook verification, idempotency, reconciliation, and failure
  recovery;
- create and protect Android and iOS signing credentials.
