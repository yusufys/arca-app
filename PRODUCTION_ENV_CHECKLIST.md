# Arca — Environment Variables & Production Setup Checklist

This checklist covers every environment variable, API key, and dashboard setting needed across **1) Laravel Backend (`backend/`)**, **2) iOS (`iOSApp/`)**, **3) Android (`android/`)**, and **4) RevenueCat**.

> **Important Security Note on Encryption Keys (E2EE)**:  
> You do **NOT** put any encryption keys in your mobile app `.env` or backend `.env`!  
> Arca is **Zero-Knowledge End-to-End Encrypted**: every user's Master Key, Space Keys (`AES-256-GCM`), Device Keys (`X25519`), and Recovery Key (`ARCA-XXXX-...`) are generated **on the user's device** using iOS `CryptoKit` / Android `Keystore`.  
> Mobile apps only ever hold **Public SDK Keys** (`appl_...` / `goog_...`), while **Secret Keys** (`REVENUECAT_WEBHOOK_SECRET`, DB password, S3/R2 secret key) stay strictly inside `backend/.env` on your server.

---

## 1. Laravel Backend (`backend/.env`)

Copy `backend/.env.example` to `backend/.env` on your server (or local Laravel Herd environment) and fill in:

- [ ] **App URL & Key**
  ```dotenv
  APP_NAME="Arca Cloud"
  APP_ENV=production
  APP_DEBUG=false
  APP_URL=https://api.yourdomain.com
  ```
  Run `php artisan key:generate` to populate `APP_KEY`.

- [ ] **PostgreSQL Database (`pgsql`)**
  ```dotenv
  DB_CONNECTION=pgsql
  DB_HOST=127.0.0.1
  DB_PORT=5432
  DB_DATABASE=arca
  DB_USERNAME=postgres
  DB_PASSWORD=your_strong_postgres_password
  ```

- [ ] **Arca Storage Mode & Quotas**
  ```dotenv
  # Default storage mode for new Spaces ('arca_sync' = Cloud DB default, 'local_only' = On Device)
  ARCA_DEFAULT_STORAGE_MODE=arca_sync
  ARCA_REMOTE_RETENTION_DAYS=90
  ```

- [ ] **RevenueCat Server Webhook Secret (PRIVATE — Server Only)**
  ```dotenv
  REVENUECAT_SERVER_API_KEY=your_revenuecat_v1_server_api_key
  REVENUECAT_ENVIRONMENT=PRODUCTION
  REVENUECAT_WEBHOOK_SECRET=your_random_64_char_webhook_bearer_secret
  REVENUECAT_PRO_ENTITLEMENT_ID=arca_app_pro
  ```

- [ ] **Cloudflare R2 / AWS S3 for Encrypted Attachment Blobs (PRIVATE — Server Only)**
  ```dotenv
  ARCA_ATTACHMENTS_DISK=r2
  AWS_ACCESS_KEY_ID=your_r2_or_s3_access_key
  AWS_SECRET_ACCESS_KEY=your_r2_or_s3_secret_key
  AWS_DEFAULT_REGION=auto
  AWS_BUCKET=arca-encrypted-blobs
  AWS_ENDPOINT=https://<account_id>.r2.cloudflarestorage.com
  ```

- [ ] **Run Migrations**
  ```bash
  cd backend
  composer install --optimize-autoloader --no-dev
  php artisan migrate --force
  ```
  - Provision an administrator separately. The dashboard requires HTTP Basic authentication and the admin role.
  - Admin Dashboard URL: `https://api.yourdomain.com/admin`

---

## 2. iOS App (`iOSApp/Info.plist` & `ArcaEnvironmentConfig`)

The iOS app reads its configuration automatically via [`ArcaEnvironmentConfig`](Sources/ArcaSync/LaravelArcaSyncBackend.swift) from either Xcode Scheme Environment Variables or [`iOSApp/Info.plist`](iOSApp/Info.plist):

- [ ] **Set `ARCA_API_BASE_URL` in [`iOSApp/Info.plist`](iOSApp/Info.plist)**
  - Local Mac testing: `http://127.0.0.1:8000` (or your Mac's LAN IP `http://192.168.x.x:8000` when testing on a physical iPhone over Wi-Fi)
  - Production: `https://api.yourdomain.com`

- [ ] **Set the Release build setting `ARCA_RC_PUBLIC_KEY`; Info.plist expands it into `REVENUECAT_IOS_PUBLIC_KEY`**
  - Format: `appl_xxxxxxxxxxxxxxxxxxxxxxxx` (found in **RevenueCat Dashboard → Project Settings → API Keys → Public app-specific API keys (Apple)**).
  - ⚠️ Use the **Public** `appl_...` key only (never `sk_...`).

- [ ] **Set `REVENUECAT_PRO_ENTITLEMENT_ID` in [`iOSApp/Info.plist`](iOSApp/Info.plist)**
  - Value: `arca_app_pro`

- [ ] **Apple Developer Signing (Xcode)**
  - Open `Arca.xcodeproj` → **Signing & Capabilities** → select your Apple Team & Bundle ID (`app.arca.personalrecords`).

---

## 3. Android App (`android/local.properties` or CI Env Vars)

[`android/app/build.gradle.kts`](android/app/build.gradle.kts) automatically reads these values from `android/local.properties` (which is gitignored) or environment variables and compiles them into `BuildConfig` for [`LaravelHttpConfig`](android/app/src/main/java/app/arca/android/sync/ArcaSyncAndBilling.kt):

- [ ] **Add keys to `android/local.properties`**
  ```properties
  # Local Android Emulator uses 10.0.2.2 to reach your Mac's localhost:8000
  # Physical Android phone on Wi-Fi: use http://192.168.x.x:8000
  # Production: https://api.yourdomain.com
  ARCA_API_BASE_URL=https://api.yourdomain.com

  # RevenueCat Google Play PUBLIC SDK Key (starts with goog_...)
  REVENUECAT_ANDROID_PUBLIC_KEY=goog_xxxxxxxxxxxxxxxxxxxxxxxx

  # Entitlement ID
  REVENUECAT_PRO_ENTITLEMENT_ID=arca_app_pro
  ```

- [ ] **Rebuild APK after updating `local.properties`**
  ```bash
  cd android
  ./gradlew assembleDebug
  ```

---

## 4. RevenueCat dashboard and TestFlight

Follow [Arca’s RevenueCat setup and verification guide](REVENUECAT.md). The iOS entitlement is `arca_app_pro`. The three products are `lifetime`, `yearly` and `monthly`. Configure separate staging and production webhook environments.
