# Arca — Architecture & Decision Log

**Working Tagline:** *"Your records. Your way."*  
**Central Experience:** *"Save something important now. Find it easily when you need it."*

---

## 1. Environment & Platform Assessment

### Observed Environment
- **Host OS:** macOS 27.0.1 (`arm64-apple-macosx27.0.0`)
- **Compiler & Toolchain:** Apple Swift 6.4 (`swiftlang-6.4.0.34.1`, `clang-2100.3.34.1`) via Command Line Tools (`/Library/Developer/CommandLineTools`)
- **System SQLite:** SQLite 3.54.0 (with FTS5 & JSON1 support built-in)
- **Full Xcode.app / iOS Simulator (`xcodebuild`, `simctl`):** Not installed in the current environment (only Command Line Tools and `MacOSX.sdk` are active).

### Deployment Target Decision & Tradeoffs
- **Selected Target:** **iOS 17.0+** (paired with `macOS 14.0+` in `Package.swift` so that all domain, persistence, encryption, sync, billing, and SwiftUI views compile and pass automated test suites under `swift build` and `swift test` on the current machine, while providing an Xcode `.xcodeproj` / SwiftPM App target ready to open on iOS 17+).
- **Why iOS 17.0+:**
  1. **Observation Framework (`@Observable`):** Eliminates boilerplate `ObservableObject`/`@Published` redraw cascades and cleanly scopes view invalidation for dynamic forms and record lists.
  2. **Swift Charts Enhancements:** Native selection and scrolling APIs (`chartXSelection`, `chartScrollableAxes`) for spending-over-time and warranty insights.
  3. **StoreKit 2 SwiftUI Views & Updates:** Mature `SubscriptionStoreView` and transaction listener APIs.
  4. **Compatibility Tradeoff:** Drops iOS 15/16 devices (<4% of active iPhones in 2026) in exchange for dramatic reductions in state-management bugs, better accessibility focus handling (`@AccessibilityFocusState`), and modern `NavigationStack` / `.inspector` / `.searchable` ergonomics.

---

## 2. Persistence Evaluation: Direct SQLite vs. SwiftData

| Requirement | SwiftData / Core Data | Direct SQLite (`SQLite3` C API + Typed Swift Actor Layer) |
| :--- | :--- | :--- |
| **Dynamic runtime user-defined schemas** | Poor fit. `@Model` requires compile-time Swift classes; arbitrary user fields force an opaque JSON blob or awkward EAV table without native predicate pushdown. | **Excellent fit.** Canonical record payload + typed EAV projection tables (`record_field_projections`) + FTS5 virtual tables (`records_fts`) queried dynamically. |
| **Independent database file per Space** | Cumbersome multi-`ModelContainer` lifecycle and fragile file detachment during live export/restore. | **Native.** Each Space is an isolated directory (`Spaces/<space-uuid>/space.sqlite` + `Attachments/`) plus a lightweight `catalog.sqlite`. |
| **Safe field type conversion & preview** | Heavyweight staged schema migrations designed for developer-compiled versions, not user-driven live field edits. | **Deterministic.** Versioned JSON/SQLite schema definitions (`schema_version`) with dry-run conversion previews and soft-deleted field retention (`retained_field_values`). |
| **Custom E2EE operation-log sync** | Automatic CloudKit sync is incompatible with client-side E2EE of schema/collection names, 2-device free tier enforcement, and custom conflict preservation. | **Full control.** Durable `sync_outbox`, `sync_cursors`, per-record revision vectors, and deletion tombstones inside the same ACID transaction as record writes. |
| **Cross-platform portability (Future Android)** | Apple-proprietary schema and metadata tables. | **100% OS-independent.** UUIDv4/v7 strings, ISO-8601 dates, integer minor units / exact decimal strings for money, and portable `.arcaarchive` bundles. |
| **Zero external network dependency to build** | Built-in. | Built-in (`import SQLite3` system library) — works offline inside sandboxed environments with zero third-party supply-chain risk. |

**Decision:** Use **Direct SQLite (`import SQLite3`) wrapped in a dedicated concurrency-safe Swift `actor` persistence engine (`SQLiteDatabase`, `SpaceStore`, `CatalogStore`)**.

---

## 3. Module & Layer Architecture

Arca is organized into clean, testable layers with strict boundaries:

