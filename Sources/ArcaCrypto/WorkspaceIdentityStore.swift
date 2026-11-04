import Foundation
import CryptoKit

/// One atomic Keychain item retains the account, recovery, device and all Space key generations.
/// A disk marker distinguishes a new workspace from one whose Keychain item is unavailable.
public final class WorkspaceIdentityStore {
    public struct CloudSession: Codable, Sendable {
        public let accountId: String
        public let bearer: String
    }
    private struct Ring: Codable {
        let spaceId: UUID
        let generation: Int
        let keyId: UUID
        let key: Data
    }
    private struct State: Codable {
        let version: Int
        var masterKey: Data
        var recoveryPhrase: String
        let deviceId: String
        let deviceName: String
        let devicePrivateKey: String
        let enrolledAt: Date
        var rings: [Ring]
        var cloudSession: CloudSession?
    }
    private let keyStore: any KeychainKeyStore
    private let identifier: String
    private var state: State
    public private(set) var masterAccountKey: SymmetricKey
    public let deviceIdentity: DeviceIdentity
    public var recoveryPhrase: String { state.recoveryPhrase }

    public init(directory: URL, namespace: String, keyStore: any KeychainKeyStore = SystemKeychainKeyStore()) throws {
        self.keyStore = keyStore
        self.identifier = "workspace-identity.v1:\(namespace)"
        let marker = directory.appendingPathComponent("identity-v1.marker")
        if let data = try keyStore.loadKeyData(forIdentifier: identifier) {
            state = try JSONDecoder().decode(State.self, from: data)
        } else {
            guard !FileManager.default.fileExists(atPath: marker.path) else {
                throw ArcaCryptoError.corruptedEnvelopeField("Missing workspace identity; existing keys were not replaced")
            }
            let device = DeviceIdentity(deviceName: "My Device")
            state = State(version: 1, masterKey: SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) },
                          recoveryPhrase: RecoveryKeyCredential.generate().formattedPhrase,
                          deviceId: device.deviceId, deviceName: device.deviceName,
                          devicePrivateKey: device.privateKeyRawBase64, enrolledAt: device.enrolledAt, rings: [])
            try keyStore.saveKeyData(JSONEncoder().encode(state), forIdentifier: identifier)
        }
        guard state.version == 1, state.masterKey.count == 32 else {
            throw ArcaCryptoError.corruptedEnvelopeField("workspaceIdentity")
        }
        _ = try RecoveryKeyCredential(formattedPhrase: state.recoveryPhrase)
        for ring in state.rings {
            guard ring.generation >= 1, ring.key.count == 32 else {
                throw ArcaCryptoError.corruptedEnvelopeField("workspaceSpaceKey")
            }
        }
        masterAccountKey = SymmetricKey(data: state.masterKey)
        deviceIdentity = try DeviceIdentity(deviceId: state.deviceId, deviceName: state.deviceName,
                                           privateKeyRawBase64: state.devicePrivateKey, enrolledAt: state.enrolledAt)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: marker.path) {
            try Data("arca.identity.v1".utf8).write(to: marker, options: .atomic)
        }
    }

    public var cloudSession: CloudSession? { state.cloudSession }

    /// Detaches a deleted account while retaining every local Space key and device identity.
    /// A future account gets a new master key and recovery phrase.
    public func clearDeletedCloudAccount(expectedAccountId: String) throws {
        guard let session = state.cloudSession else { return }
        guard session.accountId == expectedAccountId else {
            throw ArcaCryptoError.corruptedEnvelopeField("Account deletion identity mismatch")
        }
        var next = state
        next.cloudSession = nil
        next.masterKey = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        next.recoveryPhrase = RecoveryKeyCredential.generate().formattedPhrase
        try keyStore.saveKeyData(JSONEncoder().encode(next), forIdentifier: identifier)
        state = next
        masterAccountKey = SymmetricKey(data: next.masterKey)
    }

    /// Account switching requires explicit local migration; never attach existing data to a different account.
    public func bindCloudAccount(accountId: String, bearer: String, masterAccountKey: SymmetricKey, recoveryPhrase: String) throws {
        guard !accountId.isEmpty, !bearer.isEmpty,
              state.cloudSession == nil || state.cloudSession?.accountId == accountId else {
            throw ArcaCryptoError.corruptedEnvelopeField("Account identity mismatch")
        }
        let credential = try RecoveryKeyCredential(formattedPhrase: recoveryPhrase)
        let raw = masterAccountKey.withUnsafeBytes { Data($0) }
        guard raw.count == 32 else { throw ArcaCryptoError.corruptedEnvelopeField("masterKey") }
        var next = state
        next.masterKey = raw
        next.recoveryPhrase = credential.formattedPhrase
        next.cloudSession = CloudSession(accountId: accountId, bearer: bearer)
        try keyStore.saveKeyData(JSONEncoder().encode(next), forIdentifier: identifier)
        state = next
        self.masterAccountKey = masterAccountKey
    }

    public func activeSpaceKeyRing(for spaceId: UUID) throws -> SpaceKeyRing {
        if let ring = state.rings.filter({ $0.spaceId == spaceId }).max(by: { $0.generation < $1.generation }) {
            return try SpaceKeyRing(spaceId: spaceId, keyGeneration: ring.generation, keyId: ring.keyId, rawKeyData: ring.key)
        }
        let ring = SpaceKeyRing(spaceId: spaceId)
        try saveSpaceKeyRing(ring)
        return ring
    }

    public func spaceKeyRings(for spaceId: UUID) throws -> [SpaceKeyRing] {
        try state.rings.filter { $0.spaceId == spaceId }.map {
            try SpaceKeyRing(spaceId: spaceId, keyGeneration: $0.generation, keyId: $0.keyId, rawKeyData: $0.key)
        }
    }

    public func saveSpaceKeyRing(_ ring: SpaceKeyRing) throws {
        var next = state
        if let existing = next.rings.first(where: { $0.spaceId == ring.spaceId && $0.generation == ring.keyGeneration }) {
            guard existing.keyId == ring.keyId, existing.key == ring.rawKeyData else {
                throw ArcaCryptoError.corruptedEnvelopeField("Conflicting Space key generation")
            }
            return
        }
        next.rings.append(Ring(spaceId: ring.spaceId, generation: ring.keyGeneration, keyId: ring.keyId, key: ring.rawKeyData))
        try keyStore.saveKeyData(JSONEncoder().encode(next), forIdentifier: identifier)
        state = next
    }
}
