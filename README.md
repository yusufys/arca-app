# arca-app

**Arca — “Your records. Your way.”**  
*"Save something important now. Find it easily when you need it."*

A local-first, cross-platform monorepo for **Arca** on **iOS (Swift / SwiftUI)** and **Android (Kotlin / Jetpack Compose)**.

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
│   ├── ArcaSync/                    # Durable outbox, idempotent operations & concurrent edit conflict preservation
│   ├── ArcaBilling/                 # StoreKit 2 subscriptions & non-destructive post-expiry safeguards
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
│   │   ├── sync/                    # Conflict merge engine, device limits & Play Billing post-expiry policy
│   │   └── ui/                      # Jetpack Compose screens, ViewModel, Theme & EN / AR (RTL) / TR strings
│   └── app/src/test/                # JUnit 4 verification tests
└── Arca-debug.apk                   # Pre-built Android debug APK for quick device testing
```

---

## Running iOS (`Swift` / `SwiftUI`)

### 1. Run on iPhone or iOS Simulator (Xcode)
```bash
open Arca.xcodeproj
```
Select your iPhone or Simulator target and press **`Cmd + R`**.

### 2. Run the Automated 9-Suite Verification Runner (CLI)
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
