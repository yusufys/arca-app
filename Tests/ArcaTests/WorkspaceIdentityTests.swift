import XCTest
import CryptoKit
import ArcaCrypto

final class WorkspaceIdentityTests: XCTestCase {
    func testRelaunchPreservesEncryptionRecoveryDeviceAndOldGenerations() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let keyStore = InMemoryKeyStore()
        let first = try WorkspaceIdentityStore(directory: directory, namespace: "test", keyStore: keyStore)
        let spaceId = UUID()
        let ring = try first.activeSpaceKeyRing(for: spaceId)
        let next = ring.rotated()
        try first.saveSpaceKeyRing(next)
        let envelope = try ClientCryptoEngine.encryptCodable("test", using: ring.symmetricKey, keyId: ring.keyId, contextAAD: "test")
        let second = try WorkspaceIdentityStore(directory: directory, namespace: "test", keyStore: keyStore)
        XCTAssertEqual(second.deviceIdentity.privateKeyRawBase64, first.deviceIdentity.privateKeyRawBase64)
        XCTAssertEqual(second.recoveryPhrase, first.recoveryPhrase)
        XCTAssertEqual(second.masterAccountKey.withUnsafeBytes { Data($0) }, first.masterAccountKey.withUnsafeBytes { Data($0) })
        XCTAssertEqual(try second.activeSpaceKeyRing(for: spaceId), next)
        let old = try XCTUnwrap(second.spaceKeyRings(for: spaceId).first { $0.keyGeneration == 1 })
        XCTAssertEqual(try ClientCryptoEngine.decryptCodable(String.self, from: envelope, using: old.symmetricKey, contextAAD: "test"), "test")
    }

    func testMissingOrCorruptKeysNeverGenerateReplacement() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let keyStore = InMemoryKeyStore()
        _ = try WorkspaceIdentityStore(directory: directory, namespace: "test", keyStore: keyStore)
        try keyStore.removeAllKeys()
        XCTAssertThrowsError(try WorkspaceIdentityStore(directory: directory, namespace: "test", keyStore: keyStore))
        XCTAssertEqual(keyStore.storedIdentifiersCount, 0)
        try keyStore.saveKeyData(Data("corrupt".utf8), forIdentifier: "workspace-identity.v1:test")
        XCTAssertThrowsError(try WorkspaceIdentityStore(directory: directory, namespace: "test", keyStore: keyStore))
        XCTAssertEqual(try keyStore.loadKeyData(forIdentifier: "workspace-identity.v1:test"), Data("corrupt".utf8))
    }

    func testCloudBindingPreservesLocalKeysAndRejectsAccountSwitch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let keyStore = InMemoryKeyStore()
        let identity = try WorkspaceIdentityStore(directory: directory, namespace: "test", keyStore: keyStore)
        let ring = try identity.activeSpaceKeyRing(for: UUID())
        let master = SymmetricKey(size: .bits256)
        try identity.bindCloudAccount(accountId: "first", bearer: "test-token", masterAccountKey: master, recoveryPhrase: identity.recoveryPhrase)
        XCTAssertEqual(try identity.activeSpaceKeyRing(for: ring.spaceId), ring)
        XCTAssertThrowsError(try identity.bindCloudAccount(accountId: "other", bearer: "test-token", masterAccountKey: master, recoveryPhrase: identity.recoveryPhrase))
        let restored = try WorkspaceIdentityStore(directory: directory, namespace: "test", keyStore: keyStore)
        XCTAssertEqual(restored.cloudSession?.accountId, "first")
        XCTAssertEqual(restored.cloudSession?.bearer, "test-token")
    }
}
