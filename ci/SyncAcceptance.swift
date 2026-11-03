// Compiled only by the acceptance harness, which supplies disposable accounts and workspaces.
import Foundation
import CryptoKit
import ArcaCore
import ArcaCrypto
import ArcaUI

@MainActor
enum SyncAcceptance {
    static func run(_ vm: ArcaAppViewModel, mode: String) async throws -> [String: String] {
        let env = ProcessInfo.processInfo.environment
        func require(_ valid: Bool, _ message: String) throws {
            if !valid { throw NSError(domain: "Acceptance", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        try require(vm.storageStartupError == nil, vm.storageStartupError ?? "")
        let spaceName = "Acceptance workspace"
        let label = "Warranty"
        let original = "Warranty saved on A"
        let updated = "Warranty edited on B"
        let fixtureURL = vm.rootDirectoryURL.appendingPathComponent("acceptance-proof.json")
        let namespace = env["ARCA_TEST_ROOT"] == nil ? "default" : SHA256.hash(data: Data(vm.rootDirectoryURL.standardizedFileURL.path.utf8)).map { String(format: "%02x", $0) }.joined()
        let identity = try WorkspaceIdentityStore(directory: vm.rootDirectoryURL, namespace: namespace)
        await vm.bootstrapIfNeeded()

        if mode == "seed" {
            try require(vm.spaces.isEmpty, "Requires a fresh disposable workspace")
            await vm.createSpace(name: spaceName, iconName: "folder", storageMode: .arcaSync)
            let field = FieldDefinition(label: "Title", type: .shortText, isPrimaryTitle: true)
            await vm.createCustomCollection(name: label, iconName: "list.bullet", fields: [field])
            guard let schema = vm.collectionsInCurrentSpace.first else { throw failure("No schema") }
            try await vm.saveRecord(existingRecord: nil, schema: schema, values: [field.id: .shortText(original)], isFavorite: true)
            guard let record = vm.recordsInCurrentSpace.first else { throw failure("No record after save") }
            let ring = try identity.activeSpaceKeyRing(for: schema.spaceId)
            let cipher = try ClientCryptoEngine.encryptCodable(record.id, using: ring.symmetricKey, keyId: ring.keyId, contextAAD: "quit-proof")
            let proof = Proof(record: record.id, space: schema.spaceId, deviceKey: identity.deviceIdentity.publicKeyBase64,
                encryptedRecordId: cipher, recovery: try RecoveryKeyCredential(formattedPhrase: identity.recoveryPhrase)
                    .wrapMasterAccountKey(identity.masterAccountKey, accountId: "test-local"))
            try JSONEncoder().encode(proof).write(to: fixtureURL, options: .atomic)
            return ["record":record.id.uuidString]
        }
        if mode == "resume" {
            let proof = try JSONDecoder().decode(Proof.self, from: Data(contentsOf: fixtureURL))
            let ring = try identity.activeSpaceKeyRing(for: proof.space)
            let id = try ClientCryptoEngine.decryptCodable(UUID.self, from: proof.encryptedRecordId, using: ring.symmetricKey, contextAAD: "quit-proof")
            let master = try RecoveryKeyCredential.restoreMasterAccountKey(fromPhrase: vm.recoveryKeyPhrase, bundle: proof.recovery)
            try require(master == identity.masterAccountKey && proof.deviceKey == identity.deviceIdentity.publicKeyBase64 &&
                        id == proof.record && vm.record(for: id)?.isFavorite == true &&
                        vm.recordsInCurrentSpace.first?.values.values.contains(.shortText(original)) == true, "Record or key did not survive restart")
            return [:]
        }
        if mode == "register" || mode == "join" {
            guard let email = env["ARCA_TEST_EMAIL"], let password = env["ARCA_TEST_PASSWORD"] else { throw failure("Missing fixture credentials") }
            try await vm.connectCloudAccount(email: email, password: password, createAccount: mode == "register", recoveryPhrase: env["ARCA_TEST_PHRASE"] ?? "")
            if mode == "register" { return ["phrase":vm.recoveryKeyPhrase] }
        } else {
            try require(vm.cloudAccountConnected, "Cloud session was lost on relaunch")
            try await vm.syncCloudSpaces()
        }
        guard let recordId = env["ARCA_TEST_RECORD"].flatMap(UUID.init(uuidString:)),
              let record = vm.record(for: recordId), let schema = vm.schema(for: record.collectionId),
              let field = schema.primaryTitleField else { throw failure("Remote record was not recovered") }
        try require(record.values[field.id] == .shortText(mode == "join" ? original : updated), "Incorrect remote field contents")
        if mode == "join" {
            await vm.selectSpace(record.spaceId)
            var values = record.values
            values[field.id] = .shortText(updated)
            try await vm.saveRecord(existingRecord: record, schema: schema, values: values, isFavorite: true)
            try await vm.syncCloudSpaces()
        }
        return ["record":record.id.uuidString]
    }
    struct Proof: Codable {
        let record: UUID
        let space: UUID
        let deviceKey: String
        let encryptedRecordId: EncryptedEnvelope
        let recovery: WrappedRecoveryBundle
    }
    static func failure(_ message: String) -> Error {
        NSError(domain: "Acceptance", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    static func writeResult(_ vm: ArcaAppViewModel, mode: String, to url: URL) async {
        let value: [String:String]
        do { value = try await run(vm, mode: mode).merging(["status":"ok"]) { lhs,_ in lhs } }
        catch { value = ["status":"failed","error":error.localizedDescription] }
        do { try JSONEncoder().encode(value).write(to: url, options: .atomic) }
        catch { print("Could not write acceptance result") }
    }
}

#if os(macOS)
@main struct AcceptanceCLI {
    @MainActor static func main() async {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["ARCA_TEST_ROOT"], let result = env["ARCA_TEST_RESULT"], let stage = env["ARCA_TEST_STAGE"] else { exit(2) }
        let vm = ArcaAppViewModel(rootDirectoryURL: URL(fileURLWithPath: path))
        await SyncAcceptance.writeResult(vm, mode: stage, to: URL(fileURLWithPath: result))
        if stage == "seed" { while true { try? await Task.sleep(nanoseconds: 5_000_000_000) } }
    }
}
#endif
