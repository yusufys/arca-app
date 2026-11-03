import Foundation
import CryptoKit
import Security
import ArcaCore

// MARK: - Errors

/// Cryptographic errors surfaced by `ArcaCrypto`.
/// Note: Error messages intentionally never embed plaintext values, schema labels, attachment names, or key material.
public enum ArcaCryptoError: LocalizedError, Sendable, Equatable {
    case unsupportedEnvelopeVersion(Int)
    case keyIdMismatch(expected: UUID, actual: UUID)
    case corruptedEnvelopeField(String)
    case authenticationFailed
    case encryptionFailed
    case invalidPassphrase
    case invalidArchiveContainer
    case invalidRecoveryPhrase
    case invalidPublicKey
    case deviceRevoked(deviceId: String)
    case keychainFailure(status: Int32)
    case keyNotFound(identifier: String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedEnvelopeVersion(let version):
            return "Unsupported encrypted envelope format version (\(version))."
        case .keyIdMismatch:
            return "The encrypted payload requires a different encryption key generation."
        case .corruptedEnvelopeField(let field):
            return "Encrypted envelope contains invalid encoding in field '\(field)'."
        case .authenticationFailed:
            return "Cryptographic authentication failed. The data or context AAD may have been tampered with, or the key is incorrect."
        case .encryptionFailed:
            return "Failed to seal payload with AES-GCM."
        case .invalidPassphrase:
            return "Passphrase cannot be empty or failed authentication."
        case .invalidArchiveContainer:
            return "Encrypted archive container header or structure is invalid or corrupted."
        case .invalidRecoveryPhrase:
            return "Recovery key format is invalid or checksum verification failed."
        case .invalidPublicKey:
            return "Peer device public key is invalid."
        case .deviceRevoked:
            return "Cannot perform cryptographic key agreement with a revoked device."
        case .keychainFailure(let status):
            return "Keychain operation failed with OSStatus \(status)."
        case .keyNotFound:
            return "Requested encryption key was not found in the key store."
        }
    }
}

// MARK: - Encrypted Envelope

/// Provider-independent authenticated encryption envelope (`AES-GCM-256`).
/// Used identically across `ArcaSync`, portable `.arcaarchive` backups, and optional personal-cloud backup adapters.
public struct EncryptedEnvelope: Codable, Sendable, Equatable, Hashable {
    public static let currentVersion: Int = 1

    public let version: Int
    public let keyId: UUID
    public let nonceBase64: String
    public let ciphertextBase64: String
    public let tagBase64: String
    /// Opaque context identifier describing the authenticated additional data structure (never contains user plaintext).
    public let aadDescription: String

    public init(
        version: Int = EncryptedEnvelope.currentVersion,
        keyId: UUID,
        nonceBase64: String,
        ciphertextBase64: String,
        tagBase64: String,
        aadDescription: String
    ) {
        self.version = version
        self.keyId = keyId
        self.nonceBase64 = nonceBase64
        self.ciphertextBase64 = ciphertextBase64
        self.tagBase64 = tagBase64
        self.aadDescription = aadDescription
    }

    /// Total approximate ciphertext byte size visible to transport/storage layers.
    public var approximateCiphertextByteCount: Int {
        Data(base64Encoded: ciphertextBase64)?.count ?? 0
    }
}

// MARK: - Space Key Ring

/// Holds a Space's 256-bit Data Encryption Key (`SDEK`) and key generation metadata.
/// Each Space uses an independent key ring that can be rotated on device revocation.
public struct SpaceKeyRing: Sendable, Equatable {
    public let spaceId: UUID
    public let keyGeneration: Int
    public let keyId: UUID
    public let symmetricKey: SymmetricKey

    public init(
        spaceId: UUID,
        keyGeneration: Int = 1,
        keyId: UUID = UUID(),
        symmetricKey: SymmetricKey = SymmetricKey(size: .bits256)
    ) {
        self.spaceId = spaceId
        self.keyGeneration = max(1, keyGeneration)
        self.keyId = keyId
        self.symmetricKey = symmetricKey
    }

    public init(
        spaceId: UUID,
        keyGeneration: Int = 1,
        keyId: UUID = UUID(),
        rawKeyData: Data
    ) throws {
        guard rawKeyData.count == 32 else {
            throw ArcaCryptoError.corruptedEnvelopeField("symmetricKey")
        }
        self.spaceId = spaceId
        self.keyGeneration = max(1, keyGeneration)
        self.keyId = keyId
        self.symmetricKey = SymmetricKey(data: rawKeyData)
    }

    /// Exports the raw 256-bit key material for Keychain storage or wrapping.
    public var rawKeyData: Data {
        symmetricKey.withUnsafeBytes { Data($0) }
    }

    /// Wraps this SpaceKeyRing using the user's 256-bit Master Account Key (`MAK`).
    public func wrap(usingMasterAccountKey mak: SymmetricKey, makKeyId: UUID) throws -> WrappedSpaceKeyRing {
        let aadString = "arca.space-key.v1:\(spaceId.uuidString):gen:\(keyGeneration):key:\(keyId.uuidString)"
        let envelope = try ClientCryptoEngine.encryptPayload(
            rawKeyData,
            using: mak,
            keyId: makKeyId,
            aad: Data(aadString.utf8),
            aadDescription: "space-key-wrap-v1"
        )
        return WrappedSpaceKeyRing(
            spaceId: spaceId,
            keyGeneration: keyGeneration,
            keyId: keyId,
            wrappedKeyEnvelope: envelope
        )
    }

