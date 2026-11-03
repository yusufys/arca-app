import XCTest
import CryptoKit
import ArcaCore
import ArcaCrypto
import ArcaPersistence
import ArcaSync

final class LaravelNetworkSyncTests: XCTestCase {
    func testMissingAuthenticationNeverAcknowledgesOperations() async throws {
        let backend = LaravelArcaSyncBackend(baseURL: URL(string: "http://127.0.0.1:1")!, apiToken: nil)
        do {
            _ = try await backend.pushEncryptedOperations(accountId: "account", spaceId: UUID(), deviceId: "device", operations: [])
            XCTFail("Unauthenticated transport must throw")
        } catch { XCTAssertEqual(error as? SyncServiceError, .unauthenticated) }
    }

    /// Set ARCA_INTEGRATION_API_URL to an isolated Laravel server with an empty test database.
    func testTwoDeviceHTTPRecoveryBidirectionalChangesTombstonesAndCursorRestart() async throws {
        guard let rawURL = ProcessInfo.processInfo.environment["ARCA_INTEGRATION_API_URL"], let url = URL(string: rawURL) else {
            throw XCTSkip("Requires isolated Laravel HTTP server")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = LaravelArcaSyncBackend(baseURL: url, apiToken: nil)
        let b = LaravelArcaSyncBackend(baseURL: url, apiToken: nil)
        let email = "sync-\(UUID().uuidString)@example.test"
        let account = try await a.signIn(email: email, password: "test-password-123", name: "Sync test")
        let da = DeviceIdentity(deviceName: "A")
        let db = DeviceIdentity(deviceName: "B")
        let mak = ClientCryptoEngine.generateSymmetricKey()
        let phrase = RecoveryKeyCredential.generate()
        let bundle = try phrase.wrapMasterAccountKey(mak, accountId: account.accountId)
        _ = try await a.enrollDevice(accountId: account.accountId, device: EnrolledDevice(descriptor: da.descriptor), maxAllowedDevices: 2, wrappedMasterKey: nil)
        _ = try await a.publishRecoveryBundle(bundle, deviceId: da.deviceId)
        let second = try await b.signIn(email: email, password: "test-password-123")
        XCTAssertEqual(account.accountId, second.accountId)
        let downloaded = try await b.fetchRecoveryBundle()
        let recovered = try RecoveryKeyCredential.restoreMasterAccountKey(fromPhrase: phrase.formattedPhrase, bundle: XCTUnwrap(downloaded))
        _ = try await b.enrollDevice(accountId: account.accountId, device: EnrolledDevice(descriptor: db.descriptor), maxAllowedDevices: 2, wrappedMasterKey: nil)
        let spaceId = UUID(); let ring = SpaceKeyRing(spaceId: spaceId)
        try await a.publishWrappedSpaceKey(accountId: account.accountId, deviceId: da.deviceId, wrappedSpaceKey: ring.wrap(usingMasterAccountKey: mak, makKeyId: bundle.makKeyId))
        let discovered = try await b.listRemoteSpaces(deviceId: db.deviceId)
        let wrapped = try XCTUnwrap(discovered.first?.wrapped_space_keys_json?.first)
        let bRing = try SpaceKeyRing.unwrap(wrapped, usingMasterAccountKey: recovered)
        XCTAssertEqual(ring.rawKeyData, bRing.rawKeyData)
        let sa = SpaceStore(spaceId: spaceId, baseDirectoryURL: root.appendingPathComponent("A"))
        let sb = SpaceStore(spaceId: spaceId, baseDirectoryURL: root.appendingPathComponent("B"))
        let ca = SyncCoordinator(accountId: account.accountId, deviceIdentity: da, masterAccountKey: mak, backend: a)
        let cb = SyncCoordinator(accountId: account.accountId, deviceIdentity: db, masterAccountKey: recovered, backend: b)
        await ca.registerSpaceKeyRing(ring); await cb.registerSpaceKeyRing(bRing)
        let field = FieldDefinition(label: "Private title", type: .shortText)
        let schema = CollectionSchema(spaceId: spaceId, name: "Private schema", fields: [field])
        var record = RecordItem(spaceId: spaceId, collectionId: schema.id, values: [field.id: .shortText("only inside ciphertext")], lastModifiedByDeviceId: da.deviceId)
        await sa.saveCollection(schema); try await sa.saveRecord(record, schema: schema)
        _ = try await ca.synchronizeSpaceStore(sa)
        _ = try await cb.synchronizeSpaceStore(sb)
        let received = await sb.fetchRecord(id: record.id)
        XCTAssertEqual(received?.values, record.values)
        record.revision = 2; record.values[field.id] = .shortText("changed on B"); record.lastModifiedByDeviceId = db.deviceId
        try await sb.saveRecord(record, schema: schema)
        _ = try await cb.synchronizeSpaceStore(sb)
        _ = try await ca.synchronizeSpaceStore(sa)
        let returned = await sa.fetchRecord(id: record.id)
        XCTAssertEqual(returned?.values[field.id], .shortText("changed on B"))
        let cursor = try await sa.syncCursorSequence(accountId: account.accountId)
        XCTAssertGreaterThan(cursor, 0)
        let restartedStore = SpaceStore(spaceId: spaceId, baseDirectoryURL: root.appendingPathComponent("A"))
        let restarted = SyncCoordinator(accountId: account.accountId, deviceIdentity: da, masterAccountKey: mak, backend: a)
        await restarted.registerSpaceKeyRing(ring)
        let restartReport = try await restarted.synchronizeSpaceStore(restartedStore)
        XCTAssertEqual(restartReport.pulledOperationsCount, 0)
        var aVersion = record; aVersion.revision = 3; aVersion.values[field.id] = .shortText("A concurrent")
        var bVersion = record; bVersion.revision = 3; bVersion.values[field.id] = .shortText("B concurrent")
        try await sa.saveRecord(aVersion, schema: schema)
        try await sb.saveRecord(bVersion, schema: schema)
        _ = try await restarted.synchronizeSpaceStore(restartedStore)
        let conflictReport = try await cb.synchronizeSpaceStore(sb)
        XCTAssertEqual(conflictReport.newlyDetectedConflicts.count, 1)
        let bRestarted = SyncCoordinator(accountId: account.accountId, deviceIdentity: db, masterAccountKey: recovered, backend: b)
        await bRestarted.registerSpaceKeyRing(bRing)
        let sbRestarted = SpaceStore(spaceId: spaceId, baseDirectoryURL: root.appendingPathComponent("B"))
        _ = try await bRestarted.synchronizeSpaceStore(sbRestarted)
        let persistedConflicts = await bRestarted.activeConflicts(for: spaceId)
        XCTAssertEqual(persistedConflicts.count, 1)
        let conflict = try XCTUnwrap(persistedConflicts.first)
        record = try await bRestarted.resolveConflict(conflictId: conflict.id, in: sbRestarted, choice: .keepLocal)
        _ = try await bRestarted.synchronizeSpaceStore(sbRestarted)
        _ = try await restarted.synchronizeSpaceStore(restartedStore)
        record.revision += 1; record.isDeleted = true
        try await sbRestarted.saveRecord(record, schema: schema)
        _ = try await bRestarted.synchronizeSpaceStore(sbRestarted)
        _ = try await restarted.synchronizeSpaceStore(restartedStore)
        let deleted = await restartedStore.fetchRecord(id: record.id)
        XCTAssertEqual(deleted?.isDeleted, true)
        _ = try await a.deleteAccountAndRemoteData(accountId: account.accountId)
    }
}
