import Foundation
import CryptoKit
import ArcaCore
import ArcaCrypto
import ArcaPersistence
import ArcaArchive
import ArcaSync
import ArcaBilling
import ArcaCloudAdapters
import ArcaUI

struct VerificationFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String, file: String = #fileID, line: Int = #line) {
        self.description = "\(file):\(line) — \(description)"
    }
}

func check(_ condition: @autoclosure () -> Bool, _ message: String, file: String = #fileID, line: Int = #line) throws {
    if !condition() {
        throw VerificationFailure(message, file: file, line: line)
    }
}

func checkEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String = "", file: String = #fileID, line: Int = #line) throws {
    if lhs != rhs {
        throw VerificationFailure("Expected \(lhs) == \(rhs). \(message)", file: file, line: line)
    }
}

@available(macOS 14.0, iOS 17.0, *)
enum ArcaVerificationSuite {

    static func runAll() async throws {
        print("====================================================")
        print("Arca Stage 1–7 Comprehensive Verification Suite")
        print("====================================================")

        try await verify1_SchemaEvolutionAndValuePreservation()
        try await verify2_OfflineSQLiteCRUDProjectionsAndFTS5Search()
        try await verify3_PortableArchiveRoundTripAndCorruptTamperRejection()
        try await verify4_EncryptionKeyRecoveryAndFailureBehavior()
        try await verify5_DeviceLimitEnforcementAndRevocationWithKeyRotation()
        try await verify6_IdempotentRetriedSyncAndConcurrentEditConflicts()
        try await verify7_SubscriptionExpiryWithoutLocalDataLoss()
        try await verify8_PersonalCloudPolicyVerificationAndNoSilentFallback()
        try await verify9_EndToEndViewModelAndLocalizationJourneys()

        print("====================================================")
        print("ALL 9 VERIFICATION SUITES PASSED (0 FAILURES)")
        print("====================================================")
    }

    // MARK: 1. Schema Evolution, Value Preservation, Retention Policy & Conversion Preview
    static func verify1_SchemaEvolutionAndValuePreservation() async throws {
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

        // Rename field label -> preserves values and increments schemaVersion
        let initialVersion = schema.schemaVersion
        schema = SchemaEngine.renameField(in: schema, fieldId: titleField.id, newLabel: "Maintenance Description")
        try checkEqual(schema.schemaVersion, initialVersion + 1, "Schema version should increment on field rename")
        try checkEqual(record1.title(using: schema), "60,000-Mile Major Service", "Record value must be preserved when field label is renamed")

        // Archive field -> retains historical values
        let (archivedSchema, retainedRecords) = SchemaEngine.removeField(
            in: schema,
            fieldId: notesField.id,
            policy: .archiveAndRetainValues,
            records: [record1]
        )
        try check(!archivedSchema.activeFields.contains(where: { $0.id == notesField.id }), "Archived field should not be in activeFields")
        try check(archivedSchema.archivedFields.contains(where: { $0.id == notesField.id }), "Archived field must be in archivedFields")
        try checkEqual(retainedRecords[0].values[notesField.id], .longText("Replaced spark plugs and brake fluid"), "Historical value must be preserved on archive")

        // Restore archived field
        let restoredSchema = SchemaEngine.restoreArchivedField(in: archivedSchema, fieldId: notesField.id)
        try check(restoredSchema.activeFields.contains(where: { $0.id == notesField.id }), "Restored field must return to activeFields")

        // Lossy field type conversion must be detected and rejected
        let lossyPreview = SchemaEngine.previewFieldTypeConversion(
            field: restoredSchema.fields[0],
            targetType: .number,
            records: retainedRecords
        )
        try check(!lossyPreview.isSafeToApplyWithoutLoss, "Non-numeric shortText should fail conversion preview to .number")
        try checkEqual(lossyPreview.failureCount, 1)

        var threwLossyError = false
        do {
            _ = try SchemaEngine.applyFieldTypeConversion(
                in: restoredSchema,
                fieldId: titleField.id,
                targetType: .number,
                records: retainedRecords
            )
        } catch {
            threwLossyError = true
        }
        try check(threwLossyError, "Applying lossy field conversion must throw SchemaMigrationError")

        // Compatible conversion (number -> shortText) succeeds cleanly
        let (convertedSchema, convertedRecords) = try SchemaEngine.applyFieldTypeConversion(
            in: restoredSchema,
            fieldId: odometerField.id,
            targetType: .shortText,
            records: retainedRecords
        )
        try checkEqual(convertedSchema.fields.first(where: { $0.id == odometerField.id })?.type, .shortText)
        try checkEqual(convertedRecords[0].values[odometerField.id], .shortText("60250.0"))
        print("[PASS] 1. Schema Evolution, Renaming, Retention & Conversion Dry-Run Preview")
    }