    /// Unwraps a `SpaceKeyRing` from a `WrappedSpaceKeyRing` using the Master Account Key (`MAK`).
    public static func unwrap(
        _ wrapped: WrappedSpaceKeyRing,
        usingMasterAccountKey mak: SymmetricKey
    ) throws -> SpaceKeyRing {
        let aadString = "arca.space-key.v1:\(wrapped.spaceId.uuidString):gen:\(wrapped.keyGeneration):key:\(wrapped.keyId.uuidString)"
        let rawKeyData = try ClientCryptoEngine.decryptPayload(
            wrapped.wrappedKeyEnvelope,
            using: mak,
            expectedAAD: Data(aadString.utf8)
        )
        return try SpaceKeyRing(
            spaceId: wrapped.spaceId,
            keyGeneration: wrapped.keyGeneration,
            keyId: wrapped.keyId,
            rawKeyData: rawKeyData
        )
    }

    /// Rotates the Space key to the next generation (`keyGeneration + 1`) with fresh 256-bit entropy.
    public func rotated() -> SpaceKeyRing {
        SpaceKeyRing(
            spaceId: spaceId,
            keyGeneration: keyGeneration + 1,
            keyId: UUID(),
            symmetricKey: SymmetricKey(size: .bits256)
        )
    }

    public static func == (lhs: SpaceKeyRing, rhs: SpaceKeyRing) -> Bool {
        lhs.spaceId == rhs.spaceId &&
        lhs.keyGeneration == rhs.keyGeneration &&
        lhs.keyId == rhs.keyId &&
        lhs.rawKeyData == rhs.rawKeyData
    }
}

/// Serializable representation of a Space key wrapped under the Master Account Key.
public struct WrappedSpaceKeyRing: Codable, Sendable, Equatable, Hashable {
    public let spaceId: UUID
    public let keyGeneration: Int
    public let keyId: UUID
    public let wrappedKeyEnvelope: EncryptedEnvelope

    public init(
        spaceId: UUID,
        keyGeneration: Int,
        keyId: UUID,
        wrappedKeyEnvelope: EncryptedEnvelope
    ) {
        self.spaceId = spaceId
        self.keyGeneration = keyGeneration
        self.keyId = keyId
        self.wrappedKeyEnvelope = wrappedKeyEnvelope
    }
}

// MARK: - Recovery Key Credential (E2EE Data Recovery vs. Account Password Reset)

/// Serializable recovery bundle that stores the wrapped Master Account Key (`MAK`) and HKDF salt.
public struct WrappedRecoveryBundle: Codable, Sendable, Equatable, Hashable {
    public let accountId: String
    public let makKeyId: UUID
    public let hkdfSaltBase64: String
    public let wrappedMAKEnvelope: EncryptedEnvelope
    public let createdAt: Date

    public init(
        accountId: String,
        makKeyId: UUID,
        hkdfSaltBase64: String,
        wrappedMAKEnvelope: EncryptedEnvelope,
        createdAt: Date = Date()
    ) {
        self.accountId = accountId
        self.makKeyId = makKeyId
        self.hkdfSaltBase64 = hkdfSaltBase64
        self.wrappedMAKEnvelope = wrappedMAKEnvelope
        self.createdAt = createdAt
    }
}

/// Manages high-entropy Recovery Key generation, `HKDF<SHA256>` key derivation, and Master Account Key recovery.
///
/// Architectural Distinction:
/// - **Account Password Reset:** Recovers sign-in authentication to the account service, but **cannot** decrypt E2EE records.
/// - **E2EE Recovery Key:** High-entropy client-generated secret that derives a 256-bit wrapping key via `HKDF<SHA256>`
///   to unwrap the Master Account Key (`MAK`) when all enrolled devices are lost.
public struct RecoveryKeyCredential: Sendable, Equatable {
    private static let crockfordAlphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    private static let hkdfInfo = Data("arca.e2ee.recovery.hkdf.v1".utf8)

    /// Human-readable formatted recovery phrase (e.g., `ARCA-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX`).
    public let formattedPhrase: String
    public let createdAt: Date

    /// Explicitly indicates that resetting an account password alone can never decrypt E2EE user data.
    public static let canPasswordResetDecryptE2EEData: Bool = false

    /// Clear user-facing disclosure distinguishing account password reset from E2EE data recovery.
    public static let passwordResetVsRecoveryDisclosure: String =
        "Resetting your account password restores sign-in access only and cannot decrypt your end-to-end encrypted records. " +
        "To restore encrypted data without an existing enrolled device, you must provide your Arca Recovery Key."

    public init(formattedPhrase: String, createdAt: Date = Date()) throws {
        let normalized = Self.normalizePhrase(formattedPhrase)
        guard Self.isValidNormalizedPhrase(normalized) else {
            throw ArcaCryptoError.invalidRecoveryPhrase
        }
        self.formattedPhrase = normalized
        self.createdAt = createdAt
    }

