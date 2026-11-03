import Foundation
import SwiftUI
import Observation
import CryptoKit
import ArcaCore
import ArcaCrypto
import ArcaPersistence
import ArcaArchive
import ArcaSync
import ArcaBilling
import ArcaCloudAdapters

/// UI-friendly representation of an enrolled device.
public struct DeviceSummaryItem: Identifiable, Sendable, Equatable {
    public var id: String { deviceId }
    public let deviceId: String
    public let deviceName: String
    public let enrolledAt: Date
    public let isCurrentDevice: Bool
}

/// UI-friendly representation of a preserved concurrent edit conflict.
public struct ConflictSummaryItem: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let recordId: UUID
    public let localRecord: RecordItem
    public let remoteRecord: RecordItem
    public let conflictingFieldIds: [UUID]
    public let summary: String
}

/// Central `@MainActor @Observable` coordinator connecting SwiftUI screens to
/// `CatalogStore`, per-Space `SpaceStore` SQLite files, `ClientCryptoEngine`,
/// `ArchiveService`, `SyncCoordinator`, `BillingManager`, and `PersonalCloudBackupAdapter`.
@available(macOS 14.0, iOS 17.0, *)
@MainActor
@Observable
public final class ArcaAppViewModel {

    // MARK: - App Preferences & Navigation State
    public var hasCompletedOnboarding: Bool = false
    public var language: AppLanguage = .english
    public var appearanceMode: AppAppearanceMode = .light
    public var biometricLockEnabled: Bool = false
    public var isAppLocked: Bool = false
    public var bannerState: OperationalBannerState = .normal
    public var globalSearchText: String = ""

    // MARK: - Spaces, Collections & Records
    public var spaces: [SpaceMetadata] = []
    public var currentSpaceId: UUID?
    public var collectionsBySpace: [UUID: [CollectionSchema]] = [:]
    public var recordsBySpace: [UUID: [RecordItem]] = [:]
    public var publicSnapshots: [PublicRecordSnapshot] = []
    public var exportedArchiveURLs: [URL] = []

    // MARK: - Encryption, Sync, Devices & Billing State
    public var recoveryKeyPhrase: String
    public var enrolledDevices: [DeviceSummaryItem] = []
    public var syncConflicts: [ConflictSummaryItem] = []
    public var pendingOutboxCount: Int = 0
    public var isOfflineSimulated: Bool = false {
        didSet {
            if isOfflineSimulated {
                bannerState = .offlineQueued(pendingCount: pendingOutboxCount)
            } else if case .offlineQueued = bannerState {
                bannerState = .normal
            }
        }
    }
    public var isProSubscriber: Bool = false

    // MARK: - Underlying Engines
    public let rootDirectoryURL: URL
    public let catalogStore: CatalogStore
    private var spaceStores: [UUID: SpaceStore] = [:]
    public let syncBackend: InMemoryArcaSyncBackend
    public let billingManager: BillingManager
    private let masterAccountKey: SymmetricKey
    private var spaceKeyRings: [UUID: SpaceKeyRing] = [:]
    private let currentDeviceIdentity: DeviceIdentity
    private var accountId: String = "acct-local-default"
    private var isBootstrapped: Bool = false

    public init(rootDirectoryURL: URL? = nil, startWithCompletedOnboarding: Bool = false) {
        let baseDir = rootDirectoryURL ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("ArcaWorkspace-\(UUID().uuidString.prefix(8))", isDirectory: true)
        self.rootDirectoryURL = baseDir
        self.catalogStore = CatalogStore(baseDirectoryURL: baseDir)
        self.syncBackend = InMemoryArcaSyncBackend()
        self.billingManager = BillingManager()

        let mak = SymmetricKey(size: .bits256)
        self.masterAccountKey = mak
        let cred = RecoveryKeyCredential.generate()
        self.recoveryKeyPhrase = cred.formattedPhrase
        self.currentDeviceIdentity = DeviceIdentity(deviceId: "dev-primary-iphone", deviceName: "My iPhone")
        self.enrolledDevices = [
            DeviceSummaryItem(
                deviceId: currentDeviceIdentity.deviceId,
                deviceName: currentDeviceIdentity.deviceName,
                enrolledAt: Date(),
                isCurrentDevice: true
            )
        ]
        self.hasCompletedOnboarding = startWithCompletedOnboarding
    }