    // MARK: 2. Offline SQLite CRUD, Projections, Attachments & FTS5 Search
    static func verify2_OfflineSQLiteCRUDProjectionsAndFTS5Search() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ArcaVerify2-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let catalog = CatalogStore(baseDirectoryURL: tempDir)
        let space = SpaceMetadata(name: "Offline Home Space", storageMode: .localOnly)
        await catalog.saveSpace(space)

        let store = SpaceStore(spaceId: space.id, baseDirectoryURL: tempDir, isSensitiveLocal: true)
        let warrantySchema = StarterTemplateCatalog.warranties.instantiateSchema(for: space.id)
        await store.saveCollection(warrantySchema, enqueueSync: false)

        let f = warrantySchema.fields
        let money = MoneyValue(decimalString: "1299.95", currencyCode: "USD")!
        try checkEqual(money.minorUnits, 129995, "Exact minor units for $1299.95")

        let calDate = CalendarDate(isoDateString: "2028-05-19")!
        try checkEqual(calDate.isoString, "2028-05-19", "Timezone-independent CalendarDate")

        let pdfBytes = Data("Warranty Certificate #WC-55190".utf8)
        let attachmentRef = try await store.storeAttachment(
            data: pdfBytes,
            filename: "warranty-card.pdf",
            mimeType: "application/pdf"
        )
        let loadedAttachment = try await store.loadAttachmentData(for: attachmentRef)
        try checkEqual(loadedAttachment, pdfBytes, "Attachment SHA-256 round-trip")

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

        let searchQuery = RecordQuery(
            searchText: "BSH-99281-IND",
            collectionId: warrantySchema.id,
            filters: [.favoritesOnly, .hasAttachments],
            sort: .updatedAtDescending
        )
        let matches = await store.queryRecords(searchQuery, schemas: [warrantySchema.id: warrantySchema])
        try checkEqual(matches.count, 1, "FTS5 search and filter projection should return matching record")
        try checkEqual(matches.first?.id, record.id)