    /// Generates a new high-entropy 256-bit recovery credential formatted in human-readable groups.
    public static func generate(createdAt: Date = Date()) -> RecoveryKeyCredential {
        let randomKey = SymmetricKey(size: .bits256)
        let bytes = randomKey.withUnsafeBytes { Array($0) }
        // Encode 32 bytes (256 bits) into 8 groups of 4 unambiguous Base32 characters: ARCA-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX
        var groups: [String] = ["ARCA"]
        for groupIndex in 0..<8 {
            var groupChars: [Character] = []
            for charOffset in 0..<4 {
                let byteIndex = (groupIndex * 4 + charOffset) % bytes.count
                let mixed = Int(bytes[byteIndex]) ^ Int(bytes[(byteIndex + 13) % bytes.count] >> 3)
                let idx = mixed & 0x1F
                groupChars.append(crockfordAlphabet[idx])
            }
            groups.append(String(groupChars))
        }
        let phrase = groups.joined(separator: "-")
        // Safe force-init because format is guaranteed valid above
        return try! RecoveryKeyCredential(formattedPhrase: phrase, createdAt: createdAt)
    }

    /// Normalizes whitespace, casing, and lookalike characters (`O` -> `0`, `I`/`L` -> `1`) in a recovery phrase.
    public static func normalizePhrase(_ input: String) -> String {
        let upper = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: " ", with: "-")
        var normalizedChars: [Character] = []
        for ch in upper {
            switch ch {
            case "O": normalizedChars.append("0")
            case "I", "L": normalizedChars.append("1")
            default: normalizedChars.append(ch)
            }
        }
        return String(normalizedChars)
    }

    /// Validates that a normalized phrase starts with `ARCA-` and contains at least 6 groups of 4 alphanumeric characters.
    public static func isValidNormalizedPhrase(_ normalized: String) -> Bool {
        let parts = normalized.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count >= 7, parts.first == "ARCA" else {
            return false
        }
        for group in parts.dropFirst() {
            guard group.count == 4, group.allSatisfy({ $0.isLetter || $0.isNumber }) else {
                return false
            }
        }
        return true
    }

    /// Derives a 256-bit wrapping key from the recovery phrase and salt using `HKDF<SHA256>`.
    public static func deriveWrappingKey(fromPhrase phrase: String, salt: Data) throws -> SymmetricKey {
        let normalized = normalizePhrase(phrase)
        guard isValidNormalizedPhrase(normalized) else {
            throw ArcaCryptoError.invalidRecoveryPhrase
        }
        let ikm = SymmetricKey(data: Data(normalized.utf8))
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: ikm,
            salt: salt,
            info: hkdfInfo,
            outputByteCount: 32
        )
    }

    /// Wraps a 256-bit Master Account Key (`MAK`) using this recovery key credential.
    public func wrapMasterAccountKey(
        _ masterAccountKey: SymmetricKey,
        makKeyId: UUID = UUID(),
        accountId: String
    ) throws -> WrappedRecoveryBundle {
        let saltKey = SymmetricKey(size: .bits256)
        let salt = saltKey.withUnsafeBytes { Data($0) }
        let wrappingKey = try Self.deriveWrappingKey(fromPhrase: formattedPhrase, salt: salt)
        let makBytes = masterAccountKey.withUnsafeBytes { Data($0) }
        let aad = Data("arca.recovery.mak.v1:\(accountId):\(makKeyId.uuidString)".utf8)
        let envelope = try ClientCryptoEngine.encryptPayload(
            makBytes,
            using: wrappingKey,
            keyId: makKeyId,
            aad: aad,
            aadDescription: "recovery-mak-wrap-v1"
        )
        return WrappedRecoveryBundle(
            accountId: accountId,
            makKeyId: makKeyId,
            hkdfSaltBase64: salt.base64EncodedString(),
            wrappedMAKEnvelope: envelope
        )
    }

    /// Restores the 256-bit Master Account Key (`MAK`) from a recovery phrase and `WrappedRecoveryBundle`.
    public static func restoreMasterAccountKey(
        fromPhrase phrase: String,
        bundle: WrappedRecoveryBundle
    ) throws -> SymmetricKey {
        guard let salt = Data(base64Encoded: bundle.hkdfSaltBase64), !salt.isEmpty else {
            throw ArcaCryptoError.corruptedEnvelopeField("hkdfSaltBase64")
        }
        let wrappingKey = try deriveWrappingKey(fromPhrase: phrase, salt: salt)
        let aad = Data("arca.recovery.mak.v1:\(bundle.accountId):\(bundle.makKeyId.uuidString)".utf8)
        let makData = try ClientCryptoEngine.decryptPayload(
            bundle.wrappedMAKEnvelope,
            using: wrappingKey,
            expectedAAD: aad
        )
        guard makData.count == 32 else {
            throw ArcaCryptoError.corruptedEnvelopeField("masterAccountKey")
        }
        return SymmetricKey(data: makData)
    }
}

// MARK: - Device Identity & Curve25519 Key Agreement

/// Public metadata for an enrolled sync device.
public struct EnrolledDeviceDescriptor: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String { deviceId }
    public let deviceId: String
    public var deviceName: String
    public let publicKeyBase64: String
    public let enrolledAt: Date
    public var isRevoked: Bool
    public var revokedAt: Date?

    public init(
        deviceId: String,
        deviceName: String,
        publicKeyBase64: String,
        enrolledAt: Date = Date(),
        isRevoked: Bool = false,
        revokedAt: Date? = nil
    ) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.publicKeyBase64 = publicKeyBase64
        self.enrolledAt = enrolledAt
        self.isRevoked = isRevoked
        self.revokedAt = revokedAt
    }
}

