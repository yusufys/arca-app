import XCTest
import Foundation
import ArcaCore
import ArcaCrypto
import ArcaPersistence
import ArcaSync

final class SensitivePrivacyTests: XCTestCase {
    func testPrivateLabelsDefaultsUnknownValuesAndAttachmentsAreExcluded() throws {
        let spaceId = UUID()
        let privateField = FieldDefinition(label: "Secret label", type: .shortText, defaultValue: .shortText("Secret default"), privacy: .localOnly)
        let privateAttachment = FieldDefinition(label: "Secret attachment label", type: .attachment, privacy: .localOnly)
        let attachment = AttachmentReference(filename: "Secret-file.pdf", mimeType: "application/pdf", byteSize: 12, sha256Hex: "Secret-digest", localRelativePath: "Secret-path")
        let sibling = FieldDefinition(label: "Expiry", type: .shortText)
        let schema = CollectionSchema(spaceId: spaceId, name: "Warranty", fields: [privateField, privateAttachment, sibling])
        let record = RecordItem(spaceId: spaceId, collectionId: schema.id,
            values: [privateField.id: .shortText("Secret value"), privateAttachment.id: .attachments([attachment]), sibling.id: .shortText("2027"), UUID(): .shortText("Orphaned secret")])
        let projectedSchema = try XCTUnwrap(CloudPrivacyPolicy.schemaForCloud(schema))
        let projectedRecord = try XCTUnwrap(CloudPrivacyPolicy.recordForCloud(record, schema: schema))
        XCTAssertEqual(projectedSchema.fields.map(\.id), [sibling.id])
        XCTAssertEqual(projectedRecord.values, [sibling.id: .shortText("2027")])
        let bytes = try JSONEncoder().encode(projectedSchema) + JSONEncoder().encode(projectedRecord)
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("Secret"))
        var localCollection = schema; localCollection.privacy = .localOnly
        XCTAssertNil(CloudPrivacyPolicy.schemaForCloud(localCollection))
        XCTAssertNil(CloudPrivacyPolicy.recordForCloud(record, schema: localCollection))
    }

    func testOlderSanitizedSchemaCannotErasePendingLocalApproval() throws {
        let secret = FieldDefinition(label: "Private serial", type: .shortText, privacy: .syncWithConsent)
        let ordinary = FieldDefinition(label: "Expiry", type: .shortText)
        let local = CollectionSchema(spaceId: UUID(), name: "Warranty", fields: [secret, ordinary])
        var olderSanitized = local; olderSanitized.fields = [ordinary]
        let merged = CloudPrivacyPolicy.mergingRemoteSchema(olderSanitized, local: local)
        XCTAssertEqual(merged.fields.first(where: { $0.id == secret.id }), secret)
        let reset = CloudPrivacyPolicy.resettingConsent(merged)
        XCTAssertEqual(reset.fields.first(where: { $0.id == secret.id })?.privacy, .localOnly)
    }

    func testMasterPasswordRejectsEmptyAndWrongPasswordsAndRoundTripsVerifier() throws {
        XCTAssertThrowsError(try ConsentPasswordVerifier(password: ""))
        XCTAssertThrowsError(try ConsentPasswordVerifier(password: "short"))
        let verifier = try ConsentPasswordVerifier(password: "a long private password")
        let restored = try JSONDecoder().decode(ConsentPasswordVerifier.self, from: JSONEncoder().encode(verifier))
        XCTAssertTrue(try restored.verify("a long private password"))
        XCTAssertFalse(try restored.verify("a wrong private password"))
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(verifier), as: UTF8.self).contains("a long private password"))
    }

    func testQueuedPayloadsAreRebuiltAndOtherDeviceEditPreservesPrivateValue() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let backend = InMemoryArcaSyncBackend()
        let a = DeviceIdentity(deviceName: "A"), b = DeviceIdentity(deviceName: "B")
        let spaceId = UUID(), key = SpaceKeyRing(spaceId: UUID())
        let ring = SpaceKeyRing(spaceId: spaceId, symmetricKey: key.symmetricKey)
        let ca = SyncCoordinator(accountId: "privacy-test", deviceIdentity: a, backend: backend)
        let cb = SyncCoordinator(accountId: "privacy-test", deviceIdentity: b, backend: backend)
        _ = try await ca.enrollCurrentDevice(); _ = try await cb.enrollCurrentDevice()
        await ca.registerSpaceKeyRing(ring); await cb.registerSpaceKeyRing(ring)
        let sa = SpaceStore(spaceId: spaceId, baseDirectoryURL: directory.appendingPathComponent("A"))
        let sb = SpaceStore(spaceId: spaceId, baseDirectoryURL: directory.appendingPathComponent("B"))
        let secret = FieldDefinition(label: "Serial", type: .shortText)
        let expiry = FieldDefinition(label: "Expiry", type: .shortText)
        var schema = CollectionSchema(spaceId: spaceId, name: "Warranty", fields: [secret, expiry])
        await sa.saveCollection(schema)
        let record = RecordItem(spaceId: spaceId, collectionId: schema.id, values: [secret.id: .shortText("private-serial"), expiry.id: .shortText("2027")])
        try await sa.saveRecord(record, schema: schema)
        // Existing queued plaintext snapshots contain the secret. Current privacy must win on upload.
        schema.fields[0].privacy = .localOnly; schema.revision += 1
        await sa.saveCollection(schema)
        _ = try await ca.synchronizeSpaceStore(sa)
        let uploaded = await backend.inspectStoredEncryptedOperations(accountId: "privacy-test", spaceId: spaceId)
        for op in uploaded {
            if op.entityType == .collectionSchema { XCTAssertFalse(try op.decryptSchema(using: ring).fields.contains { $0.id == secret.id }) }
            if op.entityType == .record { XCTAssertNil(try op.decryptRecord(using: ring).values[secret.id]) }
        }
        _ = try await cb.synchronizeSpaceStore(sb)
        let storedB = await sb.fetchRecord(id: record.id)
        var fromB = try XCTUnwrap(storedB)
        XCTAssertNil(fromB.values[secret.id]); fromB.values[expiry.id] = .shortText("2028"); fromB.revision += 1
        let storedBSchema = await sb.fetchCollection(id: schema.id)
        let bSchema = try XCTUnwrap(storedBSchema)
        try await sb.saveRecord(fromB, schema: bSchema)
        _ = try await cb.synchronizeSpaceStore(sb)
        _ = try await ca.synchronizeSpaceStore(sa)
        let storedFinal = await sa.fetchRecord(id: record.id)
        let final = try XCTUnwrap(storedFinal)
        XCTAssertEqual(final.values[secret.id], .shortText("private-serial"))
        XCTAssertEqual(final.values[expiry.id], .shortText("2028"))
    }

    func testAlreadyUploadedCopiesArePurgedAndStaleOfflineEditsAreRedacted() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let backend = InMemoryArcaSyncBackend(), spaceId = UUID()
        let a = DeviceIdentity(deviceName: "A"), b = DeviceIdentity(deviceName: "B")
        let ring = SpaceKeyRing(spaceId: spaceId)
        let ca = SyncCoordinator(accountId: "existing-private", deviceIdentity: a, backend: backend)
        let cb = SyncCoordinator(accountId: "existing-private", deviceIdentity: b, backend: backend)
        _ = try await ca.enrollCurrentDevice(); _ = try await cb.enrollCurrentDevice()
        await ca.registerSpaceKeyRing(ring); await cb.registerSpaceKeyRing(ring)
        let sa = SpaceStore(spaceId: spaceId, baseDirectoryURL: directory.appendingPathComponent("A"))
        let sb = SpaceStore(spaceId: spaceId, baseDirectoryURL: directory.appendingPathComponent("B"))
        let secret = FieldDefinition(label: "Secret serial", type: .shortText), ordinary = FieldDefinition(label: "Expiry", type: .shortText)
        var schema = CollectionSchema(spaceId: spaceId, name: "Warranty", fields: [secret, ordinary])
        let record = RecordItem(spaceId: spaceId, collectionId: schema.id, values: [secret.id: .shortText("once-uploaded"), ordinary.id: .shortText("2027")])
        await sa.saveCollection(schema); try await sa.saveRecord(record, schema: schema)
        _ = try await ca.synchronizeSpaceStore(sa); _ = try await cb.synchronizeSpaceStore(sb)
        let original = await sb.fetchRecord(id: record.id)
        var offlineEdit = try XCTUnwrap(original)
        offlineEdit.values[ordinary.id] = .shortText("2029"); offlineEdit.revision += 1
        try await sb.saveRecord(offlineEdit, schema: schema)
        schema.fields[0].privacy = .localOnly; schema.revision += 1
        await sa.saveCollection(schema)
        _ = try await ca.synchronizeSpaceStore(sa)
        let afterPurge = await backend.inspectStoredEncryptedOperations(accountId: "existing-private", spaceId: spaceId)
        XCTAssertFalse(afterPurge.isEmpty)
        for op in afterPurge where op.entityType == .record { XCTAssertNil(try op.decryptRecord(using: ring).values[secret.id]) }
        _ = try await cb.synchronizeSpaceStore(sb)
        let afterOfflineRetry = await backend.inspectStoredEncryptedOperations(accountId: "existing-private", spaceId: spaceId)
        for op in afterOfflineRetry where op.entityType == .record { XCTAssertNil(try op.decryptRecord(using: ring).values[secret.id]) }
        _ = try await ca.synchronizeSpaceStore(sa)
        let final = await sa.fetchRecord(id: record.id)
        XCTAssertEqual(final?.values[secret.id], .shortText("once-uploaded"))
        XCTAssertEqual(final?.values[ordinary.id], .shortText("2029"))
    }

    func testTwoDeviceLaravelPrivacyPurgeAndOfflineRetry() async throws {
        guard let rawURL = ProcessInfo.processInfo.environment["ARCA_INTEGRATION_API_URL"], let url = URL(string: rawURL) else {
            throw XCTSkip("Requires isolated Laravel HTTP server")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let backendA = LaravelArcaSyncBackend(baseURL: url, apiToken: nil)
        let backendB = LaravelArcaSyncBackend(baseURL: url, apiToken: nil)
        let email = "privacy-\(UUID())@example.test", password = "disposable-test-password"
        let account = try await backendA.signIn(email: email, password: password, name: "Privacy integration")
        _ = try await backendB.signIn(email: email, password: password)
        let spaceId = UUID()
        let a = DeviceIdentity(deviceName: "A"), b = DeviceIdentity(deviceName: "B")
        let ring = SpaceKeyRing(spaceId: spaceId)
        let ca = SyncCoordinator(accountId: account.accountId, deviceIdentity: a, backend: backendA)
        let cb = SyncCoordinator(accountId: account.accountId, deviceIdentity: b, backend: backendB)
        _ = try await ca.enrollCurrentDevice(); _ = try await cb.enrollCurrentDevice()
        await ca.registerSpaceKeyRing(ring); await cb.registerSpaceKeyRing(ring)
        try await backendA.publishWrappedSpaceKey(accountId: account.accountId, deviceId: a.deviceId,
            wrappedSpaceKey: ring.wrap(usingMasterAccountKey: ClientCryptoEngine.generateSymmetricKey(), makKeyId: UUID()))
        let sa = SpaceStore(spaceId: spaceId, baseDirectoryURL: directory.appendingPathComponent("A"))
        let sb = SpaceStore(spaceId: spaceId, baseDirectoryURL: directory.appendingPathComponent("B"))
        let secret = FieldDefinition(label: "Secret serial", type: .shortText), ordinary = FieldDefinition(label: "Expiry", type: .shortText)
        var schema = CollectionSchema(spaceId: spaceId, name: "Warranty", fields: [secret, ordinary])
        let record = RecordItem(spaceId: spaceId, collectionId: schema.id, values: [secret.id: .shortText("once-uploaded"), ordinary.id: .shortText("2027")])
        await sa.saveCollection(schema); try await sa.saveRecord(record, schema: schema)
        _ = try await ca.synchronizeSpaceStore(sa); _ = try await cb.synchronizeSpaceStore(sb)
        let original = await sb.fetchRecord(id: record.id)
        var offlineEdit = try XCTUnwrap(original)
        offlineEdit.values[ordinary.id] = .shortText("2029"); offlineEdit.revision += 1
        try await sb.saveRecord(offlineEdit, schema: schema)
        schema.fields[0].privacy = .localOnly; schema.revision += 1
        await sa.saveCollection(schema)
        _ = try await ca.synchronizeSpaceStore(sa)
        let pendingAfterPurge = try await sa.pendingPrivacyRules()
        XCTAssertTrue(pendingAfterPurge.isEmpty, "Supported server must acknowledge scoped removal")
        let afterPurge = try await backendA.pullEncryptedOperations(accountId: account.accountId, spaceId: spaceId,
            deviceId: a.deviceId, sinceCursor: nil, limit: 500).operations
        XCTAssertFalse(afterPurge.isEmpty)
        for op in afterPurge where op.entityType == .record { XCTAssertNil(try op.decryptRecord(using: ring).values[secret.id]) }
        _ = try await cb.synchronizeSpaceStore(sb)
        let afterOfflineRetry = try await backendA.pullEncryptedOperations(accountId: account.accountId, spaceId: spaceId,
            deviceId: a.deviceId, sinceCursor: nil, limit: 500).operations
        for op in afterOfflineRetry where op.entityType == .record { XCTAssertNil(try op.decryptRecord(using: ring).values[secret.id]) }
        _ = try await ca.synchronizeSpaceStore(sa)
        let final = await sa.fetchRecord(id: record.id)
        XCTAssertEqual(final?.values[secret.id], .shortText("once-uploaded"))
        XCTAssertEqual(final?.values[ordinary.id], .shortText("2029"))
        _ = try await backendA.deleteAccountAndRemoteData(accountId: account.accountId)
    }

    func testPrivacyPendingSurvivesRestartAndCollectionProducesNoUploads() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let spaceId = UUID(), device = DeviceIdentity(deviceName: "A")
        let backend = InMemoryArcaSyncBackend()
        let coordinator = SyncCoordinator(accountId: "local-collection", deviceIdentity: device, backend: backend)
        _ = try await coordinator.enrollCurrentDevice()
        let store = SpaceStore(spaceId: spaceId, baseDirectoryURL: directory)
        var schema = CollectionSchema(spaceId: spaceId, name: "Private collection", fields: [FieldDefinition(label: "Secret", type: .shortText)])
        await store.saveCollection(schema)
        schema.privacy = .localOnly
        await store.saveCollection(schema)
        let restarted = SpaceStore(spaceId: spaceId, baseDirectoryURL: directory)
        let backupValues = try restarted.spaceDirectoryURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(backupValues.isExcludedFromBackup, true)
        let pending = try await restarted.pendingPrivacyRules()
        XCTAssertEqual(pending.map(\.collectionId), [schema.id])
        await backend.setSimulatedOffline(true)
        do { _ = try await coordinator.synchronizeSpaceStore(restarted); XCTFail("Offline sync should fail") } catch {}
        let offlinePending = try await restarted.pendingPrivacyRules()
        XCTAssertEqual(offlinePending.count, 1)
        await backend.setSimulatedOffline(false)
        _ = try await coordinator.synchronizeSpaceStore(restarted)
        let operations = await backend.inspectStoredEncryptedOperations(accountId: "local-collection", spaceId: spaceId)
        let remainingPending = try await restarted.pendingPrivacyRules()
        XCTAssertTrue(operations.isEmpty)
        XCTAssertTrue(remainingPending.isEmpty)
    }
}
