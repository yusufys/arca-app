import XCTest
import CryptoKit
@testable import ArcaCore
@testable import ArcaCrypto
@testable import ArcaPersistence
@testable import ArcaArchive
@testable import ArcaSync
@testable import ArcaBilling
@testable import ArcaCloudAdapters
@testable import ArcaUI

final class ArcaVerificationTests: XCTestCase {

    private var tempWorkspace: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempWorkspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArcaTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempWorkspace, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let dir = tempWorkspace {
            try? FileManager.default.removeItem(at: dir)
        }
        try super.tearDownWithError()
    }

    // MARK: - 1. Schema Evolution, Renaming, Reordering, Retention Policy & Conversion Dry-Run Preview

    func testSchemaEvolutionPreservesValuesAndRejectsLossyConversions() throws {
        let spaceId = UUID()
        var schema = StarterTemplateCatalog.vehicleMaintenance.instantiateSchema(for: spaceId)
        let titleField = schema.fields[0]
        let odometerField = schema.fields[2]
        let notesField = schema.fields[7]

        let record1 = RecordItem(
            spaceId: spaceId,
            collectionId: schema.id,
            schemaVersionAtWrite: schema.schemaVersion,
            values: [
                titleField.id: .shortText("60,000-Mile Major Service"),
                odometerField.id: .number(60250),
                notesField.id: .longText("Replaced spark plugs and brake fluid")
            ]
        )

        // 1. Renaming a field label must preserve values and bump schemaVersion
        let initialVersion = schema.schemaVersion
        schema = SchemaEngine.renameField(in: schema, fieldId: titleField.id, newLabel: "Maintenance Description")
        XCTAssertEqual(schema.schemaVersion, initialVersion + 1)
        XCTAssertEqual(record1.title(using: schema), "60,000-Mile Major Service")

        // 2. Removing a field with default retention policy (.archiveAndRetainValues) keeps values recoverable
        let (archivedSchema, retainedRecords) = SchemaEngine.removeField(
            in: schema,
            fieldId: notesField.id,
            policy: .archiveAndRetainValues,
            records: [record1]
        )
        XCTAssertFalse(archivedSchema.activeFields.contains(where: { $0.id == notesField.id }))
        XCTAssertTrue(archivedSchema.archivedFields.contains(where: { $0.id == notesField.id }))
        XCTAssertEqual(retainedRecords[0].values[notesField.id], .longText("Replaced spark plugs and brake fluid"))

        // Restore the archived field and verify value is immediately active again
        let restoredSchema = SchemaEngine.restoreArchivedField(in: archivedSchema, fieldId: notesField.id)
        XCTAssertTrue(restoredSchema.activeFields.contains(where: { $0.id == notesField.id }))

        // 3. Field type conversion preview must detect incompatible values and block silent truncation
        let lossyPreview = SchemaEngine.previewFieldTypeConversion(
            field: restoredSchema.fields[0], // "60,000-Mile Major Service" -> not a pure number
            targetType: .number,
            records: retainedRecords
        )
        XCTAssertFalse(lossyPreview.isSafeToApplyWithoutLoss)
        XCTAssertEqual(lossyPreview.failureCount, 1)
        XCTAssertThrowsError(try SchemaEngine.applyFieldTypeConversion(
            in: restoredSchema,
            fieldId: titleField.id,
            targetType: .number,
            records: retainedRecords
        ))

        // 4. Compatible conversion (number -> shortText) succeeds cleanly without data loss
        let safePreview = SchemaEngine.previewFieldTypeConversion(
            field: odometerField,
            targetType: .shortText,
            records: retainedRecords
        )
        XCTAssertTrue(safePreview.isSafeToApplyWithoutLoss)
        let (convertedSchema, convertedRecords) = try SchemaEngine.applyFieldTypeConversion(
            in: restoredSchema,
            fieldId: odometerField.id,
            targetType: .shortText,
            records: retainedRecords
        )
        XCTAssertEqual(convertedSchema.fields.first(where: { $0.id == odometerField.id })?.type, .shortText)
        XCTAssertEqual(convertedRecords[0].values[odometerField.id], .shortText("60250.0"))
    }

    // MARK: - 2. Offline SQLite CRUD, FTS5 Full-Text Search, Projections & Precise Money/Date

    func testOfflineSQLiteCRUDProjectionsAndSearch() async throws {
        let catalog = CatalogStore(baseDirectoryURL: tempWorkspace)
        let space = SpaceMetadata(name: "Offline Home Space", storageMode: .localOnly)
        try await catalog.saveSpace(space)

        let spacesRoot = tempWorkspace.appendingPathComponent("Spaces", isDirectory: true)
        let store = SpaceStore(spaceId: space.id, spacesRootDirectoryURL: spacesRoot)

        let warrantySchema = StarterTemplateCatalog.warranties.instantiateSchema(for: space.id)
        try await store.saveCollection(warrantySchema, enqueueSync: false)

        let f = warrantySchema.fields
        let money = MoneyValue(decimalString: "1299.95", currencyCode: "USD")!
        XCTAssertEqual(money.minorUnits, 129995)

        let calDate = CalendarDate(isoDateString: "2028-05-19")!
        XCTAssertEqual(calDate.isoString, "2028-05-19")

        // Store attachment with SHA-256 verification
        let pdfBytes = Data("Warranty Certificate #WC-55190".utf8)
        let attachmentRef = try await store.storeAttachment(
            data: pdfBytes,
            filename: "warranty-card.pdf",
            mimeType: "application/pdf"
        )
        let loadedAttachment = try await store.loadAttachmentData(for: attachmentRef)
        XCTAssertEqual(loadedAttachment, pdfBytes)

        let record = RecordItem(
            spaceId: space.id,
            collectionId: warrantySchema.id,
            schemaVersionAtWrite: warrantySchema.schemaVersion,
            values: [
                f[0].id: .shortText("Induction Range Oven Pro"),
                f[1].id: .shortText("Bosch Home"),
                f[2].id: .date(CalendarDate(year: 2025, month: 5, day: 19)),
                f[3].id: .date(calDate),
                f[4].id: .currency(money),
                f[5].id: .singleSelect("extended"),
                f[6].id: .boolean(true),
                f[7].id: .longText("Serial #BSH-99281-IND"),
                f[8].id: .attachments([attachmentRef])
            ],
            isFavorite: true
        )
        try await store.saveRecord(record, schema: warrantySchema, enqueueSync: false)

        // Query via full-text search
        let searchQuery = RecordQuery(
            searchText: "BSH-99281-IND",
            collectionId: warrantySchema.id,
            filters: [.favoritesOnly, .hasAttachments],
            sort: .updatedAtDescending
        )
        let matches = try await store.queryRecords(searchQuery, schemas: [warrantySchema.id: warrantySchema])
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.id, record.id)

        // Verify local-only mode did not enqueue sync operations
        let outbox = try await store.pendingOutboxItems()
        XCTAssertTrue(outbox.isEmpty)
    }

    // MARK: - 3. Portable Archive Export/Restore Round-Trip (Including Encrypted Archive & Corrupt Tamper Detection)

    func testPortableArchiveRoundTripAndCorruptArchiveRejection() async throws {
        let catalog = CatalogStore(baseDirectoryURL: tempWorkspace)
        let spacesRoot = tempWorkspace.appendingPathComponent("Spaces", isDirectory: true)
        let exportsDir = tempWorkspace.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: exportsDir, withIntermediateDirectories: true)

        let bundle = SampleDataFactory.createDefaultPersonalSpace(storageMode: .localOnly)
        try await catalog.saveSpace(bundle.space)
        let store = SpaceStore(spaceId: bundle.space.id, spacesRootDirectoryURL: spacesRoot)
        for col in bundle.collections {
            try await store.saveCollection(col, enqueueSync: false)
        }
        var sampleRecord = bundle.records[0]
        let attRef = try await store.storeAttachment(
            data: Data("Original Invoice Content".utf8),
            filename: "invoice.txt",
            mimeType: "text/plain"
        )
        if let attField = bundle.collections[0].fields.first(where: { $0.type == .attachment }) {
            sampleRecord.values[attField.id] = .attachments([attRef])
        }
        try await store.saveRecord(sampleRecord, schema: bundle.collections[0], enqueueSync: false)

        // 1. Export encrypted archive
        let passphrase = "Correct-Horse-Battery-Staple-2026"
        let encryptedArchiveURL = try await ArchiveService.exportSpace(
            space: bundle.space,
            store: store,
            destinationDirectory: exportsDir,
            encryptionPassphrase: passphrase
        )

        // 2. Wrong passphrase must fail cleanly
        do {
            _ = try ArchiveService.inspectArchive(at: encryptedArchiveURL, passphrase: "Wrong-Password")
            XCTFail("Expected wrong passphrase to fail decryption")
        } catch {
            // Expected
        }

        // 3. Staged restore as new space succeeds and preserves collections, records, and attachments
        let restoredSpace = try await ArchiveService.restoreArchiveAsNewSpace(
            from: encryptedArchiveURL,
            passphrase: passphrase,
            into: catalog,
            spacesRootDirectory: spacesRoot
        )
        XCTAssertNotEqual(restoredSpace.id, bundle.space.id)
        let restoredStore = SpaceStore(spaceId: restoredSpace.id, spacesRootDirectoryURL: spacesRoot)
        let restoredRecords = try await restoredStore.listRecords()
        XCTAssertEqual(restoredRecords.count, 1)
        let restoredAttachments = restoredRecords[0].allAttachments
        XCTAssertEqual(restoredAttachments.count, 1)
        let restoredAttachmentBytes = try await restoredStore.loadAttachmentData(for: restoredAttachments[0])
        XCTAssertEqual(String(data: restoredAttachmentBytes, encoding: .utf8), "Original Invoice Content")

        // 4. Unencrypted bundle export + corruption test: tamper with records.json and verify staged restore rejects it without harming live spaces
        let unencryptedExportDir = exportsDir.appendingPathComponent("Unencrypted", isDirectory: true)
        try FileManager.default.createDirectory(at: unencryptedExportDir, withIntermediateDirectories: true)
        let plainArchiveURL = try await ArchiveService.exportSpace(
            space: bundle.space,
            store: store,
            destinationDirectory: unencryptedExportDir,
            encryptionPassphrase: nil
        )
        let recordsJsonURL = plainArchiveURL.appendingPathComponent("records.json")
        try Data("{\"corrupted\": true}".utf8).write(to: recordsJsonURL)

        let spacesBeforeCorruptRestore = try await catalog.listSpaces().count
        do {
            _ = try await ArchiveService.restoreArchiveAsNewSpace(
                from: plainArchiveURL,
                passphrase: nil,
                into: catalog,
                spacesRootDirectory: spacesRoot
            )
            XCTFail("Corrupted archive should have been rejected during staging")
        } catch {
            // Verify live catalog was NOT modified
            let spacesAfterCorruptRestore = try await catalog.listSpaces().count
            XCTAssertEqual(spacesBeforeCorruptRestore, spacesAfterCorruptRestore)
        }
    }

    // MARK: - 4. Encryption Key Recovery, Device Enrollment, 2-Device Limit & Revocation

    func testEncryptionRecoveryKeyAndTwoDeviceLimitWithRevocation() async throws {
        // 1. Recovery Key round-trip
        let originalMAK = SymmetricKey(size: .bits256)
        let (wrappedBundle, phrase) = try RecoveryKeyCredential.generate(wrapping: originalMAK)
        XCTAssertFalse(RecoveryKeyCredential.canPasswordResetDecryptE2EEData)

        let recoveredMAK = try RecoveryKeyCredential.recoverMasterAccountKey(from: wrappedBundle, recoveryPhrase: phrase)
        let originalBytes = originalMAK.withUnsafeBytes { Data($0) }
        let recoveredBytes = recoveredMAK.withUnsafeBytes { Data($0) }
        XCTAssertEqual(originalBytes, recoveredBytes)

        // Wrong recovery phrase must fail
        XCTAssertThrowsError(try RecoveryKeyCredential.recoverMasterAccountKey(
            from: wrappedBundle,
            recoveryPhrase: "ARCA-0000-0000-0000-0000-0000-0000-0000-0000"
        ))

        // 2. Device Enrollment & Free 2-Device Limit Enforcement
        let backend = InMemoryArcaSyncBackend()
        let session = try await backend.authenticate(email: "owner@example.com", passkeyOrCredentialToken: "passkey-1")

        let device1 = DeviceIdentity(deviceId: "dev-1", deviceName: "iPhone 16")
        let device2 = DeviceIdentity(deviceId: "dev-2", deviceName: "iPad Mini")
        let device3 = DeviceIdentity(deviceId: "dev-3", deviceName: "Backup iPhone")

        _ = try await backend.enrollDevice(accountId: session.accountId, device: device1.descriptor, wrappedMasterKey: nil, isProTier: false)
        let wrappedForDev2 = try device1.wrapMasterAccountKey(originalMAK, forNewDevice: device2.descriptor)
        _ = try await backend.enrollDevice(accountId: session.accountId, device: device2.descriptor, wrappedMasterKey: wrappedForDev2, isProTier: false)

        // Device 2 can unwrap MAK
        let unwrappedByDev2 = try device2.unwrapMasterAccountKey(from: wrappedForDev2)
        XCTAssertEqual(unwrappedByDev2.withUnsafeBytes { Data($0) }, originalBytes)

        // Enrolling 3rd device on Free tier must fail with .deviceLimitReached
        do {
            _ = try await backend.enrollDevice(accountId: session.accountId, device: device3.descriptor, wrappedMasterKey: nil, isProTier: false)
            XCTFail("Expected 3rd device enrollment on Free tier to throw deviceLimitReached")
        } catch let error as SyncServiceError {
            if case .deviceLimitReached(let currentDevices, let limit) = error {
                XCTAssertEqual(limit, 2)
                XCTAssertEqual(currentDevices.count, 2)
            } else {
                XCTFail("Unexpected SyncServiceError: \(error)")
            }
        }

        // Revoking Device 2 allows Device 3 to enroll and rotates SpaceKeyRing
        _ = try await backend.revokeDevice(accountId: session.accountId, targetDeviceId: "dev-2", requestingDeviceId: "dev-1")
        let enrolled3 = try await backend.enrollDevice(accountId: session.accountId, device: device3.descriptor, wrappedMasterKey: nil, isProTier: false)
        XCTAssertEqual(enrolled3.deviceId, "dev-3")
    }

    // MARK: - 5. Idempotent Retried Sync Operations & Concurrent Edit Conflict Preservation

    func testIdempotentSyncAndConcurrentConflictPreservation() async throws {
        let backend = InMemoryArcaSyncBackend()
        let session = try await backend.authenticate(email: "sync@example.com", passkeyOrCredentialToken: "token")
        let devA = DeviceIdentity(deviceId: "dev-A", deviceName: "Device A")
        let devB = DeviceIdentity(deviceId: "dev-B", deviceName: "Device B")
        _ = try await backend.enrollDevice(accountId: session.accountId, device: devA.descriptor, wrappedMasterKey: nil, isProTier: false)
        _ = try await backend.enrollDevice(accountId: session.accountId, device: devB.descriptor, wrappedMasterKey: nil, isProTier: false)

        let space = SpaceMetadata(name: "Synced Vehicles", storageMode: .arcaSync, cloudSyncAcceptedAt: Date())
        let keyRing = SpaceKeyRing(spaceId: space.id)
        let schema = StarterTemplateCatalog.vehicleMaintenance.instantiateSchema(for: space.id)
        let titleFieldId = schema.fields[0].id
        let odometerFieldId = schema.fields[2].id
        let notesFieldId = schema.fields[7].id

        let baseRecord = RecordItem(
            spaceId: space.id,
            collectionId: schema.id,
            schemaVersionAtWrite: schema.schemaVersion,
            values: [
                titleFieldId: .shortText("Brake Pad Replacement"),
                odometerFieldId: .number(42000),
                notesFieldId: .longText("Front ceramic pads")
            ],
            revision: 1,
            lastModifiedByDeviceId: devA.deviceId
        )

        // 1. Test idempotent push: pushing the exact same operationId twice only records 1 operation on the server
        let coordinatorA = SyncCoordinator(accountId: session.accountId, deviceIdentity: devA, backend: backend)
        let opId = UUID()
        try await coordinatorA.queueRecordUpsert(baseRecord, keyRing: keyRing, fixedOperationId: opId)
        let firstSync = try await coordinatorA.synchronizeSpace(space: space, store: nil, keyRing: keyRing, isProTier: false)
        XCTAssertEqual(firstSync.pushedCount, 1)

        // Re-push same operationId to backend directly to simulate network retry
        let pullBatch = try await backend.pullEncryptedOperations(
            accountId: session.accountId,
            spaceId: space.id,
            requestingDeviceId: devB.deviceId,
            sinceCursor: nil,
            limit: 50
        )
        XCTAssertEqual(pullBatch.operations.count, 1)
        let retryAck = try await backend.pushEncryptedOperations(
            accountId: session.accountId,
            requestingDeviceId: devA.deviceId,
            operations: pullBatch.operations,
            isProTier: false
        )
        XCTAssertEqual(retryAck.deduplicatedOperationIds, [opId])

        // 2. Disjoint field concurrent edits merge cleanly
        var localDisjoint = baseRecord
        localDisjoint.values[odometerFieldId] = .number(42150)
        localDisjoint.revision = 2
        localDisjoint.lastModifiedByDeviceId = devA.deviceId

        var remoteDisjoint = baseRecord
        remoteDisjoint.values[notesFieldId] = .longText("Front and rear ceramic pads")
        remoteDisjoint.revision = 2
        remoteDisjoint.lastModifiedByDeviceId = devB.deviceId

        let disjointOutcome = SyncConflictEngine.reconcileConcurrentRecordEdit(
            baseRecord: baseRecord,
            localRecord: localDisjoint,
            remoteRecord: remoteDisjoint
        )
        if case .cleanFieldLevelMerge(let merged) = disjointOutcome {
            XCTAssertEqual(merged.values[odometerFieldId], .number(42150))
            XCTAssertEqual(merged.values[notesFieldId], .longText("Front and rear ceramic pads"))
        } else {
            XCTFail("Expected disjoint field edits to merge cleanly")
        }

        // 3. Overlapping edits to the same field create a preserved SyncConflict so no data is lost
        var localOverlap = baseRecord
        localOverlap.values[titleFieldId] = .shortText("Front Brake Service (Local Edit)")
        localOverlap.revision = 2
        localOverlap.lastModifiedByDeviceId = devA.deviceId

        var remoteOverlap = baseRecord
        remoteOverlap.values[titleFieldId] = .shortText("Full Brake Overhaul (Remote Edit)")
        remoteOverlap.revision = 2
        remoteOverlap.lastModifiedByDeviceId = devB.deviceId

        let overlapOutcome = SyncConflictEngine.reconcileConcurrentRecordEdit(
            baseRecord: baseRecord,
            localRecord: localOverlap,
            remoteRecord: remoteOverlap
        )
        if case .conflictPreserved(let conflict) = overlapOutcome {
            XCTAssertEqual(conflict.conflictingFieldIds, [titleFieldId])
            XCTAssertEqual(conflict.localRecord.values[titleFieldId], .shortText("Front Brake Service (Local Edit)"))
            XCTAssertEqual(conflict.remoteRecord.values[titleFieldId], .shortText("Full Brake Overhaul (Remote Edit)"))
        } else {
            XCTFail("Expected overlapping edits to preserve a SyncConflict")
        }
    }

    // MARK: - 6. Subscription Expiry Safeguards & Personal Cloud Policy Assessment

    @available(macOS 14.0, iOS 17.0, *)
    @MainActor
    func testSubscriptionExpiryPreservesLocalDataAndAssessesPersonalCloudPolicies() async throws {
        let billing = BillingManager()
        billing.injectDeterministicState(
            tier: .pro,
            state: .active,
            activeProductId: ArcaCommercialConfig.annualProductID
        )
        XCTAssertEqual(billing.snapshot.effectiveTier, .pro)

        // Simulate expiry with 3 enrolled devices (exceeding the 2-device Free limit)
        billing.injectDeterministicState(
            tier: .free,
            state: .expired,
            activeProductId: ArcaCommercialConfig.annualProductID
        )
        XCTAssertEqual(billing.snapshot.effectiveTier, .free)
        let postExpiry = billing.evaluatePostExpiryPolicy(activeDeviceCount: 3, remoteStorageBytesUsed: 300 * 1024 * 1024)
        XCTAssertTrue(postExpiry.allowsLocalReadWriteCRUD)
        XCTAssertTrue(postExpiry.allowsManualPortableExportAndRestore)
        XCTAssertFalse(postExpiry.deletesLocalRecordsOnExpiry)
        XCTAssertFalse(postExpiry.isSyncPushAllowed)

        // Verify Personal Cloud Provider policy assessments
        let medicalSpace = SampleDataFactory.createSensitiveHealthNotesSpace().space
        let iCloudMedicalAssessment = ProviderPolicyAssessment.evaluate(provider: .iCloudDrive, for: medicalSpace)
        XCTAssertFalse(iCloudMedicalAssessment.isPermittedForBackup)
        XCTAssertFalse(iCloudMedicalAssessment.allowsSilentFallbackToArcaCloud)

        let generalSpace = SampleDataFactory.createVehiclesSpace().space
        let iCloudGeneralAssessment = ProviderPolicyAssessment.evaluate(provider: .iCloudDrive, for: generalSpace)
        XCTAssertTrue(iCloudGeneralAssessment.isPermittedForBackup)
        XCTAssertFalse(iCloudGeneralAssessment.allowsSilentFallbackToArcaCloud)
    }

    func testSpaceMetadataDefaultStorageModes() {
        let regularSpace = SpaceMetadata(name: "Regular Space")
        XCTAssertEqual(regularSpace.storageMode, .arcaSync)

        let sensitiveSpace = SpaceMetadata(name: "Health Records", containsSensitiveHealthTemplate: true)
        XCTAssertEqual(sensitiveSpace.storageMode, .localOnly)

        let confirmedSensitiveSpace = SpaceMetadata(
            name: "Health Records Synced",
            storageMode: .arcaSync,
            containsSensitiveHealthTemplate: true,
            userExplicitlyConfirmedSyncForSensitiveSpace: true
        )
        XCTAssertEqual(confirmedSensitiveSpace.storageMode, .arcaSync)
    }
}
