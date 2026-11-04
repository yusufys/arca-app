# arca-app

**Arca — “Your records. Your way.”**  
*"Save something important now. Find it easily when you need it."*

A cross-platform monorepo for **Arca** featuring:
- **iOS (`Swift` / `SwiftUI`)**
- **Android (`Kotlin` / `Jetpack Compose`)**
- **Backend (`Laravel 13` + `PostgreSQL` + `FilamentPHP Admin Panel` + `RevenueCat Webhooks`)**

New Spaces default to Arca Sync and can be set to Local-Only. The iOS starter menus offer vehicles, warranties and home inventory.

[Download or open the standalone iOS release roadmap](ROADMAP.html) for the delivery board, milestone dependencies, release criteria, core features and frontend, backend and end-to-end architecture. Open the file locally to view the formatted page offline.

[RevenueCat setup, product IDs, Apple keys and verification](REVENUECAT.md).

---

## Monorepo Structure

```text
arca-app/
├── ARCHITECTURE.md                  # Architecture & Stage 1–7 engineering decision log
├── Package.swift                    # Swift Package (ArcaCore, ArcaCrypto, ArcaPersistence, ArcaArchive, ArcaSync, ArcaBilling, ArcaCloudAdapters, ArcaUI)
├── Arca.xcodeproj/                  # Native iOS Xcode project for physical iPhone & Simulator
├── iOSApp/                          # iOS App entry point & Info.plist
├── Sources/
│   ├── ArcaCore/                    # Domain models, MoneyValue (minor units), CalendarDate, StarterTemplates, SchemaEngine
│   ├── ArcaCrypto/                  # Provider-independent AES-256-GCM, HKDF-SHA256, Curve25519 & RecoveryKeyCredential
│   ├── ArcaPersistence/             # Actor-based SQLite WAL stores (CatalogStore, SpaceStore, FTS5 search, projections)
│   ├── ArcaArchive/                 # Portable .arcaarchive & encrypted .arcaarchive.enc export and staged restore
│   ├── ArcaSync/                    # Durable outbox, Laravel HTTP E2EE sync client & conflict preservation
│   ├── ArcaBilling/                 # StoreKit 2 / RevenueCat subscriptions & non-destructive post-expiry safeguards
│   ├── ArcaCloudAdapters/           # Optional personal cloud backup adapters & provider policy verification
│   ├── ArcaUI/                      # SwiftUI views, design system, and EN / AR (RTL) / TR localization
│   ├── ArcaApp/                     # Desktop / Simulator preview entry point
│   └── ArcaVerificationRunner/      # 9-suite automated verification runner
├── Tests/
│   └── ArcaTests/                   # XCTest suite
├── android/                         # Native Android app (Kotlin 2.0 + Jetpack Compose + Material 3)
│   ├── app/src/main/java/app/arca/android/
│   │   ├── model/                   # Cross-platform models, templates & SchemaEngine
│   │   ├── crypto/                  # AES-256-GCM, HKDF-SHA256, PBKDF2 & .arcaarchive validator
│   │   ├── persistence/             # Android SQLite WAL CatalogStore, SpaceStore & FTS search
│   │   ├── sync/                    # Laravel HTTP sync config, conflict merge engine & post-expiry policy
│   │   └── ui/                      # Jetpack Compose screens, ViewModel, Theme & EN / AR (RTL) / TR strings
│   └── app/src/test/                # JUnit 4 verification tests
├── backend/                         # Laravel 13 + PostgreSQL + FilamentPHP + RevenueCat Backend
│   ├── config/arca.php              # Default Cloud Sync mode, Free/Pro quotas & RevenueCat config
│   ├── app/Http/Controllers/Api/V1/ # Auth, Devices, E2EE Sync (Push/Pull/Migrate), Attachments, RevenueCat, Feed & Snapshots
│   ├── app/Filament/Resources/      # FilamentPHP v3 Resources (Announcements/Ads, Users, Devices, Public Snapshots)
│   ├── app/Http/Controllers/AdminDashboardController.php # Built-in /admin Web Dashboard
│   ├── database/migrations/         # PostgreSQL migrations for E2EE sync log, devices, announcements & webhooks
│   └── tests/Feature/               # Automated PHPUnit API & security test suite
└── Arca-debug.apk                   # Pre-built Android debug APK for quick device testing
```

---

## Running Backend (`Laravel` + `PostgreSQL` + `FilamentPHP` + `RevenueCat`)

### 1. Configure `.env` for PostgreSQL & RevenueCat
```bash
cd backend
cp .env.example .env
composer install
php artisan key:generate
php artisan migrate --seed
php artisan serve
```

### 2. Admin Panel & API Endpoints
- **Admin Dashboard / Announcements & Ads Manager**: `http://127.0.0.1:8000/admin`
- **RevenueCat Webhook Endpoint**: `POST /api/v1/webhooks/revenuecat` (with `Authorization: Bearer <REVENUECAT_WEBHOOK_SECRET>`)
- **E2EE Sync Endpoints**:
  - `POST /api/v1/spaces/{spaceId}/push` (Zero-plaintext validated; idempotent by `operation_id`)
  - `GET /api/v1/spaces/{spaceId}/pull?since_cursor=0`
  - `POST /api/v1/spaces/{spaceId}/migrate-mode` (Switch between `arca_sync` Cloud DB default and `local_only` with signed remote deletion receipt)
- **App Feed (Announcements / Ads / Remote Config)**: `GET /api/v1/app-feed?platform=ios&tier=free`

### 3. Run Backend Automated Tests (PHPUnit)
```bash
cd backend
php artisan test
```

---

## Running iOS (`Swift` / `SwiftUI`)

### 1. Run on iPhone or iOS Simulator (Xcode)
```bash
open Arca.xcodeproj
```
Select your iPhone or Simulator target and press **`Cmd + R`**.

### 2. Connect two iPhones

On the first device, choose **Arca Sync**, create an account and save the recovery key. On the second device, sign in with the same email, password and recovery key. Use **Settings → Sync Status, Outbox & Conflicts → Sync my cloud Spaces** to sync immediately. The app also checks for changes while it is in the foreground. Only Spaces configured for Arca Sync participate. Remote attachment uploads are currently disabled.

To run the force-quit and bidirectional sync check on a Mac with Xcode and an iOS Simulator runtime, run `python3 ci/test_ios_sync.py`. It creates two disposable simulators and a temporary account on the live Forge backend, then deletes them.

### 3. Run the Automated 9-Suite Verification Runner (CLI)
```bash
swift run --disable-sandbox -Xlinker -lsqlite3 ArcaVerificationRunner
```

---

## Running Android (`Kotlin` / `Jetpack Compose`)

### 1. Build Debug APK & Run Unit Tests
```bash
cd android
./gradlew assembleDebug testDebugUnitTest
```

### 2. Install Pre-Built APK to Connected Android Phone
```bash
adb install -r Arca-debug.apk
```