    // MARK: - Computed Properties for Views

    public var currentSpace: SpaceMetadata? {
        guard let id = currentSpaceId else { return spaces.first }
        return spaces.first(where: { $0.id == id }) ?? spaces.first
    }

    public var collectionsInCurrentSpace: [CollectionSchema] {
        guard let spaceId = currentSpace?.id else { return [] }
        return (collectionsBySpace[spaceId] ?? []).filter { !$0.isDeleted }
    }

    public var recordsInCurrentSpace: [RecordItem] {
        guard let spaceId = currentSpace?.id else { return [] }
        return (recordsBySpace[spaceId] ?? []).filter { !$0.isDeleted }
    }

    public var favoriteRecordsInCurrentSpace: [RecordItem] {
        recordsInCurrentSpace
            .filter { $0.isFavorite }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public var recentRecordsInCurrentSpace: [RecordItem] {
        recordsInCurrentSpace
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public var maxAllowedDevices: Int {
        isProSubscriber
            ? ArcaCommercialConfig.proMaxActiveDevices
            : ArcaCommercialConfig.freeMaxActiveDevices
    }

    public var currentSpaceInsights: SpaceInsightsReport {
        guard let spaceId = currentSpace?.id else {
            return SpaceInsightsReport.compute(spaceId: UUID(), collections: [], records: [], locale: language.locale)
        }
        return SpaceInsightsReport.compute(
            spaceId: spaceId,
            collections: collectionsInCurrentSpace,
            records: recordsInCurrentSpace,
            locale: language.locale
        )
    }

    public func schema(for collectionId: UUID) -> CollectionSchema? {
        for (_, cols) in collectionsBySpace {
            if let match = cols.first(where: { $0.id == collectionId && !$0.isDeleted }) {
                return match
            }
        }
        return nil
    }

    public func record(for recordId: UUID) -> RecordItem? {
        for (_, recs) in recordsBySpace {
            if let match = recs.first(where: { $0.id == recordId && !$0.isDeleted }) {
                return match
            }
        }
        return nil
    }

    public func recordCount(for collectionId: UUID) -> Int {
        recordsInCurrentSpace.filter { $0.collectionId == collectionId }.count
    }

    // MARK: - Bootstrap & Onboarding

    public func bootstrapIfNeeded() async {
        guard !isBootstrapped else { return }
        isBootstrapped = true

        let existing = await catalogStore.listSpaces()
        if !existing.isEmpty {
            self.spaces = existing
            self.currentSpaceId = existing.first?.id
            for sp in existing {
                await reloadSpaceFromDisk(sp.id)
            }
            self.hasCompletedOnboarding = true
        } else if hasCompletedOnboarding {
            await finishOnboarding(
                defaultMode: .arcaSync,
                acceptedCloudTerms: true,
                selectedTemplates: [.vehicleMaintenance, .homeInventory, .warranties]
            )
        }
    }

    public func completeCloudAccountEnrollment(email: String) {
        Task {
            let maxDevs = isProSubscriber
                ? ArcaCommercialConfig.proMaxActiveDevices
                : ArcaCommercialConfig.freeMaxActiveDevices
            let quota = isProSubscriber
                ? ArcaCommercialConfig.proCloudStorageQuotaBytes
                : ArcaCommercialConfig.freeCloudStorageQuotaBytes
            let session = try? await syncBackend.authenticate(
                email: email,
                credentialProof: "enrollment-token",
                maxAllowedDevices: maxDevs,
                storageQuotaBytes: quota
            )
            if let acct = session?.accountId {
                self.accountId = acct
                let enrolledDev = EnrolledDevice(descriptor: currentDeviceIdentity.descriptor)
                _ = try? await syncBackend.enrollDevice(
                    accountId: acct,
                    device: enrolledDev,
                    maxAllowedDevices: maxDevs,
                    wrappedMasterKey: nil
                )
            }
        }
    }

    public func finishOnboarding(
        defaultMode: SpaceStorageMode,
        acceptedCloudTerms: Bool,
        selectedTemplates: [StarterTemplateID]
    ) async {
        let effectiveMode: SpaceStorageMode = (defaultMode == .arcaSync && acceptedCloudTerms) ? .arcaSync : .localOnly

        // 1. Seed Primary Personal & Home Space
        let personalBundle = SampleDataFactory.createDefaultPersonalSpace(storageMode: effectiveMode)
        await persistSeededBundle(personalBundle)

        // 2. Seed Vehicles Space if requested
        if selectedTemplates.contains(.vehicleMaintenance) {
            let vehicleBundle = SampleDataFactory.createVehiclesSpace(storageMode: effectiveMode)
            await persistSeededBundle(vehicleBundle)
        }

        self.currentSpaceId = spaces.first?.id
        self.hasCompletedOnboarding = true
        await refreshOutboxCount()
    }

    private func persistSeededBundle(_ bundle: SampleDataFactory.SeededSpaceBundle) async {
        await catalogStore.saveSpace(bundle.space)
        let store = await spaceStore(for: bundle.space.id)
        let enqueue = bundle.space.storageMode == .arcaSync
        for col in bundle.collections {
            await store.saveCollection(col, enqueueSync: enqueue)
        }
        for rec in bundle.records {
            if let col = bundle.collections.first(where: { $0.id == rec.collectionId }) {
                try? await store.saveRecord(rec, schema: col, enqueueSync: enqueue)
            }
        }
        self.spaces = await catalogStore.listSpaces()
        await reloadSpaceFromDisk(bundle.space.id)
    }

    private func spaceStore(for spaceId: UUID) async -> SpaceStore {
        if let existing = spaceStores[spaceId] {
            return existing
        }
        let store = SpaceStore(spaceId: spaceId, baseDirectoryURL: rootDirectoryURL)
        spaceStores[spaceId] = store
        if spaceKeyRings[spaceId] == nil {
            spaceKeyRings[spaceId] = SpaceKeyRing(spaceId: spaceId)
        }
        return store
    }

    private func reloadSpaceFromDisk(_ spaceId: UUID) async {
        let store = await spaceStore(for: spaceId)
        let cols = await store.listCollections(includeDeleted: false)
        let recs = await store.listRecords(includeDeleted: false)
        collectionsBySpace[spaceId] = cols
        recordsBySpace[spaceId] = recs
        await refreshOutboxCount()
    }

    private func refreshOutboxCount() async {
        guard let spaceId = currentSpace?.id else {
            pendingOutboxCount = 0
            return
        }
        let store = await spaceStore(for: spaceId)
        let items = await store.pendingOutboxItems()
        pendingOutboxCount = items.count
        if isOfflineSimulated {
            bannerState = .offlineQueued(pendingCount: pendingOutboxCount)
        }
    }

    // MARK: - Space Management

    public func selectSpace(_ spaceId: UUID) async {
        currentSpaceId = spaceId
        await reloadSpaceFromDisk(spaceId)
    }

    public func createSpace(name: String, iconName: String, storageMode: SpaceStorageMode) async {
        let space = SpaceMetadata(
            name: name,
            iconName: iconName,
            storageMode: storageMode,
            cloudSyncAcceptedAt: storageMode == .arcaSync ? Date() : nil
        )
        await catalogStore.saveSpace(space)
        spaces = await catalogStore.listSpaces()
        await selectSpace(space.id)
    }

    public func renameSpace(id: UUID, newName: String) async {
        guard !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        _ = await catalogStore.renameSpace(id: id, newName: newName)
        spaces = await catalogStore.listSpaces()
    }

    public func deleteSpace(id: UUID) async {
        guard spaces.count > 1 else { return }
        await catalogStore.deleteSpace(id: id)
        spaceStores.removeValue(forKey: id)
        collectionsBySpace.removeValue(forKey: id)
        recordsBySpace.removeValue(forKey: id)
        spaces = await catalogStore.listSpaces()
        if currentSpaceId == id {
            currentSpaceId = spaces.first?.id
        }
    }

    // MARK: - Collection & Dynamic Schema Operations

    public func createCollectionFromTemplate(_ template: StarterTemplate, createDedicatedLocalSpaceIfSensitive: Bool) async {
        var targetSpaceId = currentSpace?.id ?? UUID()
        if createDedicatedLocalSpaceIfSensitive {
            let localSpace = SpaceMetadata(
                name: "\(template.name) (Local)",
                iconName: template.iconName,
                accentHex: template.colorHex,
                storageMode: .localOnly,
                containsSensitiveHealthTemplate: template.id == .medicalVisits
            )
            await catalogStore.saveSpace(localSpace)
            spaces = await catalogStore.listSpaces()
            targetSpaceId = localSpace.id
            currentSpaceId = localSpace.id
        }

        let schema = template.instantiateSchema(for: targetSpaceId)
        let store = await spaceStore(for: targetSpaceId)
        let enqueue = spaces.first(where: { $0.id == targetSpaceId })?.storageMode == .arcaSync
        await store.saveCollection(schema, enqueueSync: enqueue)
        await reloadSpaceFromDisk(targetSpaceId)
    }

    public func createCustomCollection(name: String, iconName: String, fields: [FieldDefinition]) async {
        guard let spaceId = currentSpace?.id else { return }
        let schema = CollectionSchema(
            spaceId: spaceId,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            iconName: iconName,
            fields: fields
        )
        let store = await spaceStore(for: spaceId)
        let enqueue = currentSpace?.storageMode == .arcaSync
        await store.saveCollection(schema, enqueueSync: enqueue)
        await reloadSpaceFromDisk(spaceId)
    }

    public func importCollectionSchemaFromJSON(_ jsonString: String) throws {
        guard let spaceId = currentSpace?.id else { return }
        let schema = try OptionalCapabilityEngine.parseAndValidateImportedSchemaJSON(jsonString, for: spaceId)
        Task {
            let store = await spaceStore(for: spaceId)
            await store.saveCollection(schema, enqueueSync: currentSpace?.storageMode == .arcaSync)
            await reloadSpaceFromDisk(spaceId)
        }
    }

    public func renameField(in collectionId: UUID, fieldId: UUID, newLabel: String) async {
        guard let currentSchema = schema(for: collectionId) else { return }
        let updated = SchemaEngine.renameField(in: currentSchema, fieldId: fieldId, newLabel: newLabel)
        let store = await spaceStore(for: updated.spaceId)
        await store.saveCollection(updated, enqueueSync: currentSpace?.storageMode == .arcaSync)
        await reloadSpaceFromDisk(updated.spaceId)
    }

    public func moveField(in collectionId: UUID, fromIndex: Int, direction: Int) async {
        guard let currentSchema = schema(for: collectionId) else { return }
        var ids = currentSchema.activeFields.map(\.id)
        let targetIndex = fromIndex + direction
        guard ids.indices.contains(fromIndex), ids.indices.contains(targetIndex) else { return }
        ids.swapAt(fromIndex, targetIndex)
        let updated = SchemaEngine.reorderFields(in: currentSchema, orderedFieldIds: ids)
        let store = await spaceStore(for: updated.spaceId)
        await store.saveCollection(updated, enqueueSync: currentSpace?.storageMode == .arcaSync)
        await reloadSpaceFromDisk(updated.spaceId)
    }

    public func removeField(in collectionId: UUID, fieldId: UUID, policy: FieldRetentionPolicy) async {
        guard let currentSchema = schema(for: collectionId) else { return }
        let store = await spaceStore(for: currentSchema.spaceId)
        let existingRecords = await store.listRecords(collectionId: collectionId)
        let (updatedSchema, updatedRecords) = SchemaEngine.removeField(
            in: currentSchema,
            fieldId: fieldId,
            policy: policy,
            records: existingRecords
        )
        let enqueue = currentSpace?.storageMode == .arcaSync
        await store.saveCollection(updatedSchema, enqueueSync: enqueue)
        if policy == .permanentlyPurgeValues {
            for r in updatedRecords {
                try? await store.saveRecord(r, schema: updatedSchema, enqueueSync: enqueue)
            }
        }
        await reloadSpaceFromDisk(currentSchema.spaceId)
    }

    public func restoreArchivedField(in collectionId: UUID, fieldId: UUID) async {
        guard let currentSchema = schema(for: collectionId) else { return }
        let updated = SchemaEngine.restoreArchivedField(in: currentSchema, fieldId: fieldId)
        let store = await spaceStore(for: updated.spaceId)
        await store.saveCollection(updated, enqueueSync: currentSpace?.storageMode == .arcaSync)
        await reloadSpaceFromDisk(updated.spaceId)
    }

    public func addField(to collectionId: UUID, label: String, type: FieldType) async {
        guard var currentSchema = schema(for: collectionId) else { return }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        currentSchema.fields.append(FieldDefinition(
            label: trimmed,
            type: type,
            sortOrder: currentSchema.fields.count
        ))
        currentSchema.schemaVersion += 1
        currentSchema.revision += 1
        currentSchema.updatedAt = Date()
        let store = await spaceStore(for: currentSchema.spaceId)
        await store.saveCollection(currentSchema, enqueueSync: currentSpace?.storageMode == .arcaSync)
        await reloadSpaceFromDisk(currentSchema.spaceId)
    }

    public func previewFieldConversion(collectionId: UUID, field: FieldDefinition, targetType: FieldType) -> FieldConversionPreview {
        let recs = recordsInCurrentSpace.filter { $0.collectionId == collectionId }
        return SchemaEngine.previewFieldTypeConversion(field: field, targetType: targetType, records: recs)
    }

    public func applyFieldConversion(collectionId: UUID, fieldId: UUID, targetType: FieldType) async throws {
        guard let currentSchema = schema(for: collectionId) else { return }
        let store = await spaceStore(for: currentSchema.spaceId)
        let recs = await store.listRecords(collectionId: collectionId)
        let (updatedSchema, updatedRecords) = try SchemaEngine.applyFieldTypeConversion(
            in: currentSchema,
            fieldId: fieldId,
            targetType: targetType,
            records: recs
        )
        let enqueue = currentSpace?.storageMode == .arcaSync
        await store.saveCollection(updatedSchema, enqueueSync: enqueue)
        for r in updatedRecords {
            try await store.saveRecord(r, schema: updatedSchema, enqueueSync: enqueue)
        }
        await reloadSpaceFromDisk(currentSchema.spaceId)
    }

    // MARK: - Record CRUD, Attachments & Search

    public func saveRecord(
        existingRecord: RecordItem?,
        schema: CollectionSchema,
        values: [UUID: FieldValue],
        isFavorite: Bool
    ) async {
        let store = await spaceStore(for: schema.spaceId)
        let recordToSave: RecordItem
        if var existing = existingRecord {
            existing.values = values
            existing.isFavorite = isFavorite
            existing.schemaVersionAtWrite = schema.schemaVersion
            existing.updatedAt = Date()
            existing.revision += 1
            existing.lastModifiedByDeviceId = currentDeviceIdentity.deviceId
            recordToSave = existing
        } else {
            recordToSave = RecordItem(
                spaceId: schema.spaceId,
                collectionId: schema.id,
                schemaVersionAtWrite: schema.schemaVersion,
                values: values,
                isFavorite: isFavorite,
                lastModifiedByDeviceId: currentDeviceIdentity.deviceId
            )
        }
        let enqueue = currentSpace?.storageMode == .arcaSync
        try? await store.saveRecord(recordToSave, schema: schema, enqueueSync: enqueue)
        await reloadSpaceFromDisk(schema.spaceId)
    }

    public func toggleFavorite(recordId: UUID) async {
        guard var rec = record(for: recordId), let col = schema(for: rec.collectionId) else { return }
        rec.isFavorite.toggle()
        rec.revision += 1
        rec.updatedAt = Date()
        let store = await spaceStore(for: rec.spaceId)
        try? await store.saveRecord(rec, schema: col, enqueueSync: currentSpace?.storageMode == .arcaSync)
        await reloadSpaceFromDisk(rec.spaceId)
    }

    public func duplicateRecord(_ record: RecordItem) async {
        guard let col = schema(for: record.collectionId) else { return }
        let copy = record.duplicated(byDeviceId: currentDeviceIdentity.deviceId)
        let store = await spaceStore(for: record.spaceId)
        try? await store.saveRecord(copy, schema: col, enqueueSync: currentSpace?.storageMode == .arcaSync)
        await reloadSpaceFromDisk(record.spaceId)
    }

    public func deleteRecord(id: UUID) async {
        guard let rec = record(for: id) else { return }
        let store = await spaceStore(for: rec.spaceId)
        await store.deleteRecord(id: id, enqueueSync: currentSpace?.storageMode == .arcaSync)
        await reloadSpaceFromDisk(rec.spaceId)
    }

    public func attachSampleReceiptFile() async -> AttachmentReference? {
        guard let spaceId = currentSpace?.id else { return nil }
        let store = await spaceStore(for: spaceId)
        let sampleContent = Data("Arca Fictional Receipt Attachment • Invoice #\(Int.random(in: 1000...9999))".utf8)
        return try? await store.storeAttachment(
            data: sampleContent,
            filename: "receipt-\(Int.random(in: 100...999)).txt",
            mimeType: "text/plain"
        )
    }

    public func searchRecordsInCurrentSpace(queryText: String) -> [RecordItem] {
        queryRecords(RecordQuery(searchText: queryText, collectionId: nil, filters: [], sort: .updatedAtDescending))
    }

    public func queryRecords(_ query: RecordQuery) -> [RecordItem] {
        let base = recordsInCurrentSpace.filter { rec in
            if let colId = query.collectionId, rec.collectionId != colId {
                return false
            }
            return true
        }

        let trimmedSearch = query.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let searched = base.filter { rec in
            guard !trimmedSearch.isEmpty else { return true }
            guard let col = schema(for: rec.collectionId) else { return false }
            if rec.title(using: col).lowercased().contains(trimmedSearch) { return true }
            for field in col.activeFields {
                if let val = rec.values[field.id],
                   val.plainTextSummary(for: field).lowercased().contains(trimmedSearch) {
                    return true
                }
            }
            return false
        }

        let filtered = searched.filter { rec in
            for filter in query.filters {
                switch filter {
                case .favoritesOnly:
                    if !rec.isFavorite { return false }
                case .hasAttachments:
                    if rec.allAttachments.isEmpty { return false }
                case .booleanEquals(let fId, let expected):
                    guard case .boolean(let actual) = rec.values[fId], actual == expected else { return false }
                case .selectContains(let fId, let optId):
                    if case .singleSelect(let s) = rec.values[fId], s == optId { continue }
                    if case .multiSelect(let arr) = rec.values[fId], arr.contains(optId) { continue }
                    return false
                case .minimumRating(let fId, let minR):
                    guard case .rating(let r) = rec.values[fId], r >= minR else { return false }
                case .numberRange(let fId, let minVal, let maxVal):
                    let num: Double? = {
                        if case .number(let n) = rec.values[fId] { return n }
                        if case .currency(let m) = rec.values[fId] { return m.doubleApproximationForChartsOnly }
                        return nil
                    }()
                    guard let n = num else { return false }
                    if let minVal, n < minVal { return false }
                    if let maxVal, n > maxVal { return false }
                case .dateRange(let fId, let from, let to):
                    guard case .date(let d) = rec.values[fId] else { return false }
                    if let from, d < from { return false }
                    if let to, to < d { return false }
                }
            }
            return true
        }

        return filtered.sorted { a, b in
            switch query.sort {
            case .updatedAtDescending: return a.updatedAt > b.updatedAt
            case .updatedAtAscending: return a.updatedAt < b.updatedAt
            case .createdAtDescending: return a.createdAt > b.createdAt
            case .titleAscending:
                let sa = schema(for: a.collectionId)
                let sb = schema(for: b.collectionId)
                return (sa.map { a.title(using: $0) } ?? "") < (sb.map { b.title(using: $0) } ?? "")
            case .titleDescending:
                let sa = schema(for: a.collectionId)
                let sb = schema(for: b.collectionId)
                return (sa.map { a.title(using: $0) } ?? "") > (sb.map { b.title(using: $0) } ?? "")
            case .fieldAscending(let fId):
                return (a.values[fId]?.plainTextSummary() ?? "") < (b.values[fId]?.plainTextSummary() ?? "")
            case .fieldDescending(let fId):
                return (a.values[fId]?.plainTextSummary() ?? "") > (b.values[fId]?.plainTextSummary() ?? "")
            }
        }
    }

    // MARK: - Portable Archive Export & Staged Restore

    public func exportCurrentSpaceArchive(passphrase: String?) async throws -> URL {
        guard let space = currentSpace else {
            throw ArchiveError.corruptedArchive("No active Space selected.")
        }
        let store = await spaceStore(for: space.id)
        let exportsDir = rootDirectoryURL.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: exportsDir, withIntermediateDirectories: true)
        let url = try await ArchiveService.exportSpace(
            space: space,
            store: store,
            destinationDirectory: exportsDir,
            encryptionPassphrase: passphrase
        )
        if !exportedArchiveURLs.contains(url) {
            exportedArchiveURLs.insert(url, at: 0)
        }
        return url
    }

    public func restoreSpaceArchive(from url: URL, passphrase: String?) async throws -> SpaceMetadata {
        let restored = try await ArchiveService.restoreArchiveAsNewSpace(
            from: url,
            passphrase: passphrase,
            into: catalogStore,
            spacesRootDirectory: rootDirectoryURL,
            duplicateHandling: .restoreAsNewSpaceWithFreshIdentity
        )
        spaces = await catalogStore.listSpaces()
        await reloadSpaceFromDisk(restored.id)
        currentSpaceId = restored.id
        return restored
    }

    // MARK: - Sync, Conflicts, Devices & Storage Migration

    public func synchronizeCurrentSpaceNow() async {
        guard !isOfflineSimulated, let space = currentSpace, space.storageMode == .arcaSync else { return }
        let store = await spaceStore(for: space.id)
        let keyRing = spaceKeyRings[space.id] ?? SpaceKeyRing(spaceId: space.id)
        spaceKeyRings[space.id] = keyRing

        let coordinator = SyncCoordinator(
            accountId: accountId,
            deviceIdentity: currentDeviceIdentity,
            masterAccountKey: masterAccountKey,
            backend: syncBackend
        )
        await coordinator.registerSpaceKeyRing(keyRing)
        _ = try? await coordinator.synchronizeSpaceStore(
            store,
            spaceMode: space.storageMode
        )
        await reloadSpaceFromDisk(space.id)
    }

    public func simulateConcurrentConflict() {
        guard let rec = recordsInCurrentSpace.first, let col = schema(for: rec.collectionId) else { return }
        var remoteCopy = rec
        remoteCopy.revision = rec.revision + 1
        remoteCopy.lastModifiedByDeviceId = "dev-secondary-ipad"
        if let primaryField = col.primaryTitleField {
            remoteCopy.values[primaryField.id] = .shortText("\(rec.title(using: col)) (Edited on Secondary Device)")
        }
        let item = ConflictSummaryItem(
            id: UUID(),
            recordId: rec.id,
            localRecord: rec,
            remoteRecord: remoteCopy,
            conflictingFieldIds: col.primaryTitleField.map { [$0.id] } ?? [],
            summary: col.name
        )
        syncConflicts.append(item)
        bannerState = .syncConflictsDetected(count: syncConflicts.count)
    }

    public func resolveConflict(_ conflictId: UUID, keepLocal: Bool) async {
        guard let idx = syncConflicts.firstIndex(where: { $0.id == conflictId }) else { return }
        let conflict = syncConflicts.remove(at: idx)
        var chosen = keepLocal ? conflict.localRecord : conflict.remoteRecord
        chosen.revision = max(conflict.localRecord.revision, conflict.remoteRecord.revision) + 1
        chosen.updatedAt = Date()
        if let col = schema(for: chosen.collectionId) {
            let store = await spaceStore(for: chosen.spaceId)
            try? await store.saveRecord(chosen, schema: col, enqueueSync: currentSpace?.storageMode == .arcaSync)
            await reloadSpaceFromDisk(chosen.spaceId)
        }
        bannerState = syncConflicts.isEmpty ? .normal : .syncConflictsDetected(count: syncConflicts.count)
    }

    public func enrollSimulatedDevice(name: String) async throws {
        if enrolledDevices.count >= maxAllowedDevices {
            bannerState = .thirdDeviceLimitBlocked
            throw NSError(
                domain: "ArcaSync",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "Free plan allows up to \(maxAllowedDevices) active synced devices. Revoke an older device or upgrade to Arca Pro. Your local records remain completely untouched."]
            )
        }
        let devId = "dev-\(UUID().uuidString.prefix(8))"
        enrolledDevices.append(DeviceSummaryItem(
            deviceId: devId,
            deviceName: name,
            enrolledAt: Date(),
            isCurrentDevice: false
        ))
    }