```
Arca/
├── Sources/
│   ├── ArcaCore/                  # Domain models, Dynamic Schema Engine, Validation, Money/Date types
│   ├── ArcaPersistence/           # SQLite3 engine, CatalogStore, SpaceStore, FTS5 search, Index projections
│   ├── ArcaArchive/               # Portable .arcaarchive packager, SHA-256 manifest, AES-GCM encrypted backups, staged restore
│   ├── ArcaCrypto/                # CryptoKit E2EE (HKDF, AES-GCM-256, Curve25519/P256 device enrollment, Keychain, Recovery Codes)
│   ├── ArcaSync/                  # Outbox queue, idempotent push/pull, conflict detection & preservation, 2-device limit engine
│   ├── ArcaBilling/               # StoreKit 2 manager, centralized quotas/pricing config, expiry & grace-period behavior
│   ├── ArcaCloudAdapters/         # Personal Cloud Backup assessment, direct-to-provider encrypted backup contract
│   └── ArcaUI/                    # SwiftUI Design System, Localization (EN/AR RTL/TR), and all 19 Screens & States
├── App/                           # iOS / macOS App entry point & Xcode project specification
└── Tests/
    └── ArcaTests/                 # Comprehensive Unit & Integration Test Suite covering all Stage 16 verification criteria
```

---

## 4. Storage, Encryption & Privacy Model

### Per-Space Storage Modes
Every Space (database) independently configures its storage mode in `catalog.sqlite`:
1. **`arcaSync` (Recommended Default for general spaces):**
   - Full local SQLite persistence + encrypted sync via Arca Cloud.
   - Requires explicit user opt-in during onboarding or mode migration before any outbox item leaves the device.
   - Enforces **2 active devices** on the Free tier. Attempting to enroll a 3rd device blocks sync enrollment with a clear device management / upgrade resolution flow while preserving all local access.
2. **`localOnly` (Default for sensitive templates such as *Medical Visits*):**
   - Zero network requests, zero account requirements, zero sync outbox generation.
   - Protected on disk with `NSFileProtectionComplete` (`completeFileProtection`) and excluded from unencrypted cloud auto-backups when configured by the user.
3. **`personalCloudBackup` (Later Paid Capability — Optional Provider Adapters, Separated from Sync):**
   - **Provider-Independent Client-Side Encryption:** Client-side encryption (`ArcaCrypto`) operates as an independent layer prior to any storage or transport adapter. Whether encrypted payloads are sent to Arca Sync, exported to a local file, or uploaded via an optional iCloud Drive / Google Drive backup adapter, the cryptographic envelope is identical and independent of the provider.
   - **Policy & Classification Nuance:** Arca is a general-purpose personal records app with user-defined schemas—not a dedicated medical device or regulated healthcare provider app. However, users *may* store sensitive personal records (such as the *Medical Visits* starter template or custom collections). Conversely, client-side encryption does **not** automatically grant an exemption from platform terms (such as Apple iCloud terms regarding health data or App Store Review Guidelines) or regulatory obligations.
   - Therefore:
     1. We support **Local-only** and **Arca Sync** first.
     2. We design **iCloud Drive** and **Google Drive** strictly as optional, modular backup adapters (`CloudBackupProviderAdapter`) behind a feature/policy verification gate (`ProviderPolicyComplianceStatus`), verifying applicable provider terms per space/template before release or enablement.
     3. Never silently fall back to Arca Cloud if a personal cloud adapter fails or is restricted.

### End-to-End Encryption (E2EE) Lifecycle
- **Root & Space Keys:**
  - Each synced account generates a 256-bit **Master Account Key (MAK)** on device using `SymmetricKey(size: .bits256)`.
  - Each Space has an independent 256-bit **Space Data Encryption Key (SDEK)** wrapped by the MAK using `AES.GCM`.
  - Records, collection schemas, collection names, and attachments are encrypted on the client with `AES.GCM` using unique 96-bit nonces and authenticated additional data (`AAD` binding `spaceId + entityType + entityId + revision`).
- **Recovery vs. Password Reset:**
  - Account authentication uses standard credentials/passkeys. Resetting an account password **cannot** decrypt E2EE records.
  - During enrollment, the user receives a formatted **Recovery Key** (high-entropy 256-bit secret encoded in human-readable groups, derived via HKDF-SHA256) that wraps a recovery copy of the MAK. Losing both all enrolled devices and the Recovery Key permanently prevents decrypting remote ciphertext.
- **Device Enrollment, Key Rotation & Revocation:**
  - Each device generates an asymmetric Curve25519 keypair (`CryptoKit.Curve25519.KeyAgreement`). Enrollment wraps the MAK to the new device's public key.
  - Revoking a device marks its `deviceId` revoked on the service, rotates the Space SDEK for future writes, and blocks future API tokens. UI copy explicitly clarifies that revocation blocks future sync access but cannot forcibly erase data already downloaded onto an offline revoked device.
- **Server-Visible Metadata Disclosure:**
  - Clearly disclosed in the Privacy & Sync UI: Account identifier, enrolled device count and device labels, encrypted record/attachment byte sizes, opaque UUIDs, revision integers, and request timestamps.

---

## 5. Dynamic Schema Engine & Data Integrity

