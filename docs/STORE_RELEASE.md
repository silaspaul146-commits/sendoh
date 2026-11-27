# Store release: Sendoh for Android (and later iOS)

The app's permanent store identity is **`cm.sendoh.app`** (Android application ID and iOS bundle ID). It can never change after the first Play upload. The name on the phone is **Sendoh**.

## 1. Firebase push for the new app ID (once)

Push alerts were registered for the old package `com.example.sendoh_organizer`. Until this step is done, staging builds still install and work, but push alerts may not register.

1. Firebase console → your Sendoh project → **Add app → Android**, package name `cm.sendoh.app`, nickname "Sendoh".
2. Copy the new **App ID** (`1:…:android:…`). You don't need to download `google-services.json`: the app reads its configuration at build time.
3. GitHub → repository → Settings → Secrets and variables → Actions → **Variables** → `SENDOH_FIREBASE_CONFIG`: replace the value of `FIREBASE_ANDROID_APP_ID` with the new App ID. Leave the other fields unchanged.
4. Later, for iOS: add an iOS app with bundle ID `cm.sendoh.app` and set `FIREBASE_IOS_APP_ID` and `FIREBASE_IOS_BUNDLE_ID` the same way.

## 2. Upload key (once, kept off GitHub)

Google Play signs the published app with its own key (Play App Signing). You sign uploads with an **upload key** that stays on your computer.

In PowerShell:

```powershell
keytool -genkey -v -keystore $HOME\sendoh-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Keep the `.jks` file and its passwords in your password manager, with a backup. Losing them means asking Google for an upload-key reset.

Then create `apps/organizer_flutter/android/key.properties`. Git ignores this file; never commit it.

```properties
storeFile=C:/Users/<you>/sendoh-upload.jks
storePassword=<the store password>
keyAlias=upload
keyPassword=<the key password>
```

Without `key.properties`, release builds fall back to the debug key. That's fine for staging APKs, but Play rejects them.

## 3. Build the Play bundle

```powershell
cd apps/organizer_flutter
flutter build appbundle --release --dart-define=API_URL=https://sendoh.onrender.com --dart-define-from-file=<path to your push config json>
```

Upload `build/app/outputs/bundle/release/app-release.aab`. Raise `version:` in `pubspec.yaml` (for example `0.1.0+1` → `0.1.1+2`) before each upload; the number after `+` must always increase.

## 4. Play Console answers that depend on the product

- **App access:** sign-in uses a phone code. Give reviewers a test number and a way to get its code (staging logs, or a reviewer number once SMS is live).
- **Account deletion:** in the app at Profile → Delete account; on the web at `https://sendoh.vercel.app/delete-account`.
- **Privacy policy:** `https://sendoh.vercel.app/privacy`.
- **Data safety** (matches the privacy policy): collects phone number, name, optional photo, financial info (payment records, Mobile Money number), and device ID (push token). Data is encrypted in transit. People can request deletion. Payment records are kept after deletion as financial records. Nothing is shared for advertising.
- **Financial features declaration:** declare person-to-person payments and group collections through a licensed payment provider (MeSomb). Answer according to your MeSomb contract and legal advice.
- **Closed testing:** a new personal developer account needs a closed test with at least 12 testers for 14 days before production access.

## 5. Website settings (Vercel)

- `NEXT_PUBLIC_SUPPORT_EMAIL`, `NEXT_PUBLIC_SUPPORT_WHATSAPP`: shown on `/support`.
- `NEXT_PUBLIC_LEGAL_ENTITY`: the operator name in the privacy policy and terms (defaults to "Sendoh").
