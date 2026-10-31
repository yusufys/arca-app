import Foundation
import CryptoKit
import ArcaCore
import ArcaCrypto
import ArcaPersistence

// MARK: - Sync Architectural Guarantees

/// Architectural policy flags for `ArcaSync`.
/// Explicitly guarantees that active SQLite database files (`space.sqlite`, `catalog.sqlite`)
/// are NEVER uploaded or overwritten as a synchronization strategy.
public enum ArcaSyncArchitecturePolicy {
    /// Arca never uploads or overwrites raw SQLite files over the network.
    public static let uploadsOrOverwritesRawSQLiteFiles: Bool = false

    /// Sync operates exclusively on structured, idempotent, client-encrypted operation envelopes.
    public static let usesIdempotentEncryptedOperationEnvelopes: Bool = true

    /// Default active device limit for Free accounts.
    public static let freeAccountMaxActiveDevices: Int = 2

    /// Default active device limit for Pro accounts.
    public static let proAccountMaxActiveDevices: Int = 10

    /// Disclosure explaining what device revocation guarantees and cannot guarantee.
    public static let deviceRevocationDisclosure: String = DeviceIdentity.revocationSecurityDisclosure
}

// MARK: - Enrolled Device & Receipts

/// Represents an enrolled device registered with an Arca Sync account.
public struct EnrolledDevice: Identifiable, Codable, Sendable, Equatable, Hashable {
    public var id: String { deviceId }
    public let deviceId: String
    public var deviceName: String
    public var platform: String
    public let publicKeyBase64: String
    public let enrolledAt: Date
    public var lastSyncAt: Date?
    public var isRevoked: Bool
    public var revokedAt: Date?

    public init(
        deviceId: String,
        deviceName: String,
        platform: String = "iOS",
        publicKeyBase64: String,
        enrolledAt: Date = Date(),
        lastSyncAt: Date? = nil,
        isRevoked: Bool = false,
        revokedAt: Date? = nil
    ) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.platform = platform
        self.publicKeyBase64 = publicKeyBase64
        self.enrolledAt = enrolledAt
        self.lastSyncAt = lastSyncAt
        self.isRevoked = isRevoked
        self.revokedAt = revokedAt
    }

    public init(descriptor: EnrolledDeviceDescriptor, platform: String = "iOS", lastSyncAt: Date? = nil) {
        self.deviceId = descriptor.deviceId
        self.deviceName = descriptor.deviceName
        self.platform = platform
        self.publicKeyBase64 = descriptor.publicKeyBase64
        self.enrolledAt = descriptor.enrolledAt
        self.lastSyncAt = lastSyncAt
        self.isRevoked = descriptor.isRevoked
        self.revokedAt = descriptor.revokedAt
    }

    public var descriptor: EnrolledDeviceDescriptor {
        EnrolledDeviceDescriptor(
            deviceId: deviceId,
            deviceName: deviceName,
            publicKeyBase64: publicKeyBase64,
            enrolledAt: enrolledAt,
            isRevoked: isRevoked,
            revokedAt: revokedAt
        )
    }
}

/// Session credentials returned after authenticating with the Arca Sync service.
public struct SyncAuthSession: Codable, Sendable, Equatable, Hashable {
    public let accountId: String
    public let email: String
    public let authToken: String
    public let maxAllowedDevices: Int
    public let storageQuotaBytes: Int64
    public let authenticatedAt: Date

    public init(
        accountId: String,
        email: String,
        authToken: String = UUID().uuidString,
        maxAllowedDevices: Int = ArcaSyncArchitecturePolicy.freeAccountMaxActiveDevices,
        storageQuotaBytes: Int64 = 250 * 1024 * 1024,
        authenticatedAt: Date = Date()
    ) {
        self.accountId = accountId
        self.email = email
        self.authToken = authToken
        self.maxAllowedDevices = maxAllowedDevices
        self.storageQuotaBytes = storageQuotaBytes
        self.authenticatedAt = authenticatedAt
    }
}

/// Receipt returned when enrolling a device on an Arca Sync account.
public struct DeviceEnrollmentReceipt: Codable, Sendable, Equatable, Hashable {
    public let accountId: String
    public let enrolledDevice: EnrolledDevice
    public let activeDevices: [EnrolledDevice]
    public let maxAllowedDevices: Int
    public let wrappedMasterKey: DeviceWrappedMasterKey?

    public init(
        accountId: String,
        enrolledDevice: EnrolledDevice,
        activeDevices: [EnrolledDevice],
        maxAllowedDevices: Int,
        wrappedMasterKey: DeviceWrappedMasterKey? = nil
    ) {
        self.accountId = accountId
        self.enrolledDevice = enrolledDevice
        self.activeDevices = activeDevices
        self.maxAllowedDevices = maxAllowedDevices
        self.wrappedMasterKey = wrappedMasterKey
    }
}

/// Receipt returned when revoking an enrolled device.
public struct DeviceRevocationReceipt: Codable, Sendable, Equatable, Hashable {
    public let accountId: String
    public let revokedDevice: EnrolledDevice
    public let remainingActiveDevices: [EnrolledDevice]
    public let rotatedSpaceKeys: [WrappedSpaceKeyRing]
    public let securityDisclosure: String
    public let revokedAt: Date

    public init(
        accountId: String,
        revokedDevice: EnrolledDevice,
        remainingActiveDevices: [EnrolledDevice],
        rotatedSpaceKeys: [WrappedSpaceKeyRing],
        securityDisclosure: String = ArcaSyncArchitecturePolicy.deviceRevocationDisclosure,
        revokedAt: Date = Date()
    ) {
        self.accountId = accountId
        self.revokedDevice = revokedDevice
        self.remainingActiveDevices = remainingActiveDevices
        self.rotatedSpaceKeys = rotatedSpaceKeys
        self.securityDisclosure = securityDisclosure
        self.revokedAt = revokedAt
    }
}

/// Receipt confirming remote deletion of a Space's encrypted data or an entire account.
public struct RemoteDeletionReceipt: Codable, Sendable, Equatable, Hashable {
    public let receiptId: UUID
    public let accountId: String
    public let deletedSpaceId: UUID?
    public let didDeleteEntireAccount: Bool
    public let purgedOperationsCount: Int
    public let purgedAttachmentsCount: Int
    public let purgedBytesCount: Int64
    public let verifiedZeroRemainingRecords: Bool
    public let deletedAt: Date

    public init(
        receiptId: UUID = UUID(),
        accountId: String,
        deletedSpaceId: UUID?,
        didDeleteEntireAccount: Bool,
        purgedOperationsCount: Int,
        purgedAttachmentsCount: Int,
        purgedBytesCount: Int64,
        verifiedZeroRemainingRecords: Bool = true,
        deletedAt: Date = Date()
    ) {
        self.receiptId = receiptId
        self.accountId = accountId
        self.deletedSpaceId = deletedSpaceId
        self.didDeleteEntireAccount = didDeleteEntireAccount
        self.purgedOperationsCount = purgedOperationsCount
        self.purgedAttachmentsCount = purgedAttachmentsCount
        self.purgedBytesCount = purgedBytesCount
        self.verifiedZeroRemainingRecords = verifiedZeroRemainingRecords
        self.deletedAt = deletedAt
    }
}

// MARK: - Sync Errors

/// Errors surfaced by `ArcaSync` operations.
/// Never logs or embeds user plaintext record values, schema labels, attachment names, or encryption keys.
public enum SyncServiceError: LocalizedError, Sendable, Equatable {
    case unauthenticated
    case offlineUnavailable
    case spaceIsNotConfiguredForSync(spaceId: UUID)
    case deviceNotEnrolled(deviceId: String)
    case deviceRevoked(deviceId: String)
    case deviceLimitReached(currentDevices: [EnrolledDevice], limit: Int)
    case storageQuotaExceeded(usedBytes: Int64, quotaBytes: Int64)
    case attachmentIntegrityMismatch(expectedSHA256: String, actualSHA256: String)
    case attachmentNotFound(attachmentId: UUID)
    case spaceKeyMismatch(expectedGeneration: Int, actualGeneration: Int)
    case invalidOperationEnvelope(String)
    case accountNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .unauthenticated:
            return "Sign in to Arca Sync to synchronize encrypted spaces."
        case .offlineUnavailable:
            return "Sync service is currently offline. Your changes are safely saved on this device and queued for sync."
        case .spaceIsNotConfiguredForSync:
            return "This Space is configured as Local-Only and never transmits data to Arca Sync."
        case .deviceNotEnrolled(let deviceId):
            return "Device \(deviceId.prefix(8)) is not enrolled for sync on this account."
        case .deviceRevoked(let deviceId):
            return "Device \(deviceId.prefix(8)) has been revoked and can no longer push or pull synced changes."
        case .deviceLimitReached(let currentDevices, let limit):
            return "Your account has reached the limit of \(limit) active synced devices (\(currentDevices.count) enrolled). Revoke an existing device or upgrade to Arca Pro to enroll this device. Your local records remain completely untouched."
        case .storageQuotaExceeded(let usedBytes, let quotaBytes):
            return "Encrypted cloud storage quota exceeded (\(usedBytes) / \(quotaBytes) bytes). Local records remain safe on this device."
        case .attachmentIntegrityMismatch:
            return "Encrypted attachment SHA-256 integrity verification failed."
        case .attachmentNotFound(let id):
            return "Encrypted attachment \(id.uuidString.prefix(8)) was not found on the sync server."
        case .spaceKeyMismatch(let expected, let actual):
            return "Space encryption key generation mismatch (expected gen \(expected), got gen \(actual))."
        case .invalidOperationEnvelope(let reason):
            return "Invalid sync operation envelope: \(reason)"
        case .accountNotFound(let accountId):
            return "Sync account \(accountId) was not found."
        }
    }
}

// MARK: - Sync Cursor & Retry Backoff Policy

/// Resumable, monotonic cursor for incremental pull pagination per Space.
public struct SyncCursor: Codable, Sendable, Equatable, Hashable, Comparable {
    public let sequenceNumber: Int64
    public let updatedAt: Date

    public static let initial = SyncCursor(sequenceNumber: 0, updatedAt: Date(timeIntervalSince1970: 0))

    public init(sequenceNumber: Int64, updatedAt: Date = Date()) {
        self.sequenceNumber = max(0, sequenceNumber)
        self.updatedAt = updatedAt
    }

    public static func < (lhs: SyncCursor, rhs: SyncCursor) -> Bool {
        lhs.sequenceNumber < rhs.sequenceNumber
    }
}

/// Deterministic exponential backoff policy for retrying transient outbox push/pull failures.
public struct RetryBackoffPolicy: Codable, Sendable, Equatable {
    public let baseDelaySeconds: TimeInterval
    public let multiplier: Double
    public let maxDelaySeconds: TimeInterval
    public let maxAttempts: Int

    public static let standard = RetryBackoffPolicy(
        baseDelaySeconds: 2.0,
        multiplier: 2.0,
        maxDelaySeconds: 300.0,
        maxAttempts: 10
    )

    public init(
        baseDelaySeconds: TimeInterval = 2.0,
        multiplier: Double = 2.0,
        maxDelaySeconds: TimeInterval = 300.0,
        maxAttempts: Int = 10
    ) {
        self.baseDelaySeconds = max(0.5, baseDelaySeconds)
        self.multiplier = max(1.1, multiplier)
        self.maxDelaySeconds = max(self.baseDelaySeconds, maxDelaySeconds)
        self.maxAttempts = max(1, maxAttempts)
    }

    /// Computes exponential backoff delay in seconds for the 1-indexed `attempt`.
    public func delaySeconds(forAttempt attempt: Int, deterministicJitterFraction: Double = 0.0) -> TimeInterval {
        let clampedAttempt = max(1, attempt)
        let exponent = Double(min(20, clampedAttempt - 1))
        let rawDelay = baseDelaySeconds * pow(multiplier, exponent)
        let capped = min(maxDelaySeconds, rawDelay)
        let clampedJitter = max(-0.25, min(0.25, deterministicJitterFraction))
        return max(baseDelaySeconds, min(maxDelaySeconds, capped * (1.0 + clampedJitter)))
    }