/// Encrypted bundle carrying the Master Account Key (`MAK`) wrapped via ECDH (`Curve25519`) + `HKDF<SHA256>`
/// from an existing enrolled device to a newly enrolled device.
public struct DeviceWrappedMasterKey: Codable, Sendable, Equatable, Hashable {
    public let senderDeviceId: String
    public let senderPublicKeyBase64: String
    public let recipientDeviceId: String
    public let recipientPublicKeyBase64: String
    public let makKeyId: UUID
    public let hkdfSaltBase64: String
    public let wrappedMAKEnvelope: EncryptedEnvelope

    public init(
        senderDeviceId: String,
        senderPublicKeyBase64: String,
        recipientDeviceId: String,
        recipientPublicKeyBase64: String,
        makKeyId: UUID,
        hkdfSaltBase64: String,
        wrappedMAKEnvelope: EncryptedEnvelope
    ) {
        self.senderDeviceId = senderDeviceId
        self.senderPublicKeyBase64 = senderPublicKeyBase64
        self.recipientDeviceId = recipientDeviceId
        self.recipientPublicKeyBase64 = recipientPublicKeyBase64
        self.makKeyId = makKeyId
        self.hkdfSaltBase64 = hkdfSaltBase64
        self.wrappedMAKEnvelope = wrappedMAKEnvelope
    }
}

/// Result of revoking a device and rotating a Space's Data Encryption Key (`SDEK`).
public struct DeviceRevocationRotationResult: Sendable, Equatable {
    public let revokedDeviceId: String
    public let rotatedSpaceKeyRing: SpaceKeyRing
    public let wrappedSpaceKeyRing: WrappedSpaceKeyRing
    public let userDisclosure: String

    public init(
        revokedDeviceId: String,
        rotatedSpaceKeyRing: SpaceKeyRing,
        wrappedSpaceKeyRing: WrappedSpaceKeyRing,
        userDisclosure: String = DeviceIdentity.revocationSecurityDisclosure
    ) {
        self.revokedDeviceId = revokedDeviceId
        self.rotatedSpaceKeyRing = rotatedSpaceKeyRing
        self.wrappedSpaceKeyRing = wrappedSpaceKeyRing
        self.userDisclosure = userDisclosure
    }
}

/// Represents a device's cryptographic identity using `Curve25519.KeyAgreement`.
/// Supports enrolling new devices by wrapping the Master Account Key (`MAK`) via ECDH + `HKDF<SHA256>`,
/// and rotating Space keys when a device is revoked.
public struct DeviceIdentity: Sendable {
    private static let keyAgreementInfoPrefix = "arca.device.enrollment.ecdh.v1"

    public let deviceId: String
    public var deviceName: String
    public let privateKey: Curve25519.KeyAgreement.PrivateKey
    public let publicKeyBase64: String
    public let enrolledAt: Date
    public var isRevoked: Bool

    /// Explicit disclosure explaining what device revocation guarantees and cannot guarantee.
    public static let revocationSecurityDisclosure: String =
        "Revoking a device immediately blocks its sync access tokens and rotates the Space encryption key for all future writes. " +
        "Note: Data already downloaded onto an offline revoked device cannot be remotely erased until that device reconnects."