- **Stable Identity:** Every `FieldDefinition` has an immutable `id: UUID` and a mutable `label: String`. Renaming a label updates `schema_version` without touching stored record keys.
- **Exact Value Representation:**
  - `currency`: Stored as `MoneyValue(minorUnits: Int64, currencyCode: String, decimalPlaces: Int)` (e.g., `$124.50` -> `12450` minor units in `USD`) to prevent IEEE-754 floating-point drift.
  - `date` (Date-only): Stored as timezone-independent calendar date string `YYYY-MM-DD` so a medical visit or warranty expiration on `2026-11-15` never shifts by +/- 1 day when traveling across time zones.
  - `dateTime`: Stored as UTC ISO-8601 instant with milliseconds (`2026-10-31T13:08:00.000Z`) plus optional recorded timezone identifier.
- **Field Removal Retention Policy:**
  - Removing a field from a collection moves it to `archivedFields` in the schema (with a 30-day / manual recovery window) rather than immediately Purging user data. Users can restore the archived field with all historical values intact or explicitly purge it.
- **Field Type Change Dry-Run Preview:**
  - Before applying a field type change (e.g., `shortText` -> `number`), `SchemaMigrationAnalyzer` scans all records in the collection, previews how many records convert cleanly vs. fail conversion, and blocks destructive silent truncation.
- **Search & Filter Projections:**
  - Every record save updates:
    1. `records` table (canonical JSON payload, revision, favorite flag, timestamps).
    2. `record_field_projections` table (`record_id`, `field_id`, `text_val`, `num_val`, `date_val`, `bool_val`) with composite SQLite indexes for fast sorting and filtering.
    3. `records_fts` (SQLite FTS5 virtual table) for instant full-text search across a Space.

---

## 6. Sync Semantics & Conflict Preservation

- **No SQLite File Overwrite:** Sync operates exclusively on structured, encrypted operation envelopes (`RecordUpsert`, `RecordTombstone`, `SchemaUpsert`, `AttachmentUpload`).
- **Outbox & Idempotency:** Local mutations append an `OutboxOperation(operationId: UUID, spaceId: UUID, entityType, entityId, baseRevision: Int64, payload)` inside the same SQLite transaction. Retries reuse the same `operationId` for idempotency.
- **Conflict Detection without Wall-Clock Trust:**
  - Authority is a monotonic per-entity `revision: Int64` and `lastModifiedByDeviceId: String`.
  - If a remote pull delivers revision `R_remote` while the local record has uncommitted changes based on `R_base < R_remote`, Arca compares field-by-field:
    - Disjoint field edits merge cleanly.
    - Overlapping edits to the same field (or Edit vs. Delete) create a first-class **`SyncConflict`** object preserving both the local version and remote version for explicit user review in the Sync & Conflicts screen.

---

## 7. Portable Archive (`.arcaarchive`) & Mode Transitions

- **Format:** Directory/bundle container with `manifest.json` (format version `1.0`, space metadata, schema count, record count, attachment list, per-file SHA-256 digests, and overall HMAC/SHA-256 integrity hash), `schemas.json`, `records.json`, and `attachments/<uuid>.bin`.
- **Optional Encryption:** Password-based key derivation (`HKDF-SHA256` with high-iteration salted stretching + `AES.GCM`) producing an authenticated `.arcaarchive.enc` payload.
- **Atomic Staged Restore:**
  1. Unpacks and validates path traversal rules (rejects `..`, absolute paths, symlinks) and verifies every SHA-256 checksum in a temporary staging directory before touching live data.
  2. Defaults to **Restore as a New Space** (guaranteeing zero destructive overwrite of existing spaces), with clear duplicate-handling options if merging.

---

## 8. Implementation Sequence

- **Stage 1 (Complete):** Workspace inspection, architecture, and decision log (`ARCHITECTURE.md`).
- **Stage 2:** Complete navigable SwiftUI prototype with all 19 required screens, design system, localization (English, Arabic RTL, Turkish), and rich realistic sample data.
- **Stage 3:** Production SQLite persistence engine (`CatalogStore`, per-space `SpaceStore`, FTS5 search, indexed field projections, dynamic schema migrations, and local file attachments).
- **Stage 4:** Verified portable export and staged restore (`.arcaarchive` with SHA-256 manifest, tamper/corruption detection, and AES-GCM encryption).
- **Stage 5:** End-to-end encryption lifecycle (`ArcaCrypto`) and `ArcaSync` engine (durable outbox, incremental cursors, conflict preservation, and 2-device free limit enforcement).
- **Stage 6:** StoreKit 2 monetization (`ArcaBilling`), entitlement expiry safeguards (zero local data loss), and production hardening.
- **Stage 7:** Personal-cloud encrypted backup adapter assessment and contract verification, followed by full unit/integration test suite execution.