    public func nextRetryDate(forAttempt attempt: Int, from referenceDate: Date = Date()) -> Date {
        referenceDate.addingTimeInterval(delaySeconds(forAttempt: attempt))
    }

    public func shouldRetry(attempt: Int) -> Bool {
        attempt <= maxAttempts
    }
}

// MARK: - Encrypted Operation Envelopes & Attachment Blobs

/// Type of entity carried inside an `EncryptedSyncOperation`.
public enum SyncEntityType: String, Codable, Sendable, Equatable, Hashable {
    case collectionSchema = "collection_schema"
    case record = "record"
    case attachment = "attachment"
    case spaceMetadata = "space_metadata"
}

/// Client-encrypted sync operation envelope transmitted between devices and the sync service.
///
/// Security Properties:
/// - `operationId` is a stable UUID generated when the mutation is queued locally, guaranteeing idempotency across retries.
/// - Collection names, field labels, record values, and attachment metadata are sealed inside `encryptedEnvelope`
///   using `ClientCryptoEngine` (`AES.GCM` 256-bit) before leaving the client.
/// - `aadContextString` binds `spaceId`, `entityType`, `entityId`, `targetRevision`, and `isDeletedTombstone`
///   so server-side metadata tampering is detected during `AES.GCM.open`.
public struct EncryptedSyncOperation: Identifiable, Codable, Sendable, Equatable, Hashable {
    public var id: UUID { operationId }
    public let operationId: UUID
    public let spaceId: UUID
    public let collectionId: UUID?
    public let entityType: SyncEntityType
    public let entityId: UUID
    public let baseRevision: Int64
    public let targetRevision: Int64
    public let isDeletedTombstone: Bool
    public let authorDeviceId: String
    public let keyGeneration: Int
    public let encryptedEnvelope: EncryptedEnvelope
    public let createdAt: Date
    public var serverSequenceNumber: Int64?

    public init(
        operationId: UUID = UUID(),
        spaceId: UUID,
        collectionId: UUID? = nil,
        entityType: SyncEntityType,
        entityId: UUID,
        baseRevision: Int64,
        targetRevision: Int64,
        isDeletedTombstone: Bool,
        authorDeviceId: String,
        keyGeneration: Int,
        encryptedEnvelope: EncryptedEnvelope,
        createdAt: Date = Date(),
        serverSequenceNumber: Int64? = nil
    ) {
        self.operationId = operationId
        self.spaceId = spaceId
        self.collectionId = collectionId
        self.entityType = entityType
        self.entityId = entityId
        self.baseRevision = baseRevision
        self.targetRevision = targetRevision
        self.isDeletedTombstone = isDeletedTombstone
        self.authorDeviceId = authorDeviceId
        self.keyGeneration = keyGeneration
        self.encryptedEnvelope = encryptedEnvelope
        self.createdAt = createdAt
        self.serverSequenceNumber = serverSequenceNumber
    }

    /// Canonical Authenticated Additional Data (AAD) string binding envelope headers to the ciphertext.
    public static func makeAADContext(
        spaceId: UUID,
        entityType: SyncEntityType,
        entityId: UUID,
        targetRevision: Int64,
        isDeletedTombstone: Bool
    ) -> String {
        "arca.sync.op.v1:\(spaceId.uuidString):\(entityType.rawValue):\(entityId.uuidString):rev:\(targetRevision):del:\(isDeletedTombstone)"
    }

    public var aadContextString: String {
        Self.makeAADContext(
            spaceId: spaceId,
            entityType: entityType,
            entityId: entityId,
            targetRevision: targetRevision,
            isDeletedTombstone: isDeletedTombstone
        )
    }

    /// Encrypts a `RecordItem` (including deletion tombstones where `record.isDeleted == true`) into an `EncryptedSyncOperation`.
    public static func encryptRecordOperation(
        operationId: UUID = UUID(),
        record: RecordItem,
        baseRevision: Int64,
        authorDeviceId: String,
        spaceKeyRing: SpaceKeyRing,
        createdAt: Date = Date()
    ) throws -> EncryptedSyncOperation {
        let aad = makeAADContext(
            spaceId: record.spaceId,
            entityType: .record,
            entityId: record.id,
            targetRevision: record.revision,
            isDeletedTombstone: record.isDeleted
        )
        let envelope = try ClientCryptoEngine.encryptCodable(
            record,
            using: spaceKeyRing.symmetricKey,
            keyId: spaceKeyRing.keyId,
            contextAAD: aad
        )
        return EncryptedSyncOperation(
            operationId: operationId,
            spaceId: record.spaceId,
            collectionId: record.collectionId,
            entityType: .record,
            entityId: record.id,
            baseRevision: baseRevision,
            targetRevision: record.revision,
            isDeletedTombstone: record.isDeleted,
            authorDeviceId: authorDeviceId,
            keyGeneration: spaceKeyRing.keyGeneration,
            encryptedEnvelope: envelope,
            createdAt: createdAt
        )
    }

    /// Decrypts a `RecordItem` from this operation using the Space's `SpaceKeyRing`.
    public func decryptRecord(using spaceKeyRing: SpaceKeyRing) throws -> RecordItem {
        guard entityType == .record else {
            throw SyncServiceError.invalidOperationEnvelope("Expected record operation, found \(entityType.rawValue).")
        }
        guard spaceKeyRing.keyId == encryptedEnvelope.keyId else {
            throw ArcaCryptoError.keyIdMismatch(expected: spaceKeyRing.keyId, actual: encryptedEnvelope.keyId)
        }
        return try ClientCryptoEngine.decryptCodable(
            RecordItem.self,
            from: encryptedEnvelope,
            using: spaceKeyRing.symmetricKey,
            contextAAD: aadContextString
        )
    }

    /// Encrypts a `CollectionSchema` (hiding collection name and all field definitions/labels from the server)
    /// into an `EncryptedSyncOperation`.
    public static func encryptSchemaOperation(
        operationId: UUID = UUID(),
        schema: CollectionSchema,
        baseRevision: Int64,
        authorDeviceId: String,
        spaceKeyRing: SpaceKeyRing,
        createdAt: Date = Date()
    ) throws -> EncryptedSyncOperation {
        let aad = makeAADContext(
            spaceId: schema.spaceId,
            entityType: .collectionSchema,
            entityId: schema.id,
            targetRevision: schema.revision,
            isDeletedTombstone: schema.isDeleted
        )
        let envelope = try ClientCryptoEngine.encryptCodable(
            schema,
            using: spaceKeyRing.symmetricKey,
            keyId: spaceKeyRing.keyId,
            contextAAD: aad
        )
        return EncryptedSyncOperation(
            operationId: operationId,
            spaceId: schema.spaceId,
            collectionId: schema.id,
            entityType: .collectionSchema,
            entityId: schema.id,
            baseRevision: baseRevision,
            targetRevision: schema.revision,
            isDeletedTombstone: schema.isDeleted,
            authorDeviceId: authorDeviceId,
            keyGeneration: spaceKeyRing.keyGeneration,
            encryptedEnvelope: envelope,
            createdAt: createdAt
        )
    }

    /// Decrypts a `CollectionSchema` from this operation using the Space's `SpaceKeyRing`.
    public func decryptSchema(using spaceKeyRing: SpaceKeyRing) throws -> CollectionSchema {
        guard entityType == .collectionSchema else {
            throw SyncServiceError.invalidOperationEnvelope("Expected collectionSchema operation, found \(entityType.rawValue).")
        }
        guard spaceKeyRing.keyId == encryptedEnvelope.keyId else {
            throw ArcaCryptoError.keyIdMismatch(expected: spaceKeyRing.keyId, actual: encryptedEnvelope.keyId)
        }
        return try ClientCryptoEngine.decryptCodable(
            CollectionSchema.self,
            from: encryptedEnvelope,
            using: spaceKeyRing.symmetricKey,
            contextAAD: aadContextString
        )
    }
}

/// Encrypted attachment payload with dual SHA-256 verification (ciphertext digest for server transport
/// + plaintext digest inside authenticated metadata for client verification).
public struct EncryptedAttachmentBlob: Identifiable, Codable, Sendable, Equatable, Hashable {
    public var id: UUID { attachmentId }
    public let attachmentId: UUID
    public let spaceId: UUID
    public let recordId: UUID
    public let authorDeviceId: String
    public let keyGeneration: Int
    public let ciphertextSHA256Hex: String
    public let encryptedMetadataEnvelope: EncryptedEnvelope
    public let encryptedDataEnvelope: EncryptedEnvelope
    public let uploadedAt: Date

    public init(
        attachmentId: UUID,
        spaceId: UUID,
        recordId: UUID,
        authorDeviceId: String,
        keyGeneration: Int,
        ciphertextSHA256Hex: String,
        encryptedMetadataEnvelope: EncryptedEnvelope,
        encryptedDataEnvelope: EncryptedEnvelope,
        uploadedAt: Date = Date()
    ) {
        self.attachmentId = attachmentId
        self.spaceId = spaceId
        self.recordId = recordId
        self.authorDeviceId = authorDeviceId
        self.keyGeneration = keyGeneration
        self.ciphertextSHA256Hex = ciphertextSHA256Hex
        self.encryptedMetadataEnvelope = encryptedMetadataEnvelope
        self.encryptedDataEnvelope = encryptedDataEnvelope
        self.uploadedAt = uploadedAt
    }

    public var approximateCiphertextBytes: Int64 {
        Int64(encryptedMetadataEnvelope.approximateCiphertextByteCount + encryptedDataEnvelope.approximateCiphertextByteCount)
    }

    private static func metadataAAD(spaceId: UUID, recordId: UUID, attachmentId: UUID) -> String {
        "arca.sync.att.meta.v1:\(spaceId.uuidString):\(recordId.uuidString):\(attachmentId.uuidString)"
    }

    private static func dataAAD(spaceId: UUID, recordId: UUID, attachmentId: UUID) -> Data {
        Data("arca.sync.att.data.v1:\(spaceId.uuidString):\(recordId.uuidString):\(attachmentId.uuidString)".utf8)
    }

    /// Encrypts an `AttachmentReference` and its raw binary data client-side, verifying SHA-256 integrity before encryption.
    public static func encryptAttachment(
        reference: AttachmentReference,
        rawData: Data,
        spaceId: UUID,
        recordId: UUID,
        authorDeviceId: String,
        spaceKeyRing: SpaceKeyRing
    ) throws -> EncryptedAttachmentBlob {
        let actualPlaintextHash = ClientCryptoEngine.sha256Hex(of: rawData)
        guard actualPlaintextHash.lowercased() == reference.sha256Hex.lowercased() else {
            throw SyncServiceError.attachmentIntegrityMismatch(
                expectedSHA256: reference.sha256Hex,
                actualSHA256: actualPlaintextHash
            )
        }

        var syncedRef = reference
        syncedRef.uploadState = .uploadedVerified

        let metaAAD = metadataAAD(spaceId: spaceId, recordId: recordId, attachmentId: reference.id)
        let metaEnvelope = try ClientCryptoEngine.encryptCodable(
            syncedRef,
            using: spaceKeyRing.symmetricKey,
            keyId: spaceKeyRing.keyId,
            contextAAD: metaAAD
        )

        let payloadAAD = dataAAD(spaceId: spaceId, recordId: recordId, attachmentId: reference.id)
        let dataEnvelope = try ClientCryptoEngine.encryptPayload(
            rawData,
            using: spaceKeyRing.symmetricKey,
            keyId: spaceKeyRing.keyId,
            aad: payloadAAD,
            aadDescription: "attachment-data-v1"
        )

        let ciphertextBytes = Data((dataEnvelope.ciphertextBase64 + ":" + dataEnvelope.tagBase64).utf8)
        let ciphertextHash = ClientCryptoEngine.sha256Hex(of: ciphertextBytes)

        return EncryptedAttachmentBlob(
            attachmentId: reference.id,
            spaceId: spaceId,
            recordId: recordId,
            authorDeviceId: authorDeviceId,
            keyGeneration: spaceKeyRing.keyGeneration,
            ciphertextSHA256Hex: ciphertextHash,
            encryptedMetadataEnvelope: metaEnvelope,
            encryptedDataEnvelope: dataEnvelope
        )
    }