    public init(
        deviceId: String = UUID().uuidString.lowercased(),
        deviceName: String,
        privateKey: Curve25519.KeyAgreement.PrivateKey = Curve25519.KeyAgreement.PrivateKey(),
        enrolledAt: Date = Date(),
        isRevoked: Bool = false
    ) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.privateKey = privateKey
        self.publicKeyBase64 = privateKey.publicKey.rawRepresentation.base64EncodedString()
        self.enrolledAt = enrolledAt
        self.isRevoked = isRevoked
    }

    public init(
        deviceId: String,
        deviceName: String,
        privateKeyRawBase64: String,
        enrolledAt: Date = Date(),
        isRevoked: Bool = false
    ) throws {
        guard let rawData = Data(base64Encoded: privateKeyRawBase64),
              let restoredKey = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: rawData) else {
            throw ArcaCryptoError.corruptedEnvelopeField("privateKeyRawBase64")
        }
        self.init(
            deviceId: deviceId,
            deviceName: deviceName,
            privateKey: restoredKey,
            enrolledAt: enrolledAt,
            isRevoked: isRevoked
        )
    }

    public var privateKeyRawBase64: String {
        privateKey.rawRepresentation.base64EncodedString()
    }

    public var descriptor: EnrolledDeviceDescriptor {
        EnrolledDeviceDescriptor(
            deviceId: deviceId,
            deviceName: deviceName,
            publicKeyBase64: publicKeyBase64,
            enrolledAt: enrolledAt,
            isRevoked: isRevoked
        )
    }

    /// Performs ECDH (`Curve25519`) + `HKDF<SHA256>` key agreement to wrap the Master Account Key (`MAK`)
    /// for a newly enrolled recipient device.
    public func wrapMasterAccountKey(
        _ masterAccountKey: SymmetricKey,
        makKeyId: UUID = UUID(),
        forRecipient recipient: EnrolledDeviceDescriptor
    ) throws -> DeviceWrappedMasterKey {
        guard !isRevoked else {
            throw ArcaCryptoError.deviceRevoked(deviceId: deviceId)
        }
        guard !recipient.isRevoked else {
            throw ArcaCryptoError.deviceRevoked(deviceId: recipient.deviceId)
        }
        guard let peerKeyData = Data(base64Encoded: recipient.publicKeyBase64),
              let peerPublicKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerKeyData) else {
            throw ArcaCryptoError.invalidPublicKey
        }

        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: peerPublicKey)
        let salt = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        let sharedInfo = Data("\(Self.keyAgreementInfoPrefix):\(deviceId)->\(recipient.deviceId)".utf8)
        let wrappingKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: salt,
            sharedInfo: sharedInfo,
            outputByteCount: 32
        )

        let makData = masterAccountKey.withUnsafeBytes { Data($0) }
        let aad = Data("arca.device.mak.v1:\(deviceId):\(recipient.deviceId):\(makKeyId.uuidString)".utf8)
        let envelope = try ClientCryptoEngine.encryptPayload(
            makData,
            using: wrappingKey,
            keyId: makKeyId,
            aad: aad,
            aadDescription: "device-enrollment-mak-v1"
        )

        return DeviceWrappedMasterKey(
            senderDeviceId: deviceId,
            senderPublicKeyBase64: publicKeyBase64,
            recipientDeviceId: recipient.deviceId,
            recipientPublicKeyBase64: recipient.publicKeyBase64,
            makKeyId: makKeyId,
            hkdfSaltBase64: salt.base64EncodedString(),
            wrappedMAKEnvelope: envelope
        )
    }

    /// Convenience overload accepting a peer `DeviceIdentity` directly.
    public func wrapMasterAccountKey(
        _ masterAccountKey: SymmetricKey,
        makKeyId: UUID = UUID(),
        forRecipientDevice recipient: DeviceIdentity
    ) throws -> DeviceWrappedMasterKey {
        try wrapMasterAccountKey(masterAccountKey, makKeyId: makKeyId, forRecipient: recipient.descriptor)
    }

    /// Unwraps the Master Account Key (`MAK`) on the newly enrolled recipient device using ECDH + `HKDF<SHA256>`.
    public func unwrapMasterAccountKey(from bundle: DeviceWrappedMasterKey) throws -> SymmetricKey {
        guard !isRevoked else {
            throw ArcaCryptoError.deviceRevoked(deviceId: deviceId)
        }
        guard bundle.recipientDeviceId == deviceId else {
            throw ArcaCryptoError.authenticationFailed
        }
        guard let senderKeyData = Data(base64Encoded: bundle.senderPublicKeyBase64),
              let senderPublicKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: senderKeyData) else {
            throw ArcaCryptoError.invalidPublicKey
        }
        guard let salt = Data(base64Encoded: bundle.hkdfSaltBase64), !salt.isEmpty else {
            throw ArcaCryptoError.corruptedEnvelopeField("hkdfSaltBase64")
        }

        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: senderPublicKey)
        let sharedInfo = Data("\(Self.keyAgreementInfoPrefix):\(bundle.senderDeviceId)->\(deviceId)".utf8)
        let wrappingKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: salt,
            sharedInfo: sharedInfo,
            outputByteCount: 32
        )

        let aad = Data("arca.device.mak.v1:\(bundle.senderDeviceId):\(deviceId):\(bundle.makKeyId.uuidString)".utf8)
        let makData = try ClientCryptoEngine.decryptPayload(
            bundle.wrappedMAKEnvelope,
            using: wrappingKey,
            expectedAAD: aad
        )
        guard makData.count == 32 else {
            throw ArcaCryptoError.corruptedEnvelopeField("masterAccountKey")
        }
        return SymmetricKey(data: makData)
    }

    /// Rotates a Space's encryption key when a device is revoked and wraps the new key ring under the Master Account Key.
    public static func rotateSpaceKey(
        currentKeyRing: SpaceKeyRing,
        revokingDeviceId: String,
        masterAccountKey: SymmetricKey,
        makKeyId: UUID = UUID()
    ) throws -> DeviceRevocationRotationResult {
        let nextRing = currentKeyRing.rotated()
        let wrapped = try nextRing.wrap(usingMasterAccountKey: masterAccountKey, makKeyId: makKeyId)
        return DeviceRevocationRotationResult(
            revokedDeviceId: revokingDeviceId,
            rotatedSpaceKeyRing: nextRing,
            wrappedSpaceKeyRing: wrapped
        )
    }
}

// MARK: - Client Crypto Engine

/// Provider-independent client-side cryptographic engine built on Apple `CryptoKit`.
/// Never logs plaintext records, schema labels, attachment filenames, or encryption keys.
public enum ClientCryptoEngine {
    /// Magic header bytes for passphrase-encrypted `.arcaarchive.enc` containers.
    private static let archiveMagicHeader = Data("ARCAENC1".utf8)
    private static let archiveHKDFInfo = Data("arca.archive.passphrase.hkdf.v1".utf8)
    private static let passphraseStretchingRounds = 4_096