    public func revokeDevice(deviceId: String) async {
        enrolledDevices.removeAll { $0.deviceId == deviceId && !$0.isCurrentDevice }
        for (spaceId, ring) in spaceKeyRings {
            spaceKeyRings[spaceId] = ring.rotated()
        }
        if case .thirdDeviceLimitBlocked = bannerState, enrolledDevices.count <= maxAllowedDevices {
            bannerState = .normal
        }
    }

    public func computeStorageMigrationPreview(
        for space: SpaceMetadata,
        to targetMode: SpaceStorageMode,
        deleteRemoteVerified: Bool
    ) -> StorageModeMigrationPreview {
        let recs = recordsBySpace[space.id] ?? []
        return StorageModeMigrationPreview.compute(
            for: space,
            to: targetMode,
            records: recs,
            remoteDeletionVerified: deleteRemoteVerified
        )
    }

    public func applyStorageModeChange(
        spaceId: UUID,
        to targetMode: SpaceStorageMode,
        deleteRemoteCopies: Bool
    ) async {
        if deleteRemoteCopies {
            _ = try? await syncBackend.deleteRemoteSpaceData(
                accountId: accountId,
                spaceId: spaceId,
                requestedByDeviceId: currentDeviceIdentity.deviceId
            )
        }
        _ = await catalogStore.updateStorageMode(
            id: spaceId,
            mode: targetMode,
            acceptedCloudSyncAt: targetMode == .arcaSync ? Date() : nil,
            provider: targetMode == .personalCloudBackup ? .iCloudDrive : nil
        )
        spaces = await catalogStore.listSpaces()
    }