    /// Verifies ciphertext SHA-256, decrypts both the attachment metadata and binary data, and verifies plaintext SHA-256.
    public func decryptAndVerify(using spaceKeyRing: SpaceKeyRing) throws -> (reference: AttachmentReference, data: Data) {
        let ciphertextBytes = Data((encryptedDataEnvelope.ciphertextBase64 + ":" + encryptedDataEnvelope.tagBase64).utf8)
        let computedCiphertextHash = ClientCryptoEngine.sha256Hex(of: ciphertextBytes)
        guard computedCiphertextHash.lowercased() == ciphertextSHA256Hex.lowercased() else {
            throw SyncServiceError.attachmentIntegrityMismatch(
                expectedSHA256: ciphertextSHA256Hex,
                actualSHA256: computedCiphertextHash
            )
        }

        let metaAAD = Self.metadataAAD(spaceId: spaceId, recordId: recordId, attachmentId: attachmentId)
        let reference = try ClientCryptoEngine.decryptCodable(
            AttachmentReference.self,
            from: encryptedMetadataEnvelope,
            using: spaceKeyRing.symmetricKey,
            contextAAD: metaAAD
        )

        let payloadAAD = Self.dataAAD(spaceId: spaceId, recordId: recordId, attachmentId: attachmentId)
        let plaintextData = try ClientCryptoEngine.decryptPayload(
            encryptedDataEnvelope,
            using: spaceKeyRing.symmetricKey,
            expectedAAD: payloadAAD
        )

        let computedPlaintextHash = ClientCryptoEngine.sha256Hex(of: plaintextData)
        guard computedPlaintextHash.lowercased() == reference.sha256Hex.lowercased() else {
            throw SyncServiceError.attachmentIntegrityMismatch(
                expectedSHA256: reference.sha256Hex,
                actualSHA256: computedPlaintextHash
            )
        }

        return (reference, plaintextData)
    }
}

/// Receipt returned by `pushEncryptedOperations`.
public struct SyncPushReceipt: Codable, Sendable, Equatable, Hashable {
    public let spaceId: UUID
    public let acceptedOperationIds: [UUID]
    public let deduplicatedOperationIds: [UUID]
    public let latestCursor: SyncCursor
    public let totalAccountBytesUsed: Int64

    public init(
        spaceId: UUID,
        acceptedOperationIds: [UUID],
        deduplicatedOperationIds: [UUID],
        latestCursor: SyncCursor,
        totalAccountBytesUsed: Int64
    ) {
        self.spaceId = spaceId
        self.acceptedOperationIds = acceptedOperationIds
        self.deduplicatedOperationIds = deduplicatedOperationIds
        self.latestCursor = latestCursor
        self.totalAccountBytesUsed = totalAccountBytesUsed
    }
}

/// Batch of encrypted operations returned by `pullEncryptedOperations(sinceCursor:)`.
public struct SyncPullBatch: Codable, Sendable, Equatable, Hashable {
    public let spaceId: UUID
    public let operations: [EncryptedSyncOperation]
    public let nextCursor: SyncCursor
    public let hasMore: Bool
    public let latestWrappedSpaceKey: WrappedSpaceKeyRing?

    public init(
        spaceId: UUID,
        operations: [EncryptedSyncOperation],
        nextCursor: SyncCursor,
        hasMore: Bool,
        latestWrappedSpaceKey: WrappedSpaceKeyRing? = nil
    ) {
        self.spaceId = spaceId
        self.operations = operations
        self.nextCursor = nextCursor
        self.hasMore = hasMore
        self.latestWrappedSpaceKey = latestWrappedSpaceKey
    }
}

// MARK: - Conflict Detection & Preservation (No Silent Overwrites, No Wall-Clock Trust)

/// Represents a preserved conflict when two devices concurrently modify the same field of a record
/// (or when one device edits a record while another device deletes it).
///
/// Both `localRecord` and `remoteRecord` are preserved intact so zero user information is lost.
public struct SyncConflict: Identifiable, Codable, Sendable, Equatable, Hashable {
    public let id: UUID
    public let spaceId: UUID
    public let collectionId: UUID
    public let recordId: UUID
    public let baseRevision: Int64
    public let localRecord: RecordItem
    public let remoteRecord: RecordItem
    public let conflictingFieldIds: [UUID]
    public let isEditVsDeleteConflict: Bool
    public let detectedAt: Date

    public init(
        id: UUID = UUID(),
        spaceId: UUID,
        collectionId: UUID,
        recordId: UUID,
        baseRevision: Int64,
        localRecord: RecordItem,
        remoteRecord: RecordItem,
        conflictingFieldIds: [UUID],
        isEditVsDeleteConflict: Bool = false,
        detectedAt: Date = Date()
    ) {
        self.id = id
        self.spaceId = spaceId
        self.collectionId = collectionId
        self.recordId = recordId
        self.baseRevision = baseRevision
        self.localRecord = localRecord
        self.remoteRecord = remoteRecord
        self.conflictingFieldIds = conflictingFieldIds
        self.isEditVsDeleteConflict = isEditVsDeleteConflict
        self.detectedAt = detectedAt
    }
}

/// User-selected resolution strategy for a `SyncConflict`.
public enum ConflictResolutionChoice: Sendable, Equatable {
    /// Keep the local version of the record and advance the revision past both local and remote.
    case keepLocal
    /// Accept the remote version of the record and advance the revision past both local and remote.
    case keepRemote
    /// Merge specific field values chosen by the user while preserving non-conflicting fields.
    case mergeFields([UUID: FieldValue])
}

/// Outcome of reconciling an incoming remote `RecordItem` with the local `RecordItem` state.
public enum RecordReconcileOutcome: Sendable, Equatable {
    case cleanNoChange(RecordItem)
    case cleanRemoteApplied(RecordItem)
    case cleanFieldLevelMerge(mergedRecord: RecordItem)
    case conflictPreserved(SyncConflict)
}

/// Deterministic conflict detection and field-level merge engine.
///
/// Authority Rules:
/// 1. Never relies on client wall-clock `updatedAt` timestamps to pick a winner.
/// 2. Uses monotonic `revision` and `baseRevision` plus `lastModifiedByDeviceId`.
/// 3. If the local record has no uncommitted edits (`!hasUncommittedLocalEdits`), a higher-revision remote record applies cleanly.
/// 4. If both devices concurrently edited the same record relative to `baseRecord` (or `baseRevision`):
///    - If one device deleted the record (`isDeleted = true`) while the other modified fields (`isDeleted = false`),
///      preserves both in a `SyncConflict` (`isEditVsDeleteConflict = true`).
///    - If both devices edited **disjoint** fields, merges all changed fields cleanly into a unified `RecordItem`.
///    - If both devices edited the **same** field to different values, creates a `SyncConflict` listing the exact `conflictingFieldIds`.
public enum SyncConflictEngine {

    public static func reconcileRecord(
        localRecord: RecordItem?,
        remoteRecord: RecordItem,
        baseRecordSnapshot: RecordItem? = nil,
        localBaseRevision: Int64? = nil,
        hasUncommittedLocalEdits: Bool
    ) -> RecordReconcileOutcome {
        // Case 1: Record does not exist locally yet -> apply remote directly
        guard let local = localRecord else {
            return .cleanRemoteApplied(remoteRecord)
        }

        // Case 2: Identical payload & deletion state -> no-op (advance revision if remote is newer)
        if local.values == remoteRecord.values && local.isDeleted == remoteRecord.isDeleted && local.isFavorite == remoteRecord.isFavorite {
            if remoteRecord.revision > local.revision {
                return .cleanRemoteApplied(remoteRecord)
            }
            return .cleanNoChange(local)
        }

        // Case 3: Local record has NO uncommitted outbox edits -> fast-forward to remote if remote revision >= local revision
        if !hasUncommittedLocalEdits {
            if remoteRecord.revision >= local.revision {
                return .cleanRemoteApplied(remoteRecord)
            } else {
                return .cleanNoChange(local)
            }
        }

        // Case 4: Concurrent edits exist on both local and remote!
        let effectiveBaseRevision = localBaseRevision ?? baseRecordSnapshot?.revision ?? min(local.revision, remoteRecord.revision) - 1

        // Subcase 4a: Edit vs. Delete conflict (one side is a tombstone, the other side is an active edit)
        if local.isDeleted != remoteRecord.isDeleted {
            if local.isDeleted && remoteRecord.isDeleted {
                return .cleanRemoteApplied(remoteRecord)
            }
            let allFieldIds = Array(Set(local.values.keys).union(remoteRecord.values.keys)).sorted {
                $0.uuidString < $1.uuidString
            }
            let conflict = SyncConflict(
                spaceId: remoteRecord.spaceId,
                collectionId: remoteRecord.collectionId,
                recordId: remoteRecord.id,
                baseRevision: effectiveBaseRevision,
                localRecord: local,
                remoteRecord: remoteRecord,
                conflictingFieldIds: allFieldIds,
                isEditVsDeleteConflict: true
            )
            return .conflictPreserved(conflict)
        }

        // Subcase 4b: Both sides edited fields on a non-deleted record.
        // Determine which fields changed on each side relative to `baseRecordSnapshot` (if available)
        // or compare field-by-field between `local` and `remoteRecord`.
        let baseKeys: [UUID] = baseRecordSnapshot.map { Array($0.values.keys) } ?? []
        let allFieldKeys = Set(local.values.keys)
            .union(remoteRecord.values.keys)
            .union(baseKeys)

        var mergedValues: [UUID: FieldValue] = baseRecordSnapshot?.values ?? [:]
        var conflictingFields: [UUID] = []

        for fieldId in allFieldKeys.sorted(by: { $0.uuidString < $1.uuidString }) {
            let localVal = local.values[fieldId] ?? .null
            let remoteVal = remoteRecord.values[fieldId] ?? .null

            if localVal == remoteVal {
                if localVal != .null {
                    mergedValues[fieldId] = localVal
                } else {
                    mergedValues.removeValue(forKey: fieldId)
                }
                continue
            }

            if let base = baseRecordSnapshot {
                let baseVal = base.values[fieldId] ?? .null
                let localChanged = (localVal != baseVal)
                let remoteChanged = (remoteVal != baseVal)

                if localChanged && !remoteChanged {
                    // Only local device modified this field
                    if localVal != .null {
                        mergedValues[fieldId] = localVal
                    } else {
                        mergedValues.removeValue(forKey: fieldId)
                    }
                } else if !localChanged && remoteChanged {
                    // Only remote device modified this field
                    if remoteVal != .null {
                        mergedValues[fieldId] = remoteVal
                    } else {
                        mergedValues.removeValue(forKey: fieldId)
                    }
                } else {
                    // Both devices modified the same field to different values!
                    conflictingFields.append(fieldId)
                }
            } else {
                // Without a base snapshot, if one side is `.null` (untouched optional field) and the other has a value,
                // treat as disjoint field population; if both have distinct non-null values, flag as a conflict.
                if localVal.isNullOrEmpty && !remoteVal.isNullOrEmpty {
                    mergedValues[fieldId] = remoteVal
                } else if !localVal.isNullOrEmpty && remoteVal.isNullOrEmpty {
                    mergedValues[fieldId] = localVal
                } else {
                    conflictingFields.append(fieldId)
                }
            }
        }

        if conflictingFields.isEmpty {
            let nextRevision = max(local.revision, remoteRecord.revision) + 1
            let merged = RecordItem(
                id: local.id,
                spaceId: local.spaceId,
                collectionId: local.collectionId,
                schemaVersionAtWrite: max(local.schemaVersionAtWrite, remoteRecord.schemaVersionAtWrite),
                values: mergedValues,
                isFavorite: local.isFavorite || remoteRecord.isFavorite,
                createdAt: min(local.createdAt, remoteRecord.createdAt),
                updatedAt: Date(),
                revision: nextRevision,
                lastModifiedByDeviceId: local.lastModifiedByDeviceId,
                isDeleted: false
            )
            return .cleanFieldLevelMerge(mergedRecord: merged)
        } else {
            let conflict = SyncConflict(
                spaceId: local.spaceId,
                collectionId: local.collectionId,
                recordId: local.id,
                baseRevision: effectiveBaseRevision,
                localRecord: local,
                remoteRecord: remoteRecord,
                conflictingFieldIds: conflictingFields,
                isEditVsDeleteConflict: false
            )
            return .conflictPreserved(conflict)
        }
    }