    /// Generates a random 256-bit `SymmetricKey`.
    public static func generateSymmetricKey() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }

    /// Computes a lowercase hexadecimal SHA-256 digest of `data`.
    public static func sha256Hex(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Computes a lowercase hexadecimal HMAC-SHA256 authentication code of `data`.
    public static func hmacSHA256Hex(of data: Data, using key: SymmetricKey) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: key)
        return Data(mac).map { String(format: "%02x", $0) }.joined()
    }

    /// Encrypts raw bytes using `AES.GCM` (256-bit key, unique 96-bit nonce, 128-bit authentication tag) and binds `aad`.
    public static func encryptPayload(
        _ plaintext: Data,
        using key: SymmetricKey,
        keyId: UUID,
        aad: Data,
        aadDescription: String = "arca.payload.v1"
    ) throws -> EncryptedEnvelope {
        let nonce = AES.GCM.Nonce()
        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.seal(plaintext, using: key, nonce: nonce, authenticating: aad)
        } catch {
            throw ArcaCryptoError.encryptionFailed
        }

        let nonceData = nonce.withUnsafeBytes { Data($0) }
        return EncryptedEnvelope(
            version: EncryptedEnvelope.currentVersion,
            keyId: keyId,
            nonceBase64: nonceData.base64EncodedString(),
            ciphertextBase64: sealedBox.ciphertext.base64EncodedString(),
            tagBase64: sealedBox.tag.base64EncodedString(),
            aadDescription: aadDescription
        )
    }

    /// Decrypts and authenticates an `EncryptedEnvelope` using `AES.GCM` and verifies `expectedAAD`.
    public static func decryptPayload(
        _ envelope: EncryptedEnvelope,
        using key: SymmetricKey,
        expectedAAD: Data
    ) throws -> Data {
        guard envelope.version == EncryptedEnvelope.currentVersion else {
            throw ArcaCryptoError.unsupportedEnvelopeVersion(envelope.version)
        }
        guard let nonceData = Data(base64Encoded: envelope.nonceBase64),
              let nonce = try? AES.GCM.Nonce(data: nonceData) else {
            throw ArcaCryptoError.corruptedEnvelopeField("nonceBase64")
        }
        guard let ciphertext = Data(base64Encoded: envelope.ciphertextBase64) else {
            throw ArcaCryptoError.corruptedEnvelopeField("ciphertextBase64")
        }
        guard let tag = Data(base64Encoded: envelope.tagBase64) else {
            throw ArcaCryptoError.corruptedEnvelopeField("tagBase64")
        }

        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        } catch {
            throw ArcaCryptoError.corruptedEnvelopeField("sealedBox")
        }

        do {
            return try AES.GCM.open(sealedBox, using: key, authenticating: expectedAAD)
        } catch {
            throw ArcaCryptoError.authenticationFailed
        }
    }

    /// Canonical JSON encoder used for deterministic encrypted payload serialization.
    private static func makeCanonicalJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    /// Canonical JSON decoder used for encrypted payload deserialization.
    private static func makeCanonicalJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Encrypts any `Encodable` value (record, collection schema, attachment metadata) into an `EncryptedEnvelope`.
    public static func encryptCodable<T: Encodable>(
        _ value: T,
        using key: SymmetricKey,
        keyId: UUID,
        contextAAD: String
    ) throws -> EncryptedEnvelope {
        let encoder = makeCanonicalJSONEncoder()
        let data = try encoder.encode(value)
        let aadData = Data(contextAAD.utf8)
        return try encryptPayload(
            data,
            using: key,
            keyId: keyId,
            aad: aadData,
            aadDescription: "codable.v1"
        )
    }

    /// Decrypts any `Decodable` value from an `EncryptedEnvelope`, verifying `contextAAD`.
    public static func decryptCodable<T: Decodable>(
        _ type: T.Type,
        from envelope: EncryptedEnvelope,
        using key: SymmetricKey,
        contextAAD: String
    ) throws -> T {
        let aadData = Data(contextAAD.utf8)
        let plaintext = try decryptPayload(envelope, using: key, expectedAAD: aadData)
        let decoder = makeCanonicalJSONDecoder()
        return try decoder.decode(T.self, from: plaintext)
    }

    /// Derives a 256-bit encryption key from a user passphrase and 256-bit salt using iterated HMAC-SHA256 + `HKDF<SHA256>`.
    private static func deriveArchiveKey(passphrase: String, salt: Data) throws -> SymmetricKey {
        guard !passphrase.isEmpty else {
            throw ArcaCryptoError.invalidPassphrase
        }
        guard salt.count == 32 else {
            throw ArcaCryptoError.invalidArchiveContainer
        }

        let passphraseData = Data(passphrase.utf8)
        let initialKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: passphraseData),
            salt: salt,
            info: archiveHKDFInfo,
            outputByteCount: 32
        )

        var stretched = initialKey.withUnsafeBytes { Data($0) }
        for round in 0..<passphraseStretchingRounds {
            var roundInput = stretched
            var roundLE = UInt32(round).littleEndian
            withUnsafeBytes(of: &roundLE) { roundInput.append(contentsOf: $0) }
            roundInput.append(salt)
            let digest = HMAC<SHA256>.authenticationCode(for: roundInput, using: initialKey)
            stretched = Data(digest)
        }

        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: stretched),
            salt: salt,
            info: archiveHKDFInfo,
            outputByteCount: 32
        )
    }

    /// Encrypts portable `.arcaarchive` bundle data with a user-supplied passphrase.
    ///
    /// Binary container layout:
    /// - 8 bytes: Magic header `"ARCAENC1"`
    /// - 32 bytes: 256-bit random salt
    /// - 12 bytes: AES-GCM nonce
    /// - 16 bytes: AES-GCM authentication tag
    /// - N bytes: AES-GCM ciphertext
    public static func encryptArchiveWithPassphrase(
        _ archiveData: Data,
        passphrase: String,
        salt: Data? = nil
    ) throws -> Data {
        let effectiveSalt: Data
        if let providedSalt = salt {
            guard providedSalt.count == 32 else {
                throw ArcaCryptoError.invalidArchiveContainer
            }
            effectiveSalt = providedSalt
        } else {
            effectiveSalt = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        }

        let key = try deriveArchiveKey(passphrase: passphrase, salt: effectiveSalt)
        let nonce = AES.GCM.Nonce()
        let aad = archiveMagicHeader + effectiveSalt

        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.seal(archiveData, using: key, nonce: nonce, authenticating: aad)
        } catch {
            throw ArcaCryptoError.encryptionFailed
        }

        var container = Data()
        container.reserveCapacity(8 + 32 + 12 + 16 + sealedBox.ciphertext.count)
        container.append(archiveMagicHeader)
        container.append(effectiveSalt)
        container.append(nonce.withUnsafeBytes { Data($0) })
        container.append(sealedBox.tag)
        container.append(sealedBox.ciphertext)
        return container
    }

    /// Decrypts and verifies a passphrase-encrypted `.arcaarchive` container.
    public static func decryptArchiveWithPassphrase(
        _ encryptedData: Data,
        passphrase: String
    ) throws -> Data {
        let headerCount = archiveMagicHeader.count // 8
        let saltCount = 32
        let nonceCount = 12
        let tagCount = 16
        let minByteCount = headerCount + saltCount + nonceCount + tagCount

        guard encryptedData.count >= minByteCount else {
            throw ArcaCryptoError.invalidArchiveContainer
        }

        let header = encryptedData.subdata(in: 0..<headerCount)
        guard header == archiveMagicHeader else {
            throw ArcaCryptoError.invalidArchiveContainer
        }

        let saltRange = headerCount..<(headerCount + saltCount)
        let nonceRange = saltRange.upperBound..<(saltRange.upperBound + nonceCount)
        let tagRange = nonceRange.upperBound..<(nonceRange.upperBound + tagCount)
        let ciphertextRange = tagRange.upperBound..<encryptedData.count

        let salt = encryptedData.subdata(in: saltRange)
        let nonceData = encryptedData.subdata(in: nonceRange)
        let tagData = encryptedData.subdata(in: tagRange)
        let ciphertextData = encryptedData.subdata(in: ciphertextRange)

        let key = try deriveArchiveKey(passphrase: passphrase, salt: salt)
        guard let nonce = try? AES.GCM.Nonce(data: nonceData) else {
            throw ArcaCryptoError.invalidArchiveContainer
        }

        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertextData, tag: tagData)
        } catch {
            throw ArcaCryptoError.invalidArchiveContainer
        }

        let aad = archiveMagicHeader + salt
        do {
            return try AES.GCM.open(sealedBox, using: key, authenticating: aad)
        } catch {
            throw ArcaCryptoError.authenticationFailed
        }
    }
}