        let outbox = await store.pendingOutboxItems()
        try check(outbox.isEmpty, "Local-only space must not enqueue sync outbox items")
        print("[PASS] 2. Offline SQLite CRUD, FTS5 Full-Text Search, Projections & Attachments")
    }

    // MARK: 3. Portable Archive Export/Restore Round-Trip & Corrupt Archive Rejection
    static func verify3_PortableArchiveRoundTripAndCorruptTamperRejection() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ArcaVerify3-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let catalog = CatalogStore(baseDirectoryURL: tempDir)
        let exportsDir = tempDir.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: exportsDir, withIntermediateDirectories: true)

        let bundle = SampleDataFactory.createDefaultPersonalSpace(storageMode: .localOnly)
        await catalog.saveSpace(bundle.space)
        let store = SpaceStore(spaceId: bundle.space.id, baseDirectoryURL: tempDir)
        for col in bundle.collections {
            await store.saveCollection(col, enqueueSync: false)
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

        // Export encrypted archive
        let passphrase = "Correct-Horse-Battery-Staple-2026"
        let encryptedArchiveURL = try await ArchiveService.exportSpace(
            space: bundle.space,
            store: store,
            destinationDirectory: exportsDir,
            encryptionPassphrase: passphrase
        )

        // Wrong passphrase must fail
        var failedWrongPassphrase = false
        do {
            _ = try ArchiveService.inspectArchive(at: encryptedArchiveURL, passphrase: "Wrong-Password")
        } catch {
            failedWrongPassphrase = true
        }
        try check(failedWrongPassphrase, "Wrong passphrase must fail archive decryption")

        // Staged restore as new space
        let restoredSpace = try await ArchiveService.restoreArchiveAsNewSpace(
            from: encryptedArchiveURL,
            passphrase: passphrase,
            into: catalog,
            spacesRootDirectory: tempDir
        )
        try check(restoredSpace.id != bundle.space.id, "Default restore must create a new Space UUID")
        let restoredStore = SpaceStore(spaceId: restoredSpace.id, baseDirectoryURL: tempDir)
        let restoredRecords = await restoredStore.listRecords()
        try checkEqual(restoredRecords.count, 1)
        let restoredAttachments = restoredRecords[0].allAttachments
        try checkEqual(restoredAttachments.count, 1)
        let restoredBytes = try await restoredStore.loadAttachmentData(for: restoredAttachments[0])
        try checkEqual(String(data: restoredBytes, encoding: .utf8), "Original Invoice Content")

        // Corrupt archive rejection without modifying live spaces
        let unencryptedDir = exportsDir.appendingPathComponent("Plain", isDirectory: true)
        try FileManager.default.createDirectory(at: unencryptedDir, withIntermediateDirectories: true)
        let plainArchiveURL = try await ArchiveService.exportSpace(
            space: bundle.space,
            store: store,
            destinationDirectory: unencryptedDir,
            encryptionPassphrase: nil
        )
        try Data("{\"tampered\": true}".utf8).write(to: plainArchiveURL.appendingPathComponent("records.json"))

        let spacesCountBefore = await catalog.listSpaces().count
        var rejectedCorruptArchive = false
        do {
            _ = try await ArchiveService.restoreArchiveAsNewSpace(
                from: plainArchiveURL,
                passphrase: nil,
                into: catalog,
                spacesRootDirectory: tempDir
            )
        } catch {
            rejectedCorruptArchive = true
        }
        let spacesCountAfter = await catalog.listSpaces().count
        try check(rejectedCorruptArchive, "Tampered archive must be rejected during staging")
        try checkEqual(spacesCountBefore, spacesCountAfter, "Rejected restore must leave live spaces untouched")
        print("[PASS] 3. Portable Archive Export/Restore Round-Trip & Corrupt Archive Rejection")
    }

    // MARK: 4. Encryption Key Recovery & Failure Behavior
    static func verify4_EncryptionKeyRecoveryAndFailureBehavior() async throws {
        let originalMAK = SymmetricKey(size: .bits256)
        let makId = UUID()
        let credential = RecoveryKeyCredential.generate()
        try check(!RecoveryKeyCredential.canPasswordResetDecryptE2EEData, "Password reset must never claim ability to decrypt E2EE data")

        let wrappedBundle = try credential.wrapMasterAccountKey(originalMAK, makKeyId: makId, accountId: "acct-1")
        let recoveredMAK = try RecoveryKeyCredential.restoreMasterAccountKey(
            fromPhrase: credential.formattedPhrase,
            bundle: wrappedBundle
        )
        try checkEqual(
            originalMAK.withUnsafeBytes { Data($0) },
            recoveredMAK.withUnsafeBytes { Data($0) },
            "Recovered Master Account Key must match original 256-bit key"
        )

        var wrongPhraseFailed = false
        do {
            _ = try RecoveryKeyCredential.restoreMasterAccountKey(
                fromPhrase: "ARCA-0000-0000-0000-0000-0000-0000-0000-0000",
                bundle: wrappedBundle
            )
        } catch {
            wrongPhraseFailed = true
        }
        try check(wrongPhraseFailed, "Incorrect recovery key must fail authentication tag verification")
        print("[PASS] 4. Encryption Key Recovery & Failure Behavior")
    }

    // MARK: 5. Device Limits (2 Devices on Free) & Revocation with Key Rotation
    static func verify5_DeviceLimitEnforcementAndRevocationWithKeyRotation() async throws {
        let backend = InMemoryArcaSyncBackend()
        let session = try await backend.authenticate(
            email: "owner@example.com",
            credentialProof: "passkey-1",
            maxAllowedDevices: 2,
            storageQuotaBytes: ArcaCommercialConfig.freeCloudStorageQuotaBytes
        )

        let mak = SymmetricKey(size: .bits256)
        let makId = UUID()
        let dev1 = DeviceIdentity(deviceId: "dev-1", deviceName: "iPhone 16")
        let dev2 = DeviceIdentity(deviceId: "dev-2", deviceName: "iPad Mini")
        let dev3 = DeviceIdentity(deviceId: "dev-3", deviceName: "Third Device")

        _ = try await backend.enrollDevice(
            accountId: session.accountId,
            device: EnrolledDevice(descriptor: dev1.descriptor),
            maxAllowedDevices: 2,
            wrappedMasterKey: nil
        )

        let wrappedForDev2 = try dev1.wrapMasterAccountKey(mak, makKeyId: makId, forRecipient: dev2.descriptor)
        _ = try await backend.enrollDevice(
            accountId: session.accountId,
            device: EnrolledDevice(descriptor: dev2.descriptor),
            maxAllowedDevices: 2,
            wrappedMasterKey: wrappedForDev2
        )

        let unwrappedByDev2 = try dev2.unwrapMasterAccountKey(from: wrappedForDev2)
        try checkEqual(unwrappedByDev2.withUnsafeBytes { Data($0) }, mak.withUnsafeBytes { Data($0) })

        // 3rd device on Free tier must fail with .deviceLimitReached
        var hitTwoDeviceLimit = false
        do {
            _ = try await backend.enrollDevice(
                accountId: session.accountId,
                device: EnrolledDevice(descriptor: dev3.descriptor),
                maxAllowedDevices: 2,
                wrappedMasterKey: nil
            )
        } catch let err as SyncServiceError {
            if case .deviceLimitReached(let currentDevices, let limit) = err {
                try checkEqual(limit, 2)
                try checkEqual(currentDevices.count, 2)
                hitTwoDeviceLimit = true
            }
        }
        try check(hitTwoDeviceLimit, "Enrolling a 3rd device on Free account must throw SyncServiceError.deviceLimitReached")

        // Revoke dev-2 and rotate Space key
        let spaceRingGen1 = SpaceKeyRing(spaceId: UUID(), keyGeneration: 1)
        let rotationResult = try DeviceIdentity.rotateSpaceKey(
            currentKeyRing: spaceRingGen1,
            revokingDeviceId: "dev-2",
            masterAccountKey: mak,
            makKeyId: makId
        )
        try checkEqual(rotationResult.rotatedSpaceKeyRing.keyGeneration, 2)

        _ = try await backend.revokeDevice(
            accountId: session.accountId,
            revokingDeviceId: "dev-2",
            requestedByDeviceId: "dev-1",
            rotatedSpaceKeys: [rotationResult.wrappedSpaceKeyRing]
        )

        // Now dev-3 can enroll within the 2-device limit
        let enrolled3 = try await backend.enrollDevice(
            accountId: session.accountId,
            device: EnrolledDevice(descriptor: dev3.descriptor),
            maxAllowedDevices: 2,
            wrappedMasterKey: nil
        )
        try checkEqual(enrolled3.enrolledDevice.deviceId, "dev-3")
        print("[PASS] 5. Free 2-Device Limit Enforcement, Device Revocation & Space Key Rotation")
    }

    // MARK: 6. Duplicate/Retried Sync Operations & Concurrent Edit Conflict Preservation
    static func verify6_IdempotentRetriedSyncAndConcurrentEditConflicts() async throws {
        let backend = InMemoryArcaSyncBackend()
        let session = try await backend.authenticate(
            email: "sync@example.com",
            credentialProof: "token",
            maxAllowedDevices: 2,
            storageQuotaBytes: ArcaCommercialConfig.freeCloudStorageQuotaBytes
        )
        let mak = SymmetricKey(size: .bits256)
        let devA = DeviceIdentity(deviceId: "dev-A", deviceName: "Device A")
        let devB = DeviceIdentity(deviceId: "dev-B", deviceName: "Device B")

        _ = try await backend.enrollDevice(accountId: session.accountId, device: EnrolledDevice(descriptor: devA.descriptor), maxAllowedDevices: 2, wrappedMasterKey: nil)
        _ = try await backend.enrollDevice(accountId: session.accountId, device: EnrolledDevice(descriptor: devB.descriptor), maxAllowedDevices: 2, wrappedMasterKey: nil)

        let spaceId = UUID()
        let keyRing = SpaceKeyRing(spaceId: spaceId)
        let schema = StarterTemplateCatalog.vehicleMaintenance.instantiateSchema(for: spaceId)
        let titleFieldId = schema.fields[0].id
        let odometerFieldId = schema.fields[2].id
        let notesFieldId = schema.fields[7].id

        let baseRecord = RecordItem(
            spaceId: spaceId,
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

        // 1. Idempotent retried push
        let opId = UUID()
        let encryptedOp = try EncryptedSyncOperation.encryptRecordOperation(
            operationId: opId,
            record: baseRecord,
            baseRevision: 0,
            authorDeviceId: devA.deviceId,
            spaceKeyRing: keyRing
        )
        let firstReceipt = try await backend.pushEncryptedOperations(
            accountId: session.accountId,
            spaceId: spaceId,
            deviceId: devA.deviceId,
            operations: [encryptedOp]
        )
        try checkEqual(firstReceipt.acceptedOperationIds, [opId])

        let retryReceipt = try await backend.pushEncryptedOperations(
            accountId: session.accountId,
            spaceId: spaceId,
            deviceId: devA.deviceId,
            operations: [encryptedOp]
        )
        try checkEqual(retryReceipt.deduplicatedOperationIds, [opId], "Retried operationId must be deduplicated idempotently")

        // 2. Disjoint field concurrent edits merge cleanly
        var localDisjoint = baseRecord
        localDisjoint.values[odometerFieldId] = .number(42150)
        localDisjoint.revision = 2
        localDisjoint.lastModifiedByDeviceId = devA.deviceId

        var remoteDisjoint = baseRecord
        remoteDisjoint.values[notesFieldId] = .longText("Front and rear ceramic pads")
        remoteDisjoint.revision = 2
        remoteDisjoint.lastModifiedByDeviceId = devB.deviceId

        let disjointOutcome = SyncConflictEngine.reconcileRecord(
            localRecord: localDisjoint,
            remoteRecord: remoteDisjoint,
            baseRecordSnapshot: baseRecord,
            localBaseRevision: 1,
            hasUncommittedLocalEdits: true
        )
        if case .cleanFieldLevelMerge(let merged) = disjointOutcome {
            try checkEqual(merged.values[odometerFieldId], .number(42150))
            try checkEqual(merged.values[notesFieldId], .longText("Front and rear ceramic pads"))
        } else {
            throw VerificationFailure("Disjoint field edits must merge cleanly")
        }

        // 3. Overlapping edits to the same field preserve a SyncConflict
        var localOverlap = baseRecord
        localOverlap.values[titleFieldId] = .shortText("Front Brake Service (Local)")
        localOverlap.revision = 2
        localOverlap.lastModifiedByDeviceId = devA.deviceId

        var remoteOverlap = baseRecord
        remoteOverlap.values[titleFieldId] = .shortText("Full Brake Overhaul (Remote)")
        remoteOverlap.revision = 2
        remoteOverlap.lastModifiedByDeviceId = devB.deviceId

        let overlapOutcome = SyncConflictEngine.reconcileRecord(
            localRecord: localOverlap,
            remoteRecord: remoteOverlap,
            baseRecordSnapshot: baseRecord,
            localBaseRevision: 1,
            hasUncommittedLocalEdits: true
        )
        if case .conflictPreserved(let conflict) = overlapOutcome {
            try checkEqual(conflict.conflictingFieldIds, [titleFieldId])
            try checkEqual(conflict.localRecord.values[titleFieldId], .shortText("Front Brake Service (Local)"))
            try checkEqual(conflict.remoteRecord.values[titleFieldId], .shortText("Full Brake Overhaul (Remote)"))
        } else {
            throw VerificationFailure("Overlapping same-field concurrent edits must preserve a SyncConflict")
        }

        // 4. Edit vs. Delete conflict preservation
        var remoteDeleted = baseRecord
        remoteDeleted.isDeleted = true
        remoteDeleted.revision = 2
        remoteDeleted.lastModifiedByDeviceId = devB.deviceId

        let editVsDeleteOutcome = SyncConflictEngine.reconcileRecord(
            localRecord: localOverlap,
            remoteRecord: remoteDeleted,
            baseRecordSnapshot: baseRecord,
            localBaseRevision: 1,
            hasUncommittedLocalEdits: true
        )
        if case .conflictPreserved(let delConflict) = editVsDeleteOutcome {
            try check(delConflict.isEditVsDeleteConflict, "Edit vs Delete must be flagged and preserved")
        } else {
            throw VerificationFailure("Concurrent Edit vs Delete must preserve a SyncConflict")
        }

        _ = mak // keep reference
        print("[PASS] 6. Idempotent Retried Sync Operations & Concurrent Edit/Delete Conflict Preservation")
    }

    // MARK: 7. Subscription Expiry Without Local Data Loss
    @MainActor
    static func verify7_SubscriptionExpiryWithoutLocalDataLoss() async throws {
        let billing = BillingManager()
        billing.injectDeterministicState(
            tier: .pro,
            state: .active,
            activeProductId: ArcaCommercialConfig.annualProductID
        )
        try checkEqual(billing.currentTier, .pro)

        // Expire subscription while user has 3 devices and 300 MB remote data
        billing.injectDeterministicState(
            tier: .free,
            state: .expired,
            activeProductId: ArcaCommercialConfig.annualProductID
        )
        try checkEqual(billing.currentTier, .free)
        let policy = billing.evaluatePostExpiryPolicy(activeDeviceCount: 3, remoteStorageBytesUsed: 300 * 1024 * 1024)
        try check(policy.allowsLocalReadWriteCRUD, "Local read/write CRUD must remain active after subscription expiry")
        try check(policy.allowsManualPortableExportAndRestore, "Manual portable exports must remain active after subscription expiry")
        try check(!policy.deletesLocalRecordsOnExpiry, "Local records must NEVER be deleted on subscription expiry")
        try check(!policy.isSyncPushAllowed, "Cloud sync push should pause gracefully when over Free tier device/storage allowance")
        try check(!ArcaCommercialConfig.offersLifetimeCloudHostingCommitment, "Must not invent lifetime cloud hosting commitments")
        print("[PASS] 7. Subscription Expiry Safeguards Without Local Data Loss")
    }

    // MARK: 8. Personal Cloud Backup Policy Assessment & No Silent Fallback
    static func verify8_PersonalCloudPolicyVerificationAndNoSilentFallback() async throws {
        let medicalSpace = SampleDataFactory.createSensitiveHealthNotesSpace().space
        let iCloudMedical = ProviderPolicyAssessment.evaluate(provider: .iCloudDrive, for: medicalSpace)
        try check(!iCloudMedical.isPermittedForBackup, "Must not promise or permit automatic iCloud backup for sensitive health template space")
        try check(!iCloudMedical.allowsSilentFallbackToArcaCloud, "Must never silently fall back to Arca Cloud")

        let vehicleSpace = SampleDataFactory.createVehiclesSpace().space
        let iCloudGeneral = ProviderPolicyAssessment.evaluate(provider: .iCloudDrive, for: vehicleSpace)
        try check(iCloudGeneral.isPermittedForBackup, "General vehicle space is eligible for client-encrypted personal cloud backup after policy check")
        try check(!iCloudGeneral.allowsSilentFallbackToArcaCloud, "Must never silently fall back to Arca Cloud")
        print("[PASS] 8. Personal Cloud Backup Policy Assessment & Zero Silent Fallback")
    }

    // MARK: 9. ViewModel End-to-End Journeys & Localization Foundations (EN / AR RTL / TR)
    @MainActor
    static func verify9_EndToEndViewModelAndLocalizationJourneys() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ArcaVerify9-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let vm = ArcaAppViewModel(rootDirectoryURL: tempDir, startWithCompletedOnboarding: false)
        await vm.finishOnboarding(
            defaultMode: .arcaSync,
            acceptedCloudTerms: true,
            selectedTemplates: [.vehicleMaintenance, .homeInventory, .warranties],
            createSeparateMedicalLocalSpace: true
        )
        try check(vm.hasCompletedOnboarding, "Onboarding should complete")
        try checkEqual(vm.spaces.count, 3, "Should seed Personal, Vehicles, and Local Health Notes spaces")

        // Verify sensitive Medical Visits space defaulted to Local-Only
        let healthSpace = vm.spaces.first(where: { $0.containsSensitiveHealthTemplate })
        try checkEqual(healthSpace?.storageMode, .localOnly, "Sensitive health template space must default to .localOnly")

        // Verify SpaceMetadata constructor defaults
        let regularDefaultSpace = SpaceMetadata(name: "Regular Project")
        try checkEqual(regularDefaultSpace.storageMode, .arcaSync, "SpaceMetadata must default to .arcaSync for regular spaces")
        let sensitiveDefaultSpace = SpaceMetadata(name: "Medical Space", containsSensitiveHealthTemplate: true)
        try checkEqual(sensitiveDefaultSpace.storageMode, .localOnly, "SpaceMetadata must default to .localOnly for sensitive templates")

        // Verify Insights report
        let insights = vm.currentSpaceInsights
        try check(insights.totalRecords >= 2, "Default space should have seeded sample records")

        // Verify Localization & RTL layout direction for Arabic
        try checkEqual(AppLanguage.arabic.layoutDirection, .rightToLeft)
        try checkEqual(AppLanguage.english.layoutDirection, .leftToRight)
        try checkEqual(AppLanguage.turkish.layoutDirection, .leftToRight)
        try check(ArcaStrings.text("app.tagline", language: .arabic).contains("سجلاتك"), "Arabic localization must be present")
        try check(ArcaStrings.text("app.tagline", language: .turkish).contains("Kayıtlarınız"), "Turkish localization must be present")
        print("[PASS] 9. End-to-End ViewModel Journeys, Sensitive Template Defaults & EN/AR-RTL/TR Localization")
    }
}

if #available(macOS 14.0, iOS 17.0, *) {
    Task { @MainActor in
        do {
            try await ArcaVerificationSuite.runAll()
            exit(0)
        } catch {
            fputs("VERIFICATION FAILED: \(error)\n", stderr)
            exit(1)
        }
    }
    dispatchMain()
}