    /// Resolves a preserved `SyncConflict` using the user's explicit `ConflictResolutionChoice`.
    public static func resolveConflict(
        _ conflict: SyncConflict,
        choice: ConflictResolutionChoice,
        resolvedByDeviceId: String
    ) -> RecordItem {
        let nextRevision = max(conflict.localRecord.revision, conflict.remoteRecord.revision) + 1
        switch choice {
        case .keepLocal:
            var resolved = conflict.localRecord
            resolved.revision = nextRevision
            resolved.updatedAt = Date()
            resolved.lastModifiedByDeviceId = resolvedByDeviceId
            return resolved

        case .keepRemote:
            var resolved = conflict.remoteRecord
            resolved.revision = nextRevision
            resolved.updatedAt = Date()
            resolved.lastModifiedByDeviceId = resolvedByDeviceId
            return resolved

        case .mergeFields(let chosenValues):
            var combinedValues = conflict.remoteRecord.values
            for (k, v) in conflict.localRecord.values where combinedValues[k] == nil {
                combinedValues[k] = v
            }
            for (k, v) in chosenValues {
                if v == .null {
                    combinedValues.removeValue(forKey: k)
                } else {
                    combinedValues[k] = v
                }
            }
            return RecordItem(
                id: conflict.recordId,
                spaceId: conflict.spaceId,
                collectionId: conflict.collectionId,
                schemaVersionAtWrite: max(conflict.localRecord.schemaVersionAtWrite, conflict.remoteRecord.schemaVersionAtWrite),
                values: combinedValues,
                isFavorite: conflict.localRecord.isFavorite || conflict.remoteRecord.isFavorite,
                createdAt: min(conflict.localRecord.createdAt, conflict.remoteRecord.createdAt),
                updatedAt: Date(),
                revision: nextRevision,
                lastModifiedByDeviceId: resolvedByDeviceId,
                isDeleted: false
            )
        }
    }
}

// MARK: - Explicit Sync Backend Protocol

/// Explicit contract for the Arca Sync backend service.
///
/// All payloads crossing this boundary (`EncryptedSyncOperation`, `EncryptedAttachmentBlob`, `WrappedSpaceKeyRing`)
/// are encrypted on the client prior to invocation.
public protocol ArcaSyncBackendProtocol: Sendable {
    // 1. Authentication & Account Deletion
    func authenticate(
        email: String,
        credentialProof: String,
        maxAllowedDevices: Int,
        storageQuotaBytes: Int64
    ) async throws -> SyncAuthSession

    func deleteAccountAndRemoteData(accountId: String) async throws -> RemoteDeletionReceipt

    // 2. Device Enrollment & Revocation (2-Device Free Limit Enforcement)
    func enrollDevice(
        accountId: String,
        device: EnrolledDevice,
        maxAllowedDevices: Int,
        wrappedMasterKey: DeviceWrappedMasterKey?
    ) async throws -> DeviceEnrollmentReceipt

    func listEnrolledDevices(accountId: String) async throws -> [EnrolledDevice]

    func revokeDevice(
        accountId: String,
        revokingDeviceId: String,
        requestedByDeviceId: String,
        rotatedSpaceKeys: [WrappedSpaceKeyRing]
    ) async throws -> DeviceRevocationReceipt

    // 3. Space Key Ring Distribution
    func publishWrappedSpaceKey(
        accountId: String,
        deviceId: String,
        wrappedSpaceKey: WrappedSpaceKeyRing
    ) async throws

    func fetchLatestWrappedSpaceKey(
        accountId: String,
        spaceId: UUID,
        deviceId: String
    ) async throws -> WrappedSpaceKeyRing?

    // 4. Idempotent Push & Resumable Incremental Pull
    func pushEncryptedOperations(
        accountId: String,
        spaceId: UUID,
        deviceId: String,
        operations: [EncryptedSyncOperation]
    ) async throws -> SyncPushReceipt

    func pullEncryptedOperations(
        accountId: String,
        spaceId: UUID,
        deviceId: String,
        sinceCursor: SyncCursor?,
        limit: Int
    ) async throws -> SyncPullBatch

    // 5. Encrypted Attachment Upload & Download with SHA-256 Verification
    func uploadEncryptedAttachment(
        accountId: String,
        deviceId: String,
        blob: EncryptedAttachmentBlob
    ) async throws

    func downloadEncryptedAttachment(
        accountId: String,
        spaceId: UUID,
        attachmentId: UUID,
        deviceId: String
    ) async throws -> EncryptedAttachmentBlob

    // 6. Remote Space Deletion Verification
    func deleteRemoteSpaceData(
        accountId: String,
        spaceId: UUID,
        requestedByDeviceId: String
    ) async throws -> RemoteDeletionReceipt
}

// MARK: - Local Development / Multi-Device Integration Test Backend