// MARK: - Keychain Key Store

/// Abstraction over local device key storage for Master Account Keys, Space Key Rings, and Device Identities.
public protocol KeychainKeyStore: Sendable {
    func saveKeyData(_ data: Data, forIdentifier identifier: String) throws
    func loadKeyData(forIdentifier identifier: String) throws -> Data?
    func deleteKeyData(forIdentifier identifier: String) throws
    func removeAllKeys() throws
}

extension KeychainKeyStore {
    /// Saves a 256-bit `SymmetricKey` under `identifier`.
    public func saveSymmetricKey(_ key: SymmetricKey, forIdentifier identifier: String) throws {
        let raw = key.withUnsafeBytes { Data($0) }
        try saveKeyData(raw, forIdentifier: identifier)
    }

    /// Loads a 256-bit `SymmetricKey` from `identifier`.
    public func loadSymmetricKey(forIdentifier identifier: String) throws -> SymmetricKey? {
        guard let data = try loadKeyData(forIdentifier: identifier) else {
            return nil
        }
        guard data.count == 32 else {
            throw ArcaCryptoError.corruptedEnvelopeField("keychainSymmetricKey")
        }
        return SymmetricKey(data: data)
    }

    /// Saves a `SpaceKeyRing` into the key store.
    public func saveSpaceKeyRing(_ keyRing: SpaceKeyRing) throws {
        let identifier = "space-key:\(keyRing.spaceId.uuidString):gen:\(keyRing.keyGeneration)"
        try saveKeyData(keyRing.rawKeyData, forIdentifier: identifier)
    }

    /// Loads a `SpaceKeyRing` from the key store.
    public func loadSpaceKeyRing(spaceId: UUID, keyGeneration: Int, keyId: UUID) throws -> SpaceKeyRing? {
        let identifier = "space-key:\(spaceId.uuidString):gen:\(keyGeneration)"
        guard let raw = try loadKeyData(forIdentifier: identifier) else {
            return nil
        }
        return try SpaceKeyRing(
            spaceId: spaceId,
            keyGeneration: keyGeneration,
            keyId: keyId,
            rawKeyData: raw
        )
    }
}