    // MARK: - Billing & Subscription

    public func purchaseProSubscription(annual: Bool) async {
        let productId = annual
            ? ArcaCommercialConfig.annualProductID
            : ArcaCommercialConfig.monthlyProductID
        _ = try? await billingManager.purchase(productId: productId)
        isProSubscriber = billingManager.currentTier == .pro
        if case .thirdDeviceLimitBlocked = bannerState {
            bannerState = .normal
        }
    }

    public func simulateSubscriptionExpiry() async {
        billingManager.injectDeterministicState(
            tier: .free,
            state: .expired,
            activeProductId: ArcaCommercialConfig.annualProductID
        )
        isProSubscriber = false
        if enrolledDevices.count > ArcaCommercialConfig.freeMaxActiveDevices {
            bannerState = .thirdDeviceLimitBlocked
        }
    }

    public func restorePurchases() async {
        _ = try? await billingManager.restorePurchases(performStoreSync: false)
        isProSubscriber = billingManager.currentTier == .pro
    }

    // MARK: - Public Snapshot & Biometrics

    public func createPublicSnapshot(
        for record: RecordItem,
        schema: CollectionSchema,
        selectedFieldIds: Set<UUID>
    ) {
        let pairs: [(label: String, formattedValue: String)] = schema.activeFields
            .filter { selectedFieldIds.contains($0.id) }
            .map { field in
                let val = (record.values[field.id] ?? .null).plainTextSummary(for: field, locale: language.locale)
                return (field.label, val)
            }
        let snapshot = PublicRecordSnapshot(
            sourceRecordId: record.id,
            title: record.title(using: schema),
            selectedFieldPairs: pairs
        )
        publicSnapshots.append(snapshot)
    }

    public func unlockAppWithBiometrics() {
        isAppLocked = false
    }

    public func handleBannerAction() {
        switch bannerState {
        case .permissionDenied, .restoreValidationFailed:
            bannerState = .normal
        case .failedUpload:
            bannerState = .normal
        default:
            break
        }
    }
}