/// Deterministic in-memory implementation of `ArcaSyncBackendProtocol` for local development,
/// offline/online simulation, and multi-device E2EE integration testing.
///
/// Enforces:
/// - 2 active devices per Free account (`maxAllowedDevices = 2` by default, `10` for Pro).
/// - Strict device revocation checks blocking pushes/pulls/uploads from revoked devices.
/// - 100% idempotency on `operationId` so retried pushes never duplicate records.
/// - Ciphertext SHA-256 integrity checks on attachment uploads.
public actor InMemoryArcaSyncBackend: ArcaSyncBackendProtocol {
    private struct AccountState {
        var session: SyncAuthSession
        var devices: [EnrolledDevice]
        var wrappedMasterKeysByRecipient: [String: DeviceWrappedMasterKey]
        var wrappedSpaceKeys: [UUID: [WrappedSpaceKeyRing]]
        var operationsBySpace: [UUID: [EncryptedSyncOperation]]
        var operationSequenceByOperationId: [UUID: Int64]
        var nextSequenceBySpace: [UUID: Int64]
        var attachmentsBySpace: [UUID: [UUID: EncryptedAttachmentBlob]]
    }

    public nonisolated let isLocalTestAndDevelopmentBackend: Bool = true
    private var accounts: [String: AccountState] = [:]
    private var defaultAccountId: String = "default-arca-account"
    private var isSimulatedOffline: Bool = false

    public init() {}

    /// Toggles simulated network offline mode for testing offline outbox queuing and retry recovery.
    public func setSimulatedOffline(_ offline: Bool) {
        self.isSimulatedOffline = offline
    }

    public func simulatedOfflineState() -> Bool {
        isSimulatedOffline
    }

    /// Updates the account's device limit and storage quota (e.g., when upgrading to Pro or expiring to Free).
    public func updateAccountQuotas(
        accountId: String,
        maxAllowedDevices: Int,
        storageQuotaBytes: Int64
    ) {
        guard var state = accounts[accountId] else { return }
        state.session = SyncAuthSession(
            accountId: state.session.accountId,
            email: state.session.email,
            authToken: state.session.authToken,
            maxAllowedDevices: maxAllowedDevices,
            storageQuotaBytes: storageQuotaBytes,
            authenticatedAt: state.session.authenticatedAt
        )
        accounts[accountId] = state
    }

    // MARK: 1. Authentication & Account Deletion

    public func authenticate(
        email: String,
        credentialProof: String = "passkey-or-password-proof",
        maxAllowedDevices: Int = ArcaSyncArchitecturePolicy.freeAccountMaxActiveDevices,
        storageQuotaBytes: Int64 = 250 * 1024 * 1024
    ) async throws -> SyncAuthSession {
        try ensureOnline()
        let cleanedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let accountId = "acct-\(cleanedEmail.isEmpty ? "user" : cleanedEmail)"
        defaultAccountId = accountId

        if var existing = accounts[accountId] {
            existing.session = SyncAuthSession(
                accountId: accountId,
                email: cleanedEmail,
                authToken: existing.session.authToken,
                maxAllowedDevices: maxAllowedDevices,
                storageQuotaBytes: storageQuotaBytes,
                authenticatedAt: Date()
            )
            accounts[accountId] = existing
            return existing.session
        }

        let session = SyncAuthSession(
            accountId: accountId,
            email: cleanedEmail,
            authToken: UUID().uuidString,
            maxAllowedDevices: maxAllowedDevices,
            storageQuotaBytes: storageQuotaBytes
        )
        accounts[accountId] = AccountState(
            session: session,
            devices: [],
            wrappedMasterKeysByRecipient: [:],
            wrappedSpaceKeys: [:],
            operationsBySpace: [:],
            operationSequenceByOperationId: [:],
            nextSequenceBySpace: [:],
            attachmentsBySpace: [:]
        )
        return session
    }

    public func deleteAccountAndRemoteData(accountId: String) async throws -> RemoteDeletionReceipt {
        try ensureOnline()
        guard let state = accounts.removeValue(forKey: accountId) else {
            return RemoteDeletionReceipt(
                accountId: accountId,
                deletedSpaceId: nil,
                didDeleteEntireAccount: true,
                purgedOperationsCount: 0,
                purgedAttachmentsCount: 0,
                purgedBytesCount: 0,
                verifiedZeroRemainingRecords: true
            )
        }

        let opCount = state.operationsBySpace.values.reduce(0) { $0 + $1.count }
        let attCount = state.attachmentsBySpace.values.reduce(0) { $0 + $1.count }
        let totalBytes = Self.computeTotalBytes(for: state)

        return RemoteDeletionReceipt(
            accountId: accountId,
            deletedSpaceId: nil,
            didDeleteEntireAccount: true,
            purgedOperationsCount: opCount,
            purgedAttachmentsCount: attCount,
            purgedBytesCount: totalBytes,
            verifiedZeroRemainingRecords: accounts[accountId] == nil
        )
    }

    // MARK: 2. Device Enrollment & Revocation

    public func enrollDevice(
        accountId: String,
        device: EnrolledDevice,
        maxAllowedDevices: Int = ArcaSyncArchitecturePolicy.freeAccountMaxActiveDevices,
        wrappedMasterKey: DeviceWrappedMasterKey? = nil
    ) async throws -> DeviceEnrollmentReceipt {
        try ensureOnline()
        var state = ensureAccountState(accountId: accountId, defaultMaxDevices: maxAllowedDevices)
        let effectiveLimit = min(maxAllowedDevices, state.session.maxAllowedDevices)

        if let existingIdx = state.devices.firstIndex(where: { $0.deviceId == device.deviceId }) {
            if state.devices[existingIdx].isRevoked {
                throw SyncServiceError.deviceRevoked(deviceId: device.deviceId)
            }
            state.devices[existingIdx].deviceName = device.deviceName
            state.devices[existingIdx].lastSyncAt = Date()
            if let wrappedMasterKey {
                state.wrappedMasterKeysByRecipient[device.deviceId] = wrappedMasterKey
            }
            accounts[accountId] = state
            let active = state.devices.filter { !$0.isRevoked }
            return DeviceEnrollmentReceipt(
                accountId: accountId,
                enrolledDevice: state.devices[existingIdx],
                activeDevices: active,
                maxAllowedDevices: effectiveLimit,
                wrappedMasterKey: state.wrappedMasterKeysByRecipient[device.deviceId]
            )
        }

        let activeDevices = state.devices.filter { !$0.isRevoked }
        guard activeDevices.count < effectiveLimit else {
            throw SyncServiceError.deviceLimitReached(currentDevices: activeDevices, limit: effectiveLimit)
        }

        var enrolled = device
        enrolled.isRevoked = false
        enrolled.revokedAt = nil
        state.devices.append(enrolled)
        if let wrappedMasterKey {
            state.wrappedMasterKeysByRecipient[device.deviceId] = wrappedMasterKey
        }
        accounts[accountId] = state

        let updatedActive = state.devices.filter { !$0.isRevoked }
        return DeviceEnrollmentReceipt(
            accountId: accountId,
            enrolledDevice: enrolled,
            activeDevices: updatedActive,
            maxAllowedDevices: effectiveLimit,
            wrappedMasterKey: wrappedMasterKey
        )
    }

    public func listEnrolledDevices(accountId: String) async throws -> [EnrolledDevice] {
        try ensureOnline()
        guard let state = accounts[accountId] else { return [] }
        return state.devices
    }

    public func revokeDevice(
        accountId: String,
        revokingDeviceId: String,
        requestedByDeviceId: String,
        rotatedSpaceKeys: [WrappedSpaceKeyRing] = []
    ) async throws -> DeviceRevocationReceipt {
        try ensureOnline()
        guard var state = accounts[accountId] else {
            throw SyncServiceError.accountNotFound(accountId)
        }
        try verifyActiveEnrolledDevice(deviceId: requestedByDeviceId, in: state)

        guard let idx = state.devices.firstIndex(where: { $0.deviceId == revokingDeviceId }) else {
            throw SyncServiceError.deviceNotEnrolled(deviceId: revokingDeviceId)
        }

        let now = Date()
        state.devices[idx].isRevoked = true
        state.devices[idx].revokedAt = now
        state.wrappedMasterKeysByRecipient.removeValue(forKey: revokingDeviceId)

        for keyRing in rotatedSpaceKeys {
            var history = state.wrappedSpaceKeys[keyRing.spaceId] ?? []
            history.append(keyRing)
            state.wrappedSpaceKeys[keyRing.spaceId] = history
        }

        accounts[accountId] = state
        let remainingActive = state.devices.filter { !$0.isRevoked }

        return DeviceRevocationReceipt(
            accountId: accountId,
            revokedDevice: state.devices[idx],
            remainingActiveDevices: remainingActive,
            rotatedSpaceKeys: rotatedSpaceKeys,
            securityDisclosure: ArcaSyncArchitecturePolicy.deviceRevocationDisclosure,
            revokedAt: now
        )
    }

    // MARK: 3. Space Key Ring Distribution

    public func publishWrappedSpaceKey(
        accountId: String,
        deviceId: String,
        wrappedSpaceKey: WrappedSpaceKeyRing
    ) async throws {
        try ensureOnline()
        var state = ensureAccountState(accountId: accountId)
        try verifyActiveEnrolledDevice(deviceId: deviceId, in: state)
        var rings = state.wrappedSpaceKeys[wrappedSpaceKey.spaceId] ?? []
        if !rings.contains(where: { $0.keyId == wrappedSpaceKey.keyId && $0.keyGeneration == wrappedSpaceKey.keyGeneration }) {
            rings.append(wrappedSpaceKey)
            rings.sort { $0.keyGeneration < $1.keyGeneration }
        }
        state.wrappedSpaceKeys[wrappedSpaceKey.spaceId] = rings
        accounts[accountId] = state
    }

    public func fetchLatestWrappedSpaceKey(
        accountId: String,
        spaceId: UUID,
        deviceId: String
    ) async throws -> WrappedSpaceKeyRing? {
        try ensureOnline()
        guard let state = accounts[accountId] else { return nil }
        try verifyActiveEnrolledDevice(deviceId: deviceId, in: state)
        return state.wrappedSpaceKeys[spaceId]?.last
    }

    // MARK: 4. Idempotent Push & Resumable Incremental Pull

    public func pushEncryptedOperations(
        accountId: String,
        spaceId: UUID,
        deviceId: String,
        operations: [EncryptedSyncOperation]
    ) async throws -> SyncPushReceipt {
        try ensureOnline()
        var state = ensureAccountState(accountId: accountId)
        try verifyActiveEnrolledDevice(deviceId: deviceId, in: state)

        // Check active device count against account tier limit (pauses push if downgraded from Pro to Free with >2 devices)
        let activeDevices = state.devices.filter { !$0.isRevoked }
        if activeDevices.count > state.session.maxAllowedDevices {
            throw SyncServiceError.deviceLimitReached(
                currentDevices: activeDevices,
                limit: state.session.maxAllowedDevices
            )
        }

        // Check storage quota
        let currentBytes = Self.computeTotalBytes(for: state)
        let incomingBytes = operations.reduce(Int64(0)) { $0 + Int64($1.encryptedEnvelope.approximateCiphertextByteCount) }
        if currentBytes + incomingBytes > state.session.storageQuotaBytes {
            throw SyncServiceError.storageQuotaExceeded(
                usedBytes: currentBytes + incomingBytes,
                quotaBytes: state.session.storageQuotaBytes
            )
        }

        var spaceOps = state.operationsBySpace[spaceId] ?? []
        var nextSeq = state.nextSequenceBySpace[spaceId] ?? 0
        var acceptedIds: [UUID] = []
        var deduplicatedIds: [UUID] = []

        for var op in operations {
            guard op.spaceId == spaceId else {
                throw SyncServiceError.invalidOperationEnvelope("Operation spaceId mismatch.")
            }
            // Idempotency check by `operationId`
            if state.operationSequenceByOperationId[op.operationId] != nil {
                deduplicatedIds.append(op.operationId)
                continue
            }

            nextSeq += 1
            op.serverSequenceNumber = nextSeq
            spaceOps.append(op)
            state.operationSequenceByOperationId[op.operationId] = nextSeq
            acceptedIds.append(op.operationId)
        }

        state.operationsBySpace[spaceId] = spaceOps
        state.nextSequenceBySpace[spaceId] = nextSeq
        if let devIdx = state.devices.firstIndex(where: { $0.deviceId == deviceId }) {
            state.devices[devIdx].lastSyncAt = Date()
        }
        accounts[accountId] = state

        let totalBytesAfter = Self.computeTotalBytes(for: state)
        return SyncPushReceipt(
            spaceId: spaceId,
            acceptedOperationIds: acceptedIds,
            deduplicatedOperationIds: deduplicatedIds,
            latestCursor: SyncCursor(sequenceNumber: nextSeq),
            totalAccountBytesUsed: totalBytesAfter
        )
    }

    public func pullEncryptedOperations(
        accountId: String,
        spaceId: UUID,
        deviceId: String,
        sinceCursor: SyncCursor? = nil,
        limit: Int = 200
    ) async throws -> SyncPullBatch {
        try ensureOnline()
        guard var state = accounts[accountId] else {
            return SyncPullBatch(
                spaceId: spaceId,
                operations: [],
                nextCursor: sinceCursor ?? .initial,
                hasMore: false
            )
        }
        try verifyActiveEnrolledDevice(deviceId: deviceId, in: state)

        let minSequence = sinceCursor?.sequenceNumber ?? 0
        let allOps = state.operationsBySpace[spaceId] ?? []
        let filtered = allOps.filter { ($0.serverSequenceNumber ?? 0) > minSequence }
        let pageLimit = max(1, limit)
        let slice = Array(filtered.prefix(pageLimit))
        let hasMore = filtered.count > slice.count
        let maxSeqInSlice = slice.compactMap(\.serverSequenceNumber).max() ?? minSequence

        if let devIdx = state.devices.firstIndex(where: { $0.deviceId == deviceId }) {
            state.devices[devIdx].lastSyncAt = Date()
            accounts[accountId] = state
        }

        return SyncPullBatch(
            spaceId: spaceId,
            operations: slice,
            nextCursor: SyncCursor(sequenceNumber: maxSeqInSlice),
            hasMore: hasMore,
            latestWrappedSpaceKey: state.wrappedSpaceKeys[spaceId]?.last
        )
    }

    // MARK: 5. Encrypted Attachments

    public func uploadEncryptedAttachment(
        accountId: String,
        deviceId: String,
        blob: EncryptedAttachmentBlob
    ) async throws {
        try ensureOnline()
        var state = ensureAccountState(accountId: accountId)
        try verifyActiveEnrolledDevice(deviceId: deviceId, in: state)

        // Verify ciphertext SHA-256 integrity on upload receipt
        let ciphertextBytes = Data((blob.encryptedDataEnvelope.ciphertextBase64 + ":" + blob.encryptedDataEnvelope.tagBase64).utf8)
        let computedHash = ClientCryptoEngine.sha256Hex(of: ciphertextBytes)
        guard computedHash.lowercased() == blob.ciphertextSHA256Hex.lowercased() else {
            throw SyncServiceError.attachmentIntegrityMismatch(
                expectedSHA256: blob.ciphertextSHA256Hex,
                actualSHA256: computedHash
            )
        }

        let currentBytes = Self.computeTotalBytes(for: state)
        if currentBytes + blob.approximateCiphertextBytes > state.session.storageQuotaBytes {
            throw SyncServiceError.storageQuotaExceeded(
                usedBytes: currentBytes + blob.approximateCiphertextBytes,
                quotaBytes: state.session.storageQuotaBytes
            )
        }

        var spaceAttachments = state.attachmentsBySpace[blob.spaceId] ?? [:]
        spaceAttachments[blob.attachmentId] = blob
        state.attachmentsBySpace[blob.spaceId] = spaceAttachments
        accounts[accountId] = state
    }

    public func downloadEncryptedAttachment(
        accountId: String,
        spaceId: UUID,
        attachmentId: UUID,
        deviceId: String
    ) async throws -> EncryptedAttachmentBlob {
        try ensureOnline()
        guard let state = accounts[accountId] else {
            throw SyncServiceError.attachmentNotFound(attachmentId: attachmentId)
        }
        try verifyActiveEnrolledDevice(deviceId: deviceId, in: state)
        guard let blob = state.attachmentsBySpace[spaceId]?[attachmentId] else {
            throw SyncServiceError.attachmentNotFound(attachmentId: attachmentId)
        }
        return blob
    }

    // MARK: 6. Remote Space Deletion Verification

    public func deleteRemoteSpaceData(
        accountId: String,
        spaceId: UUID,
        requestedByDeviceId: String
    ) async throws -> RemoteDeletionReceipt {
        try ensureOnline()
        guard var state = accounts[accountId] else {
            return RemoteDeletionReceipt(
                accountId: accountId,
                deletedSpaceId: spaceId,
                didDeleteEntireAccount: false,
                purgedOperationsCount: 0,
                purgedAttachmentsCount: 0,
                purgedBytesCount: 0,
                verifiedZeroRemainingRecords: true
            )
        }
        try verifyActiveEnrolledDevice(deviceId: requestedByDeviceId, in: state)

        let removedOps = state.operationsBySpace.removeValue(forKey: spaceId) ?? []
        for op in removedOps {
            state.operationSequenceByOperationId.removeValue(forKey: op.operationId)
        }
        state.nextSequenceBySpace.removeValue(forKey: spaceId)
        state.wrappedSpaceKeys.removeValue(forKey: spaceId)
        let removedAttachments = state.attachmentsBySpace.removeValue(forKey: spaceId) ?? [:]

        let purgedOpBytes = removedOps.reduce(Int64(0)) { $0 + Int64($1.encryptedEnvelope.approximateCiphertextByteCount) }
        let purgedAttBytes = removedAttachments.values.reduce(Int64(0)) { $0 + $1.approximateCiphertextBytes }

        accounts[accountId] = state
        let remainingOpsForSpace = state.operationsBySpace[spaceId]?.count ?? 0

        return RemoteDeletionReceipt(
            accountId: accountId,
            deletedSpaceId: spaceId,
            didDeleteEntireAccount: false,
            purgedOperationsCount: removedOps.count,
            purgedAttachmentsCount: removedAttachments.count,
            purgedBytesCount: purgedOpBytes + purgedAttBytes,
            verifiedZeroRemainingRecords: remainingOpsForSpace == 0
        )
    }

    /// Convenience overload when deleting remote space data using the active default account.
    public func deleteRemoteSpaceData(spaceId: UUID) async throws -> RemoteDeletionReceipt {
        try ensureOnline()
        guard let state = accounts[defaultAccountId],
              let activeDevice = state.devices.first(where: { !$0.isRevoked }) else {
            return RemoteDeletionReceipt(
                accountId: defaultAccountId,
                deletedSpaceId: spaceId,
                didDeleteEntireAccount: false,
                purgedOperationsCount: 0,
                purgedAttachmentsCount: 0,
                purgedBytesCount: 0,
                verifiedZeroRemainingRecords: true
            )
        }
        return try await deleteRemoteSpaceData(
            accountId: defaultAccountId,
            spaceId: spaceId,
            requestedByDeviceId: activeDevice.deviceId
        )
    }

    /// Inspects raw stored operation envelopes for a Space (used by E2EE tests to verify server never sees plaintext).
    public func inspectStoredEncryptedOperations(accountId: String, spaceId: UUID) -> [EncryptedSyncOperation] {
        accounts[accountId]?.operationsBySpace[spaceId] ?? []
    }

    // MARK: Private Helpers

    private func ensureOnline() throws {
        if isSimulatedOffline {
            throw SyncServiceError.offlineUnavailable
        }
    }

    private func ensureAccountState(
        accountId: String,
        defaultMaxDevices: Int = ArcaSyncArchitecturePolicy.freeAccountMaxActiveDevices
    ) -> AccountState {
        if let existing = accounts[accountId] {
            return existing
        }
        let session = SyncAuthSession(
            accountId: accountId,
            email: "\(accountId)@arca.local",
            maxAllowedDevices: defaultMaxDevices
        )
        let created = AccountState(
            session: session,
            devices: [],
            wrappedMasterKeysByRecipient: [:],
            wrappedSpaceKeys: [:],
            operationsBySpace: [:],
            operationSequenceByOperationId: [:],
            nextSequenceBySpace: [:],
            attachmentsBySpace: [:]
        )
        accounts[accountId] = created
        return created
    }

    private func verifyActiveEnrolledDevice(deviceId: String, in state: AccountState) throws {
        guard let device = state.devices.first(where: { $0.deviceId == deviceId }) else {
            throw SyncServiceError.deviceNotEnrolled(deviceId: deviceId)
        }
        if device.isRevoked {
            throw SyncServiceError.deviceRevoked(deviceId: deviceId)
        }
    }

    private static func computeTotalBytes(for state: AccountState) -> Int64 {
        var total: Int64 = 0
        for ops in state.operationsBySpace.values {
            for op in ops {
                total += Int64(op.encryptedEnvelope.approximateCiphertextByteCount)
            }
        }
        for spaceAtts in state.attachmentsBySpace.values {
            for blob in spaceAtts.values {
                total += blob.approximateCiphertextBytes
            }
        }
        return total
    }
}