/// Thread-safe in-memory key store for deterministic unit testing and sandboxed environments.
public final class InMemoryKeyStore: KeychainKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]

    public init() {}

    public func saveKeyData(_ data: Data, forIdentifier identifier: String) throws {
        lock.lock()
        defer { lock.unlock() }
        storage[identifier] = data
    }

    public func loadKeyData(forIdentifier identifier: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return storage[identifier]
    }

    public func deleteKeyData(forIdentifier identifier: String) throws {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: identifier)
    }

    public func removeAllKeys() throws {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
    }

    public var storedIdentifiersCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage.count
    }
}

/// System Keychain implementation backed by Apple `Security` (`SecItemAdd` / `SecItemCopyMatching`)
/// using `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
public final class SystemKeychainKeyStore: KeychainKeyStore, Sendable {
    public let serviceName: String

    public init(serviceName: String = "app.arca.keystore") {
        self.serviceName = serviceName
    }

    public func saveKeyData(_ data: Data, forIdentifier identifier: String) throws {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: identifier
        ]
        // Update atomically: deleting first could lose existing keys if the subsequent write fails.
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw ArcaCryptoError.keychainFailure(status: updateStatus)
        }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw ArcaCryptoError.keychainFailure(status: status)
        }
    }

    public func loadKeyData(forIdentifier identifier: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: identifier,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw ArcaCryptoError.keychainFailure(status: status)
        }
        guard let data = item as? Data else {
            throw ArcaCryptoError.corruptedEnvelopeField("keychainData")
        }
        return data
    }

    public func deleteKeyData(forIdentifier identifier: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: identifier
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ArcaCryptoError.keychainFailure(status: status)
        }
    }

    public func removeAllKeys() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ArcaCryptoError.keychainFailure(status: status)
        }
    }
}

// MARK: - Server-Visible Metadata Disclosure Report

/// Transparent disclosure report detailing what metadata remains visible to a sync server under E2EE
/// versus what is strictly encrypted on the client before leaving the device.
public struct ServerVisibleMetadataReport: Codable, Sendable, Equatable {
    public struct MetadataItem: Codable, Sendable, Equatable, Identifiable {
        public var id: String { category }
        public let category: String
        public let details: String

        public init(category: String, details: String) {
            self.category = category
            self.details = details
        }
    }

    public let visibleToServer: [MetadataItem]
    public let strictlyHiddenFromServer: [MetadataItem]
    public let summaryDisclosure: String

    public init(
        visibleToServer: [MetadataItem],
        strictlyHiddenFromServer: [MetadataItem],
        summaryDisclosure: String
    ) {
        self.visibleToServer = visibleToServer
        self.strictlyHiddenFromServer = strictlyHiddenFromServer
        self.summaryDisclosure = summaryDisclosure
    }

    /// Standard report describing Arca Sync's End-to-End Encryption privacy boundary.
    public static let standardReport = ServerVisibleMetadataReport(
        visibleToServer: [
            MetadataItem(
                category: "Account Identifier",
                details: "Opaque account ID and subscription tier required to route sync envelopes and enforce plan quotas."
            ),
            MetadataItem(
                category: "Enrolled Device Count & Public Keys",
                details: "Number of active enrolled devices (e.g., 2-device free tier check), device IDs, and Curve25519 public keys."
            ),
            MetadataItem(
                category: "Ciphertext Byte Size",
                details: "Approximate byte length of encrypted record envelopes and encrypted attachment blobs."
            ),
            MetadataItem(
                category: "Opaque Entity UUIDs & Revisions",
                details: "Random UUIDs for spaces, schemas, records, and attachments alongside monotonic integer revision counters."
            ),
            MetadataItem(
                category: "Request Timestamps",
                details: "Server receipt timestamps and sync cursor positions when push or pull operations occur."
            )
        ],
        strictlyHiddenFromServer: [
            MetadataItem(
                category: "Record Field Values",
                details: "All text, notes, monetary amounts, dates, ratings, and select values are AES-GCM-256 encrypted on device."
            ),
            MetadataItem(
                category: "Collection Names & Space Titles",
                details: "Human-readable Space names, Collection titles, icons, and descriptions are encrypted before upload."
            ),
            MetadataItem(
                category: "Schema Labels & Field Definitions",
                details: "Custom field names, select option labels, and schema definitions are sealed inside encrypted envelopes."
            ),
            MetadataItem(
                category: "Attachment Filenames & Contents",
                details: "Photos, PDFs, receipts, and original filenames are encrypted on the client prior to transfer."
            ),
            MetadataItem(
                category: "Decryption Keys & Recovery Key",
                details: "Master Account Keys, Space Data Encryption Keys, and Recovery Keys never leave your devices in plaintext."
            )
        ],
        summaryDisclosure:
            "With End-to-End Encryption enabled, the sync server only sees opaque UUIDs, encrypted payload sizes, " +
            "enrolled device count, and request timestamps. Your record values, collection names, schema labels, " +
            "attachments, and decryption keys are never visible to Arca."
    )
}
