import Foundation
import CryptoKit
import ArcaCore
import ArcaCrypto
import ArcaUI

@available(macOS 14.0, iOS 17.0, *)
@MainActor
func verifyWorkspaceRestart(mode: String, path: String) async throws {
    struct Fixture: Codable {
        let spaceId: UUID
        let recordIds: [UUID]
        let keyId: UUID
        let masterEnvelope: EncryptedEnvelope
        let spaceEnvelope: EncryptedEnvelope
        let devicePublicKey: String
        let deviceId: String
        let recoveryBundle: WrappedRecoveryBundle
    }
    let directory = URL(fileURLWithPath: path, isDirectory: true)
    let namespace = SHA256.hash(data: Data(directory.standardizedFileURL.path.utf8)).map { String(format: "%02x", $0) }.joined()
    let vm = ArcaAppViewModel(rootDirectoryURL: directory)
    try check(vm.storageStartupError == nil, "Workspace failed to open: \(vm.storageStartupError ?? "")")
    if mode.hasPrefix("write") {
        await vm.finishOnboarding(defaultMode: .localOnly, acceptedCloudTerms: false, selectedTemplates: [])
    }
    let identity = try WorkspaceIdentityStore(directory: directory, namespace: namespace)
    let fixtureURL = directory.appendingPathComponent("restart-fixture.json")
    let cleartext = "persisted cryptographic continuity"
    if mode.hasPrefix("write") {
        let space = try vm.spaces.first.unwrap("Expected seeded Space")
        let ring = try identity.activeSpaceKeyRing(for: space.id)
        let credential = try RecoveryKeyCredential(formattedPhrase: identity.recoveryPhrase)
        let fixture = Fixture(spaceId: space.id, recordIds: vm.recordsInCurrentSpace.map(\.id), keyId: ring.keyId,
            masterEnvelope: try ClientCryptoEngine.encryptCodable(cleartext, using: identity.masterAccountKey, keyId: UUID(), contextAAD: "restart"),
            spaceEnvelope: try ClientCryptoEngine.encryptCodable(cleartext, using: ring.symmetricKey, keyId: ring.keyId, contextAAD: "restart"),
            devicePublicKey: identity.deviceIdentity.publicKeyBase64, deviceId: identity.deviceIdentity.deviceId,
            recoveryBundle: try credential.wrapMasterAccountKey(identity.masterAccountKey, accountId: "restart-test"))
        try check(!fixture.recordIds.isEmpty, "Record fixture cannot be empty")
        try JSONEncoder().encode(fixture).write(to: fixtureURL, options: .atomic)
        print("[PASS] Restart fixture written; terminate this process before running read")
        fflush(stdout)
        if mode == "write-and-wait" {
            while true { try await Task.sleep(nanoseconds: 1_000_000_000) }
        }
    } else {
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: fixtureURL))
        await vm.bootstrapIfNeeded()
        try checkEqual(vm.spaces.first?.id, fixture.spaceId)
        try checkEqual(Set(vm.recordsInCurrentSpace.map(\.id)), Set(fixture.recordIds))
        let ring = try identity.activeSpaceKeyRing(for: fixture.spaceId)
        try checkEqual(ring.keyId, fixture.keyId)
        try checkEqual(identity.deviceIdentity.deviceId, fixture.deviceId)
        try checkEqual(identity.deviceIdentity.publicKeyBase64, fixture.devicePublicKey)
        try checkEqual(try ClientCryptoEngine.decryptCodable(String.self, from: fixture.masterEnvelope, using: identity.masterAccountKey, contextAAD: "restart"), cleartext)
        try checkEqual(try ClientCryptoEngine.decryptCodable(String.self, from: fixture.spaceEnvelope, using: ring.symmetricKey, contextAAD: "restart"), cleartext)
        let recovered = try RecoveryKeyCredential.restoreMasterAccountKey(fromPhrase: identity.recoveryPhrase, bundle: fixture.recoveryBundle)
        try checkEqual(try ClientCryptoEngine.decryptCodable(String.self, from: fixture.masterEnvelope, using: recovered, contextAAD: "restart"), cleartext)
        print("[PASS] Fresh process recovered SQLite records, master encryption key, Space key bytes/ID, device private key and recovery phrase")
    }
}

private extension Optional {
    func unwrap(_ message: String) throws -> Wrapped {
        guard let value = self else { throw VerificationFailure(message) }
        return value
    }
}

func verifyWorkspaceIdentityFailureModes() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ArcaIdentityCheck-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let keyStore = InMemoryKeyStore()
    let identity = try WorkspaceIdentityStore(directory: directory, namespace: "check", keyStore: keyStore)
    let ring = try identity.activeSpaceKeyRing(for: UUID())
    try identity.saveSpaceKeyRing(ring.rotated())
    let master = SymmetricKey(size: .bits256)
    try identity.bindCloudAccount(accountId: "first", bearer: "test", masterAccountKey: master, recoveryPhrase: identity.recoveryPhrase)
    var rejected = false
    do { try identity.bindCloudAccount(accountId: "other", bearer: "test", masterAccountKey: master, recoveryPhrase: identity.recoveryPhrase) }
    catch { rejected = true }
    try check(rejected, "Switching cloud accounts must be rejected")
    let restored = try WorkspaceIdentityStore(directory: directory, namespace: "check", keyStore: keyStore)
    try checkEqual(restored.cloudSession?.accountId, "first")
    try checkEqual(restored.cloudSession?.bearer, "test")
    try checkEqual(restored.deviceIdentity.privateKeyRawBase64, identity.deviceIdentity.privateKeyRawBase64)
    try checkEqual(try restored.spaceKeyRings(for: ring.spaceId).count, 2)
    try checkEqual(try restored.spaceKeyRings(for: ring.spaceId).first, ring)
    try keyStore.removeAllKeys()
    rejected = false
    do { _ = try WorkspaceIdentityStore(directory: directory, namespace: "check", keyStore: keyStore) }
    catch { rejected = true }
    try check(rejected, "Missing keys must fail closed")
    try checkEqual(keyStore.storedIdentifiersCount, 0, "Missing keys must not be replaced")
    try keyStore.saveKeyData(Data("corrupt".utf8), forIdentifier: "workspace-identity.v1:check")
    rejected = false
    do { _ = try WorkspaceIdentityStore(directory: directory, namespace: "check", keyStore: keyStore) }
    catch { rejected = true }
    try check(rejected, "Corrupt keys must fail closed")
    try checkEqual(try keyStore.loadKeyData(forIdentifier: "workspace-identity.v1:check"), Data("corrupt".utf8))
    print("[PASS] Workspace key history/session continuity, account mismatch protection and missing/corrupt key rejection")
}