// MARK: - Durable Outbox Queue Item

/// Represents a pending local mutation queued for idempotent encrypted push.
public struct PendingSyncOutboxItem: Identifiable, Codable, Sendable, Equatable, Hashable {
    public var id: UUID { operation.operationId }
    public let operation: EncryptedSyncOperation
    public let baseRecordSnapshot: RecordItem?
    public var attemptCount: Int
    public var nextEligibleAttemptAt: Date
    public var lastErrorDescription: String?

    public init(
        operation: EncryptedSyncOperation,
        baseRecordSnapshot: RecordItem? = nil,
        attemptCount: Int = 0,
        nextEligibleAttemptAt: Date = Date(timeIntervalSince1970: 0),
        lastErrorDescription: String? = nil
    ) {
        self.operation = operation
        self.baseRecordSnapshot = baseRecordSnapshot
        self.attemptCount = attemptCount
        self.nextEligibleAttemptAt = nextEligibleAttemptAt
        self.lastErrorDescription = lastErrorDescription
    }
}

/// Summary of a completed `SyncCoordinator.synchronizeSpace` cycle.
public struct SpaceSyncCycleReport: Sendable, Equatable {
    public let spaceId: UUID
    public let pushedOperationsCount: Int
    public let deduplicatedOperationsCount: Int
    public let pulledOperationsCount: Int
    public let cleanlyMergedRecordsCount: Int
    public let newlyDetectedConflicts: [SyncConflict]
    public let updatedCursor: SyncCursor

    public init(
        spaceId: UUID,
        pushedOperationsCount: Int,
        deduplicatedOperationsCount: Int,
        pulledOperationsCount: Int,
        cleanlyMergedRecordsCount: Int,
        newlyDetectedConflicts: [SyncConflict],
        updatedCursor: SyncCursor
    ) {
        self.spaceId = spaceId
        self.pushedOperationsCount = pushedOperationsCount
        self.deduplicatedOperationsCount = deduplicatedOperationsCount
        self.pulledOperationsCount = pulledOperationsCount
        self.cleanlyMergedRecordsCount = cleanlyMergedRecordsCount
        self.newlyDetectedConflicts = newlyDetectedConflicts
        self.updatedCursor = updatedCursor
    }
}

// MARK: - SyncCoordinator Actor

/// Coordinates client-side encryption (`ClientCryptoEngine`), per-Space outbox queues,
/// resumable pull cursors, field-level conflict reconciliation, and device enrollment/revocation
/// against `ArcaSyncBackendProtocol`.
///
/// Guarantees:
/// - Never uploads or overwrites raw SQLite database files.
/// - Local-only Spaces (`storageMode == .localOnly`) are strictly rejected from sync operations.
/// - Preserves both local and remote record versions whenever concurrent edits touch the same field.
public actor SyncCoordinator {
    public let accountId: String
    public let deviceIdentity: DeviceIdentity
    public let backend: any ArcaSyncBackendProtocol
    public let backoffPolicy: RetryBackoffPolicy

    private var masterAccountKey: SymmetricKey
    private var makKeyId: UUID
    private var spaceKeyRingsBySpace: [UUID: [Int: SpaceKeyRing]] = [:]
    private var latestKeyGenBySpace: [UUID: Int] = [:]
    private var outboxBySpace: [UUID: [PendingSyncOutboxItem]] = [:]
    private var cursorsBySpace: [UUID: SyncCursor] = [:]
    private var schemasBySpace: [UUID: [UUID: CollectionSchema]] = [:]
    private var recordsBySpace: [UUID: [UUID: RecordItem]] = [:]
    private var conflictsBySpace: [UUID: [SyncConflict]] = [:]

    public init(
        accountId: String,
        deviceIdentity: DeviceIdentity,
        masterAccountKey: SymmetricKey = ClientCryptoEngine.generateSymmetricKey(),
        makKeyId: UUID = UUID(),
        backend: any ArcaSyncBackendProtocol,
        backoffPolicy: RetryBackoffPolicy = .standard
    ) {
        self.accountId = accountId
        self.deviceIdentity = deviceIdentity
        self.masterAccountKey = masterAccountKey
        self.makKeyId = makKeyId
        self.backend = backend
        self.backoffPolicy = backoffPolicy
    }

    // MARK: - Key Ring Management

    /// Registers or updates a `SpaceKeyRing` for a Space.
    public func registerSpaceKeyRing(_ keyRing: SpaceKeyRing) {
        var gens = spaceKeyRingsBySpace[keyRing.spaceId] ?? [:]
        gens[keyRing.keyGeneration] = keyRing
        spaceKeyRingsBySpace[keyRing.spaceId] = gens
        let currentMax = latestKeyGenBySpace[keyRing.spaceId] ?? 0
        if keyRing.keyGeneration >= currentMax {
            latestKeyGenBySpace[keyRing.spaceId] = keyRing.keyGeneration
        }
    }

    /// Returns the active `SpaceKeyRing` for `spaceId`, generating generation 1 if none exists yet.
    public func activeSpaceKeyRing(for spaceId: UUID) -> SpaceKeyRing {
        if let gen = latestKeyGenBySpace[spaceId],
           let ring = spaceKeyRingsBySpace[spaceId]?[gen] {
            return ring
        }
        let initial = SpaceKeyRing(spaceId: spaceId, keyGeneration: 1)
        registerSpaceKeyRing(initial)
        return initial
    }

    // MARK: - Device Enrollment & Revocation

    /// Enrolls this coordinator's `deviceIdentity` with the backend, respecting the account's active device limit.
    public func enrollCurrentDevice(
        maxAllowedDevices: Int = ArcaSyncArchitecturePolicy.freeAccountMaxActiveDevices,
        platform: String = "iOS"
    ) async throws -> DeviceEnrollmentReceipt {
        let device = EnrolledDevice(descriptor: deviceIdentity.descriptor, platform: platform)
        return try await backend.enrollDevice(
            accountId: accountId,
            device: device,
            maxAllowedDevices: maxAllowedDevices,
            wrappedMasterKey: nil
        )
    }

    /// Revokes a target device, rotates the `SpaceKeyRing` for all active synced Spaces, and uploads the rotated wrapped keys.
    public func revokeDeviceAndRotateKeys(revokingDeviceId: String) async throws -> DeviceRevocationReceipt {
        var rotatedWrappedKeys: [WrappedSpaceKeyRing] = []
        for (spaceId, _) in latestKeyGenBySpace {
            let currentRing = activeSpaceKeyRing(for: spaceId)
            let rotationResult = try DeviceIdentity.rotateSpaceKey(
                currentKeyRing: currentRing,
                revokingDeviceId: revokingDeviceId,
                masterAccountKey: masterAccountKey,
                makKeyId: makKeyId
            )
            registerSpaceKeyRing(rotationResult.rotatedSpaceKeyRing)
            rotatedWrappedKeys.append(rotationResult.wrappedSpaceKeyRing)
        }

        return try await backend.revokeDevice(
            accountId: accountId,
            revokingDeviceId: revokingDeviceId,
            requestedByDeviceId: deviceIdentity.deviceId,
            rotatedSpaceKeys: rotatedWrappedKeys
        )
    }

    // MARK: - Local Mutation Queuing (Client-Side Encrypted Outbox)

    /// Encrypts and queues a `CollectionSchema` creation/update into the Space's durable outbox.
    @discardableResult
    public func queueSchemaUpsert(
        _ schema: CollectionSchema,
        spaceMode: SpaceStorageMode = .arcaSync,
        operationId: UUID = UUID()
    ) throws -> EncryptedSyncOperation {
        guard spaceMode == .arcaSync else {
            throw SyncServiceError.spaceIsNotConfiguredForSync(spaceId: schema.spaceId)
        }
        let existing = schemasBySpace[schema.spaceId]?[schema.id]
        let baseRev = existing?.revision ?? max(0, schema.revision - 1)
        let keyRing = activeSpaceKeyRing(for: schema.spaceId)

        let op = try EncryptedSyncOperation.encryptSchemaOperation(
            operationId: operationId,
            schema: schema,
            baseRevision: baseRev,
            authorDeviceId: deviceIdentity.deviceId,
            spaceKeyRing: keyRing
        )

        var spaceSchemas = schemasBySpace[schema.spaceId] ?? [:]
        spaceSchemas[schema.id] = schema
        schemasBySpace[schema.spaceId] = spaceSchemas

        appendToOutbox(PendingSyncOutboxItem(operation: op), for: schema.spaceId)
        return op
    }

    /// Encrypts and queues a `RecordItem` creation/update into the Space's durable outbox.
    @discardableResult
    public func queueRecordUpsert(
        _ record: RecordItem,
        baseRecordSnapshot: RecordItem? = nil,
        spaceMode: SpaceStorageMode = .arcaSync,
        operationId: UUID = UUID()
    ) throws -> EncryptedSyncOperation {
        guard spaceMode == .arcaSync else {
            throw SyncServiceError.spaceIsNotConfiguredForSync(spaceId: record.spaceId)
        }
        let priorSnapshot = baseRecordSnapshot ?? recordsBySpace[record.spaceId]?[record.id]
        let baseRev = priorSnapshot?.revision ?? max(0, record.revision - 1)
        let keyRing = activeSpaceKeyRing(for: record.spaceId)

        var updatedRecord = record
        updatedRecord.lastModifiedByDeviceId = deviceIdentity.deviceId

        let op = try EncryptedSyncOperation.encryptRecordOperation(
            operationId: operationId,
            record: updatedRecord,
            baseRevision: baseRev,
            authorDeviceId: deviceIdentity.deviceId,
            spaceKeyRing: keyRing
        )

        var spaceRecords = recordsBySpace[record.spaceId] ?? [:]
        spaceRecords[record.id] = updatedRecord
        recordsBySpace[record.spaceId] = spaceRecords

        appendToOutbox(
            PendingSyncOutboxItem(operation: op, baseRecordSnapshot: priorSnapshot),
            for: record.spaceId
        )
        return op
    }

    /// Encrypts and queues a deletion tombstone (`isDeleted = true`) for a `RecordItem`.
    @discardableResult
    public func queueRecordTombstone(
        record: RecordItem,
        spaceMode: SpaceStorageMode = .arcaSync,
        operationId: UUID = UUID()
    ) throws -> EncryptedSyncOperation {
        var tombstone = record
        let baseRev = record.revision
        tombstone.isDeleted = true
        tombstone.revision = baseRev + 1
        tombstone.updatedAt = Date()
        tombstone.lastModifiedByDeviceId = deviceIdentity.deviceId
        return try queueRecordUpsert(
            tombstone,
            baseRecordSnapshot: record,
            spaceMode: spaceMode,
            operationId: operationId
        )
    }

    // MARK: - Push & Pull Synchronization Cycle

    /// Executes a pull-reconcile-push synchronization cycle for `spaceId`.
    public func synchronizeSpace(
        spaceId: UUID,
        spaceMode: SpaceStorageMode = .arcaSync,
        referenceDate: Date = Date()
    ) async throws -> SpaceSyncCycleReport {
        guard spaceMode == .arcaSync else {
            throw SyncServiceError.spaceIsNotConfiguredForSync(spaceId: spaceId)
        }

        // 1. Pull remote operations since our last cursor first so we can detect concurrent edits cleanly
        let currentCursor = cursorsBySpace[spaceId]
        let pullBatch = try await backend.pullEncryptedOperations(
            accountId: accountId,
            spaceId: spaceId,
            deviceId: deviceIdentity.deviceId,
            sinceCursor: currentCursor,
            limit: 500
        )

        var cleanlyMergedCount = 0
        var newConflicts: [SyncConflict] = []

        for remoteOp in pullBatch.operations {
            // Skip operations authored by this device that we already applied locally
            if remoteOp.authorDeviceId == deviceIdentity.deviceId {
                continue
            }

            let keyRing = try resolveKeyRing(for: spaceId, keyGeneration: remoteOp.keyGeneration, keyId: remoteOp.encryptedEnvelope.keyId)

            switch remoteOp.entityType {
            case .collectionSchema:
                let remoteSchema = try remoteOp.decryptSchema(using: keyRing)
                var spaceSchemas = schemasBySpace[spaceId] ?? [:]
                if let localSchema = spaceSchemas[remoteSchema.id] {
                    if remoteSchema.revision >= localSchema.revision {
                        spaceSchemas[remoteSchema.id] = remoteSchema
                    }
                } else {
                    spaceSchemas[remoteSchema.id] = remoteSchema
                }
                schemasBySpace[spaceId] = spaceSchemas

            case .record:
                let remoteRecord = try remoteOp.decryptRecord(using: keyRing)
                var spaceRecords = recordsBySpace[spaceId] ?? [:]
                let localRecord = spaceRecords[remoteRecord.id]

                let pendingLocalItem = (outboxBySpace[spaceId] ?? []).first {
                    $0.operation.entityType == .record && $0.operation.entityId == remoteRecord.id
                }
                let hasUncommittedLocal = pendingLocalItem != nil

                let outcome = SyncConflictEngine.reconcileRecord(
                    localRecord: localRecord,
                    remoteRecord: remoteRecord,
                    baseRecordSnapshot: pendingLocalItem?.baseRecordSnapshot,
                    localBaseRevision: pendingLocalItem?.operation.baseRevision,
                    hasUncommittedLocalEdits: hasUncommittedLocal
                )

                switch outcome {
                case .cleanNoChange(let kept):
                    spaceRecords[remoteRecord.id] = kept

                case .cleanRemoteApplied(let applied):
                    spaceRecords[remoteRecord.id] = applied

                case .cleanFieldLevelMerge(let mergedRecord):
                    spaceRecords[remoteRecord.id] = mergedRecord
                    cleanlyMergedCount += 1
                    // Replace the pending outbox operation with the cleanly merged record so the server receives the combined result
                    replacePendingRecordOutboxOperation(with: mergedRecord, baseRevision: remoteRecord.revision, in: spaceId)

                case .conflictPreserved(let conflict):
                    var spaceConflicts = conflictsBySpace[spaceId] ?? []
                    spaceConflicts.removeAll { $0.recordId == conflict.recordId }
                    spaceConflicts.append(conflict)
                    conflictsBySpace[spaceId] = spaceConflicts
                    newConflicts.append(conflict)
                    // Hold push of the conflicting record until the user explicitly chooses a resolution
                    removePendingRecordFromOutbox(recordId: conflict.recordId, in: spaceId)
                }
                recordsBySpace[spaceId] = spaceRecords

            case .attachment, .spaceMetadata:
                break
            }
        }

        cursorsBySpace[spaceId] = pullBatch.nextCursor

        // 2. Push eligible outbox operations
        let currentOutbox = outboxBySpace[spaceId] ?? []
        let eligibleItems = currentOutbox.filter {
            $0.nextEligibleAttemptAt <= referenceDate && backoffPolicy.shouldRetry(attempt: $0.attemptCount + 1)
        }

        var pushedCount = 0
        var deduplicatedCount = 0
        var finalCursor = pullBatch.nextCursor

        if !eligibleItems.isEmpty {
            let opsToPush = eligibleItems.map(\.operation)
            do {
                let pushReceipt = try await backend.pushEncryptedOperations(
                    accountId: accountId,
                    spaceId: spaceId,
                    deviceId: deviceIdentity.deviceId,
                    operations: opsToPush
                )
                pushedCount = pushReceipt.acceptedOperationIds.count
                deduplicatedCount = pushReceipt.deduplicatedOperationIds.count
                let completedSet = Set(pushReceipt.acceptedOperationIds).union(pushReceipt.deduplicatedOperationIds)
                var remaining = outboxBySpace[spaceId] ?? []
                remaining.removeAll { completedSet.contains($0.operation.operationId) }
                outboxBySpace[spaceId] = remaining

                // Pull again to advance cursor past our own newly pushed operations
                let postPushPull = try await backend.pullEncryptedOperations(
                    accountId: accountId,
                    spaceId: spaceId,
                    deviceId: deviceIdentity.deviceId,
                    sinceCursor: cursorsBySpace[spaceId],
                    limit: 500
                )
                finalCursor = postPushPull.nextCursor
                cursorsBySpace[spaceId] = finalCursor
            } catch {
                // Record attempt & schedule exponential backoff without losing any outbox items
                var updatedOutbox = outboxBySpace[spaceId] ?? []
                for idx in updatedOutbox.indices {
                    if eligibleItems.contains(where: { $0.id == updatedOutbox[idx].id }) {
                        updatedOutbox[idx].attemptCount += 1
                        updatedOutbox[idx].nextEligibleAttemptAt = backoffPolicy.nextRetryDate(
                            forAttempt: updatedOutbox[idx].attemptCount,
                            from: referenceDate
                        )
                        updatedOutbox[idx].lastErrorDescription = error.localizedDescription
                    }
                }
                outboxBySpace[spaceId] = updatedOutbox
                throw error
            }
        }

        return SpaceSyncCycleReport(
            spaceId: spaceId,
            pushedOperationsCount: pushedCount,
            deduplicatedOperationsCount: deduplicatedCount,
            pulledOperationsCount: pullBatch.operations.count,
            cleanlyMergedRecordsCount: cleanlyMergedCount,
            newlyDetectedConflicts: newConflicts,
            updatedCursor: finalCursor
        )
    }

    /// Synchronizes a SQLite-backed `SpaceStore` by pulling remote encrypted operations,
    /// reconciling concurrent edits against `SpaceStore.pendingOutboxItems()`, and pushing encrypted outbox items.
    public func synchronizeSpaceStore(
        _ spaceStore: SpaceStore,
        spaceMode: SpaceStorageMode = .arcaSync,
        referenceDate: Date = Date()
    ) async throws -> SpaceSyncCycleReport {
        let spaceId = spaceStore.spaceId
        guard spaceMode == .arcaSync else {
            throw SyncServiceError.spaceIsNotConfiguredForSync(spaceId: spaceId)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // 1. Pull remote operations since last cursor
        let currentCursor = cursorsBySpace[spaceId]
        let pullBatch = try await backend.pullEncryptedOperations(
            accountId: accountId,
            spaceId: spaceId,
            deviceId: deviceIdentity.deviceId,
            sinceCursor: currentCursor,
            limit: 500
        )

        let initialOutbox = await spaceStore.pendingOutboxItems()
        var cleanlyMergedCount = 0
        var newConflicts: [SyncConflict] = []

        for remoteOp in pullBatch.operations {
            if remoteOp.authorDeviceId == deviceIdentity.deviceId {
                continue
            }

            let keyRing = try resolveKeyRing(
                for: spaceId,
                keyGeneration: remoteOp.keyGeneration,
                keyId: remoteOp.encryptedEnvelope.keyId
            )

            switch remoteOp.entityType {
            case .collectionSchema:
                let remoteSchema = try remoteOp.decryptSchema(using: keyRing)
                let localSchema = await spaceStore.fetchCollection(id: remoteSchema.id)
                if localSchema == nil || remoteSchema.revision >= (localSchema?.revision ?? 0) {
                    await spaceStore.saveCollection(remoteSchema, enqueueSync: false)
                }

            case .record:
                let remoteRecord = try remoteOp.decryptRecord(using: keyRing)
                let localRecord = await spaceStore.fetchRecord(id: remoteRecord.id)
                let matchingOutbox = initialOutbox.filter {
                    ($0.parsedEntityType == .recordUpsert || $0.parsedEntityType == .recordTombstone) &&
                    $0.entityId == remoteRecord.id
                }
                let hasUncommittedLocal = !matchingOutbox.isEmpty
                let earliestBaseRev = matchingOutbox.first?.baseRevision

                let outcome = SyncConflictEngine.reconcileRecord(
                    localRecord: localRecord,
                    remoteRecord: remoteRecord,
                    baseRecordSnapshot: nil,
                    localBaseRevision: earliestBaseRev,
                    hasUncommittedLocalEdits: hasUncommittedLocal
                )

                switch outcome {
                case .cleanNoChange:
                    break

                case .cleanRemoteApplied(let applied):
                    if let schema = await spaceStore.fetchCollection(id: applied.collectionId) {
                        try? await spaceStore.saveRecord(applied, schema: schema, enqueueSync: false)
                    }

                case .cleanFieldLevelMerge(let mergedRecord):
                    cleanlyMergedCount += 1
                    for item in matchingOutbox {
                        await spaceStore.removeOutboxItem(operationId: item.operationId)
                    }
                    if let schema = await spaceStore.fetchCollection(id: mergedRecord.collectionId) {
                        try? await spaceStore.saveRecord(mergedRecord, schema: schema, enqueueSync: true)
                    }

                case .conflictPreserved(let conflict):
                    var spaceConflicts = conflictsBySpace[spaceId] ?? []
                    spaceConflicts.removeAll { $0.recordId == conflict.recordId }
                    spaceConflicts.append(conflict)
                    conflictsBySpace[spaceId] = spaceConflicts
                    newConflicts.append(conflict)
                    for item in matchingOutbox {
                        await spaceStore.removeOutboxItem(operationId: item.operationId)
                    }
                }

            case .attachment, .spaceMetadata:
                break
            }
        }

        cursorsBySpace[spaceId] = pullBatch.nextCursor

        // 2. Encrypt and push remaining `SpaceStore` outbox items
        let remainingOutbox = await spaceStore.pendingOutboxItems()
        let keyRing = activeSpaceKeyRing(for: spaceId)
        var encryptedOps: [EncryptedSyncOperation] = []

        for item in remainingOutbox where backoffPolicy.shouldRetry(attempt: item.retryCount + 1) {
            guard let payloadData = item.payloadJSON.data(using: .utf8) else { continue }
            switch item.parsedEntityType {
            case .collectionUpsert, .collectionTombstone:
                if let schema = try? decoder.decode(CollectionSchema.self, from: payloadData) {
                    let op = try EncryptedSyncOperation.encryptSchemaOperation(
                        operationId: item.operationId,
                        schema: schema,
                        baseRevision: item.baseRevision,
                        authorDeviceId: deviceIdentity.deviceId,
                        spaceKeyRing: keyRing,
                        createdAt: item.createdAt
                    )
                    encryptedOps.append(op)
                }
            case .recordUpsert, .recordTombstone:
                if let record = try? decoder.decode(RecordItem.self, from: payloadData) {
                    let op = try EncryptedSyncOperation.encryptRecordOperation(
                        operationId: item.operationId,
                        record: record,
                        baseRevision: item.baseRevision,
                        authorDeviceId: deviceIdentity.deviceId,
                        spaceKeyRing: keyRing,
                        createdAt: item.createdAt
                    )
                    encryptedOps.append(op)
                }
            case .attachmentUpload, .none:
                break
            }
        }

        var pushedCount = 0
        var deduplicatedCount = 0
        var finalCursor = pullBatch.nextCursor

        if !encryptedOps.isEmpty {
            do {
                let receipt = try await backend.pushEncryptedOperations(
                    accountId: accountId,
                    spaceId: spaceId,
                    deviceId: deviceIdentity.deviceId,
                    operations: encryptedOps
                )
                pushedCount = receipt.acceptedOperationIds.count
                deduplicatedCount = receipt.deduplicatedOperationIds.count
                let completedIds = Set(receipt.acceptedOperationIds).union(receipt.deduplicatedOperationIds)
                for completedId in completedIds {
                    await spaceStore.removeOutboxItem(operationId: completedId)
                }

                let postPushPull = try await backend.pullEncryptedOperations(
                    accountId: accountId,
                    spaceId: spaceId,
                    deviceId: deviceIdentity.deviceId,
                    sinceCursor: cursorsBySpace[spaceId],
                    limit: 500
                )
                finalCursor = postPushPull.nextCursor
                cursorsBySpace[spaceId] = finalCursor
            } catch {
                for op in encryptedOps {
                    await spaceStore.markOutboxFailure(operationId: op.operationId, error: error.localizedDescription)
                }
                throw error
            }
        }

        return SpaceSyncCycleReport(
            spaceId: spaceId,
            pushedOperationsCount: pushedCount,
            deduplicatedOperationsCount: deduplicatedCount,
            pulledOperationsCount: pullBatch.operations.count,
            cleanlyMergedRecordsCount: cleanlyMergedCount,
            newlyDetectedConflicts: newConflicts,
            updatedCursor: finalCursor
        )
    }

    /// Resolves a `SyncConflict` in a SQLite-backed `SpaceStore`, persisting the resolved record and queuing it for sync.
    @discardableResult
    public func resolveConflict(
        conflictId: UUID,
        in spaceStore: SpaceStore,
        choice: ConflictResolutionChoice
    ) async throws -> RecordItem {
        let spaceId = spaceStore.spaceId
        guard var spaceConflicts = conflictsBySpace[spaceId],
              let idx = spaceConflicts.firstIndex(where: { $0.id == conflictId }) else {
            throw SyncServiceError.invalidOperationEnvelope("Conflict not found.")
        }
        let conflict = spaceConflicts.remove(at: idx)
        conflictsBySpace[spaceId] = spaceConflicts

        let resolvedRecord = SyncConflictEngine.resolveConflict(
            conflict,
            choice: choice,
            resolvedByDeviceId: deviceIdentity.deviceId
        )

        if let schema = await spaceStore.fetchCollection(id: resolvedRecord.collectionId) {
            try await spaceStore.saveRecord(resolvedRecord, schema: schema, enqueueSync: true)
        }
        return resolvedRecord
    }

    // MARK: - Conflict Resolution

    /// Resolves a `SyncConflict` using the user's explicit choice, updates the local record, and queues the resolved record for sync.
    @discardableResult
    public func resolveConflict(
        conflictId: UUID,
        in spaceId: UUID,
        choice: ConflictResolutionChoice
    ) throws -> RecordItem {
        guard var spaceConflicts = conflictsBySpace[spaceId],
              let idx = spaceConflicts.firstIndex(where: { $0.id == conflictId }) else {
            throw SyncServiceError.invalidOperationEnvelope("Conflict not found.")
        }
        let conflict = spaceConflicts.remove(at: idx)
        conflictsBySpace[spaceId] = spaceConflicts

        let resolvedRecord = SyncConflictEngine.resolveConflict(
            conflict,
            choice: choice,
            resolvedByDeviceId: deviceIdentity.deviceId
        )

        var spaceRecords = recordsBySpace[spaceId] ?? [:]
        spaceRecords[resolvedRecord.id] = resolvedRecord
        recordsBySpace[spaceId] = spaceRecords

        _ = try queueRecordUpsert(
            resolvedRecord,
            baseRecordSnapshot: conflict.remoteRecord,
            spaceMode: .arcaSync
        )
        return resolvedRecord
    }

    // MARK: - Encrypted Attachment Upload & Download

    /// Encrypts an attachment and uploads it to the backend, returning the updated `.uploadedVerified` reference.
    public func uploadAttachment(
        reference: AttachmentReference,
        rawData: Data,
        spaceId: UUID,
        recordId: UUID
    ) async throws -> AttachmentReference {
        let keyRing = activeSpaceKeyRing(for: spaceId)
        let blob = try EncryptedAttachmentBlob.encryptAttachment(
            reference: reference,
            rawData: rawData,
            spaceId: spaceId,
            recordId: recordId,
            authorDeviceId: deviceIdentity.deviceId,
            spaceKeyRing: keyRing
        )
        try await backend.uploadEncryptedAttachment(
            accountId: accountId,
            deviceId: deviceIdentity.deviceId,
            blob: blob
        )
        var verified = reference
        verified.uploadState = .uploadedVerified
        return verified
    }

    /// Downloads, decrypts, and verifies the SHA-256 integrity of an encrypted attachment.
    public func downloadAndVerifyAttachment(
        spaceId: UUID,
        attachmentId: UUID
    ) async throws -> (reference: AttachmentReference, data: Data) {
        let blob = try await backend.downloadEncryptedAttachment(
            accountId: accountId,
            spaceId: spaceId,
            attachmentId: attachmentId,
            deviceId: deviceIdentity.deviceId
        )
        let keyRing = try resolveKeyRing(
            for: spaceId,
            keyGeneration: blob.keyGeneration,
            keyId: blob.encryptedDataEnvelope.keyId
        )
        return try blob.decryptAndVerify(using: keyRing)
    }

    // MARK: - Remote Space Deletion (Mode Transition Support)

    /// Deletes all remote encrypted operations and attachments for `spaceId` when a user switches a Space to Local-Only
    /// and chooses to purge remote copies, while leaving local records intact.
    public func deleteRemoteSpaceData(spaceId: UUID) async throws -> RemoteDeletionReceipt {
        outboxBySpace.removeValue(forKey: spaceId)
        cursorsBySpace.removeValue(forKey: spaceId)
        return try await backend.deleteRemoteSpaceData(
            accountId: accountId,
            spaceId: spaceId,
            requestedByDeviceId: deviceIdentity.deviceId
        )
    }

    // MARK: - State Inspection Accessors

    public func pendingOutboxItems(for spaceId: UUID) -> [PendingSyncOutboxItem] {
        outboxBySpace[spaceId] ?? []
    }

    public func activeConflicts(for spaceId: UUID) -> [SyncConflict] {
        conflictsBySpace[spaceId] ?? []
    }

    public func syncedRecords(for spaceId: UUID, includeDeleted: Bool = false) -> [RecordItem] {
        let all = Array((recordsBySpace[spaceId] ?? [:]).values)
        return includeDeleted ? all : all.filter { !$0.isDeleted }
    }

    public func syncedRecord(id: UUID, in spaceId: UUID) -> RecordItem? {
        recordsBySpace[spaceId]?[id]
    }

    public func syncedSchemas(for spaceId: UUID) -> [CollectionSchema] {
        Array((schemasBySpace[spaceId] ?? [:]).values).filter { !$0.isDeleted }
    }

    public func currentCursor(for spaceId: UUID) -> SyncCursor {
        cursorsBySpace[spaceId] ?? .initial
    }

    // MARK: - Private Helpers

    private func appendToOutbox(_ item: PendingSyncOutboxItem, for spaceId: UUID) {
        var queue = outboxBySpace[spaceId] ?? []
        if let existingIdx = queue.firstIndex(where: { $0.operation.operationId == item.operation.operationId }) {
            queue[existingIdx] = item
        } else {
            queue.append(item)
        }
        outboxBySpace[spaceId] = queue
    }

    private func replacePendingRecordOutboxOperation(with mergedRecord: RecordItem, baseRevision: Int64, in spaceId: UUID) {
        var queue = outboxBySpace[spaceId] ?? []
        queue.removeAll { $0.operation.entityType == .record && $0.operation.entityId == mergedRecord.id }
        outboxBySpace[spaceId] = queue
        _ = try? queueRecordUpsert(mergedRecord, spaceMode: .arcaSync)
    }

    private func removePendingRecordFromOutbox(recordId: UUID, in spaceId: UUID) {
        var queue = outboxBySpace[spaceId] ?? []
        queue.removeAll { $0.operation.entityType == .record && $0.operation.entityId == recordId }
        outboxBySpace[spaceId] = queue
    }

    private func resolveKeyRing(for spaceId: UUID, keyGeneration: Int, keyId: UUID) throws -> SpaceKeyRing {
        if let ring = spaceKeyRingsBySpace[spaceId]?[keyGeneration], ring.keyId == keyId {
            return ring
        }
        let active = activeSpaceKeyRing(for: spaceId)
        if active.keyId == keyId {
            return active
        }
        throw SyncServiceError.spaceKeyMismatch(expectedGeneration: active.keyGeneration, actualGeneration: keyGeneration)
    }
}
