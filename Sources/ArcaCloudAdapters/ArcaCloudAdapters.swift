import Foundation
import CryptoKit
import ArcaCore
import ArcaCrypto
import ArcaArchive

// MARK: - Provider Policy Compliance & Nuanced Classification Assessment

/// Compliance status determined when evaluating a Space for an optional Personal Cloud Backup provider.
public enum ProviderPolicyComplianceStatus: String, Codable, Sendable, Equatable {
    /// Permitted for direct client-side encrypted backup archive upload.
    case permittedForEncryptedBackup = "permitted_for_encrypted_backup"
    /// Requires explicit user confirmation and provider terms review before enabling.
    case conditionalRequiresTermsConfirmation = "conditional_requires_terms_confirmation"
    /// Blocked due to platform/provider policy restrictions (e.g., iCloud terms regarding sensitive health templates).
    case restrictedByProviderPolicy = "restricted_by_provider_policy"
}

/// Evaluates provider policies, encryption boundaries, and platform restrictions for a given
/// `PersonalCloudProvider` and `SpaceMetadata`.
///
/// Architectural & Policy Principles:
/// 1. Arca is a general-purpose personal records app with user-defined schemas (not a regulated healthcare
///    provider app or medical device), and client-side encryption (`ArcaCrypto`) is applied independently
///    of the storage provider prior to upload.
/// 2. However, client-side encryption does **not** automatically create an exemption from storage provider
///    terms of service or platform review guidelines.
/// 3. Arca never promises iCloud storage for Personal Health Information (`containsSensitiveHealthTemplate`).
/// 4. Arca never silently falls back to Arca Cloud if a personal cloud provider fails, is restricted, or is offline.
public struct ProviderPolicyAssessment: Codable, Sendable, Equatable {
    public let provider: PersonalCloudProvider
    public let spaceId: UUID
    public let spaceName: String
    public let containsSensitiveHealthTemplate: Bool
    public let status: ProviderPolicyComplianceStatus
    public let isPermittedForBackup: Bool
    public let allowsSilentFallbackToArcaCloud: Bool
    public let clientSideEncryptedPriorToUpload: Bool
    public let productClassificationExplanation: String
    public let termsExemptionCaveatExplanation: String
    public let providerSpecificExplanation: String
    public let fallbackGuaranteeExplanation: String

    public init(
        provider: PersonalCloudProvider,
        spaceId: UUID,
        spaceName: String,
        containsSensitiveHealthTemplate: Bool,
        status: ProviderPolicyComplianceStatus,
        isPermittedForBackup: Bool,
        allowsSilentFallbackToArcaCloud: Bool = false,
        clientSideEncryptedPriorToUpload: Bool = true,
        productClassificationExplanation: String,
        termsExemptionCaveatExplanation: String,
        providerSpecificExplanation: String,
        fallbackGuaranteeExplanation: String
    ) {
        self.provider = provider
        self.spaceId = spaceId
        self.spaceName = spaceName
        self.containsSensitiveHealthTemplate = containsSensitiveHealthTemplate
        self.status = status
        self.isPermittedForBackup = isPermittedForBackup
        self.allowsSilentFallbackToArcaCloud = allowsSilentFallbackToArcaCloud
        self.clientSideEncryptedPriorToUpload = clientSideEncryptedPriorToUpload
        self.productClassificationExplanation = productClassificationExplanation
        self.termsExemptionCaveatExplanation = termsExemptionCaveatExplanation
        self.providerSpecificExplanation = providerSpecificExplanation
        self.fallbackGuaranteeExplanation = fallbackGuaranteeExplanation
    }

    /// Evaluates whether a Space can use the given `PersonalCloudProvider` for encrypted portable archive backups.
    public static func evaluate(
        provider: PersonalCloudProvider,
        for space: SpaceMetadata
    ) -> ProviderPolicyAssessment {
        let classificationCopy =
            "Arca is a general-purpose personal records app with user-defined schemas—not a regulated healthcare " +
            "provider app. Client-side AES-GCM-256 encryption is applied on your device independently of the storage " +
            "provider before any backup payload is written or uploaded."

        let caveatCopy =
            "However, applying client-side encryption does not automatically create an exemption from third-party " +
            "storage provider terms of service, platform guidelines, or regulatory obligations."

        let fallbackCopy =
            "Arca never silently falls back to Arca Cloud if \(provider.displayName) is restricted, unauthenticated, " +
            "or offline. Your storage boundary choice is strictly respected."

        switch provider {
        case .iCloudDrive:
            if space.containsSensitiveHealthTemplate {
                return ProviderPolicyAssessment(
                    provider: provider,
                    spaceId: space.id,
                    spaceName: space.name,
                    containsSensitiveHealthTemplate: true,
                    status: .restrictedByProviderPolicy,
                    isPermittedForBackup: false,
                    allowsSilentFallbackToArcaCloud: false,
                    clientSideEncryptedPriorToUpload: true,
                    productClassificationExplanation: classificationCopy,
                    termsExemptionCaveatExplanation: caveatCopy,
                    providerSpecificExplanation:
                        "Arca does not promise or enable automatic iCloud Drive storage for Spaces flagged with " +
                        "sensitive health templates (such as Medical Visits). Use Local-Only storage with manual " +
                        "encrypted exports, or opt in to dedicated end-to-end encrypted Arca Sync.",
                    fallbackGuaranteeExplanation: fallbackCopy
                )
            } else {
                return ProviderPolicyAssessment(
                    provider: provider,
                    spaceId: space.id,
                    spaceName: space.name,
                    containsSensitiveHealthTemplate: false,
                    status: .permittedForEncryptedBackup,
                    isPermittedForBackup: true,
                    allowsSilentFallbackToArcaCloud: false,
                    clientSideEncryptedPriorToUpload: true,
                    productClassificationExplanation: classificationCopy,
                    termsExemptionCaveatExplanation: caveatCopy,
                    providerSpecificExplanation:
                        "Eligible for optional encrypted portable archive backup to iCloud Drive. Backups are " +
                        "sealed on-device with AES-GCM-256 prior to transfer and are separate from real-time sync.",
                    fallbackGuaranteeExplanation: fallbackCopy
                )
            }

        case .googleDrive:
            let status: ProviderPolicyComplianceStatus = space.containsSensitiveHealthTemplate
                ? .conditionalRequiresTermsConfirmation
                : .permittedForEncryptedBackup

            let providerNote: String
            if space.containsSensitiveHealthTemplate {
                providerNote =
                    "This Space includes a sensitive health template. While Arca encrypts the entire backup archive " +
                    "on-device before upload, you must confirm that storing encrypted personal health notes in your " +
                    "personal Google Drive complies with your applicable account terms."
            } else {
                providerNote =
                    "Eligible for optional encrypted portable archive backup to Google Drive. Backups are " +
                    "sealed on-device with AES-GCM-256 prior to transfer and are separate from real-time sync."
            }

            return ProviderPolicyAssessment(
                provider: provider,
                spaceId: space.id,
                spaceName: space.name,
                containsSensitiveHealthTemplate: space.containsSensitiveHealthTemplate,
                status: status,
                isPermittedForBackup: true,
                allowsSilentFallbackToArcaCloud: false,
                clientSideEncryptedPriorToUpload: true,
                productClassificationExplanation: classificationCopy,
                termsExemptionCaveatExplanation: caveatCopy,
                providerSpecificExplanation: providerNote,
                fallbackGuaranteeExplanation: fallbackCopy
            )
        }
    }
}

// MARK: - Personal Cloud Backup Receipt & Errors

/// Metadata receipt for an encrypted portable archive uploaded to a personal cloud backup adapter.
/// Note: Backup adapters operate on full encrypted `.arcaarchive` snapshots and are explicitly separated from real-time operation-log sync.
public struct PersonalCloudBackupReceipt: Identifiable, Codable, Sendable, Equatable, Hashable {
    public var id: UUID { backupId }
    public let backupId: UUID
    public let provider: PersonalCloudProvider
    public let spaceId: UUID
    public let archiveId: UUID
    public let keyId: UUID
    public let uploadedAt: Date
    public let ciphertextByteCount: Int
    public let ciphertextSha256Hex: String
    public let remoteRelativePath: String
    public let proxiedPlaintextThroughArcaServers: Bool
    public let isSimulatedLocalStaging: Bool

    public init(
        backupId: UUID = UUID(),
        provider: PersonalCloudProvider,
        spaceId: UUID,
        archiveId: UUID,
        keyId: UUID,
        uploadedAt: Date = Date(),
        ciphertextByteCount: Int,
        ciphertextSha256Hex: String,
        remoteRelativePath: String,
        proxiedPlaintextThroughArcaServers: Bool = false,
        isSimulatedLocalStaging: Bool = true
    ) {
        self.backupId = backupId
        self.provider = provider
        self.spaceId = spaceId
        self.archiveId = archiveId
        self.keyId = keyId
        self.uploadedAt = uploadedAt
        self.ciphertextByteCount = ciphertextByteCount
        self.ciphertextSha256Hex = ciphertextSha256Hex
        self.remoteRelativePath = remoteRelativePath
        self.proxiedPlaintextThroughArcaServers = proxiedPlaintextThroughArcaServers
        self.isSimulatedLocalStaging = isSimulatedLocalStaging
    }
}

public enum PersonalCloudBackupError: LocalizedError, Sendable, Equatable {
    case policyRestricted(ProviderPolicyAssessment)
    case termsConfirmationRequired(ProviderPolicyAssessment)
    case providerOffline(PersonalCloudProvider)
    case backupNotFound(UUID)
    case ciphertextIntegrityMismatch(expected: String, actual: String)
    case invalidArchiveSource
    case ioFailure(String)

    public var errorDescription: String? {
        switch self {
        case .policyRestricted(let assessment):
            return assessment.providerSpecificExplanation
        case .termsConfirmationRequired(let assessment):
            return assessment.providerSpecificExplanation
        case .providerOffline(let provider):
            return "\(provider.displayName) is currently offline or unreachable. Arca will not silently fall back to Arca Cloud; your local data remains safe on this device."
        case .backupNotFound(let id):
            return "Personal cloud backup \(id.uuidString) could not be found."
        case .ciphertextIntegrityMismatch:
            return "Downloaded cloud backup failed SHA-256 ciphertext integrity verification."
        case .invalidArchiveSource:
            return "The specified local archive could not be packaged for encrypted backup."
        case .ioFailure(let reason):
            return "Personal cloud backup storage error: \(reason)"
        }
    }
}

// MARK: - PersonalCloudBackupAdapter Protocol

/// Contract for optional, modular personal-cloud backup adapters (`iCloud Drive` and `Google Drive`).
///
/// Key Guarantees:
/// - Separate capability from real-time sync (snapshot backup/restore).
/// - Encrypts portable archives on-device (`ClientCryptoEngine`) prior to upload.
/// - Uploads ciphertext directly to the provider target without proxying plaintext through Arca servers.
/// - Never silently falls back to Arca Cloud on error or offline state.
public protocol PersonalCloudBackupAdapter: Sendable {
    var provider: PersonalCloudProvider { get }
    var isSimulatedLocalStagingAdapter: Bool { get }
    var adapterStatusDisclosure: String { get }

    func assessPolicy(for space: SpaceMetadata) -> ProviderPolicyAssessment

    func uploadEncryptedBackup(
        archiveURL: URL,
        space: SpaceMetadata,
        spaceKeyRing: SpaceKeyRing,
        userConfirmedConditionalTerms: Bool
    ) async throws -> PersonalCloudBackupReceipt

    func downloadAndDecryptBackup(
        receipt: PersonalCloudBackupReceipt,
        spaceKeyRing: SpaceKeyRing,
        destinationDirectory: URL
    ) async throws -> URL

    func listBackups(for spaceId: UUID) async throws -> [PersonalCloudBackupReceipt]

    func deleteBackup(backupId: UUID) async throws
}

// MARK: - SimulatedPersonalCloudBackupEngine

/// Local filesystem staging implementation of `PersonalCloudBackupAdapter` used until external
/// platform entitlements (`iCloud Documents` container) or Google OAuth credentials are configured.
///
/// Performs real `AES-GCM-256` envelope encryption via `ClientCryptoEngine` on the portable `.arcaarchive`
/// before writing the ciphertext to the isolated provider staging folder.
public actor SimulatedPersonalCloudBackupEngine: PersonalCloudBackupAdapter {
    public nonisolated let provider: PersonalCloudProvider
    public nonisolated let isSimulatedLocalStagingAdapter: Bool = true
    public nonisolated let stagingRootDirectory: URL

    private var isOnline: Bool = true
    private var receiptsById: [UUID: PersonalCloudBackupReceipt] = [:]
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public nonisolated var adapterStatusDisclosure: String {
        "Local Filesystem Staging Adapter for \(provider.displayName): Encrypts portable archives on-device " +
        "with AES-GCM-256 (ClientCryptoEngine) and writes ciphertext directly to an isolated local staging " +
        "directory until external \(provider.displayName) OAuth/entitlement credentials are configured. " +
        "Plaintext is never proxied through Arca servers, and failures never fall back to Arca Cloud."
    }

    public init(
        provider: PersonalCloudProvider,
        stagingRootDirectory: URL? = nil
    ) {
        self.provider = provider
        let defaultRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArcaPersonalCloudStaging", isDirectory: true)
            .appendingPathComponent(provider.rawValue, isDirectory: true)
        let resolvedRoot = stagingRootDirectory ?? defaultRoot
        self.stagingRootDirectory = resolvedRoot

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.sortedKeys, .prettyPrinted]
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec

        try? FileManager.default.createDirectory(at: resolvedRoot, withIntermediateDirectories: true)
    }

    /// Configures simulated reachability for testing offline failure handling (verifying no silent fallback to Arca Cloud).
    public func setSimulatedOnlineState(_ online: Bool) {
        self.isOnline = online
    }

    public nonisolated func assessPolicy(for space: SpaceMetadata) -> ProviderPolicyAssessment {
        ProviderPolicyAssessment.evaluate(provider: provider, for: space)
    }

    /// Packages and encrypts a portable `.arcaarchive` on-device using `ClientCryptoEngine` and uploads the
    /// resulting `EncryptedEnvelope` ciphertext directly to the provider target.
    public func uploadEncryptedBackup(
        archiveURL: URL,
        space: SpaceMetadata,
        spaceKeyRing: SpaceKeyRing,
        userConfirmedConditionalTerms: Bool = false
    ) async throws -> PersonalCloudBackupReceipt {
        let assessment = assessPolicy(for: space)
        guard assessment.isPermittedForBackup else {
            throw PersonalCloudBackupError.policyRestricted(assessment)
        }
        if assessment.status == .conditionalRequiresTermsConfirmation && !userConfirmedConditionalTerms {
            throw PersonalCloudBackupError.termsConfirmationRequired(assessment)
        }
        guard isOnline else {
            throw PersonalCloudBackupError.providerOffline(provider)
        }

        // Load portable archive structure and serialize canonically on-device before encryption
        let portablePackage = try PortableSpaceArchive.loadPackage(from: archiveURL)
        let privacyDecoder = JSONDecoder(); privacyDecoder.dateDecodingStrategy = .iso8601
        let schemas = try privacyDecoder.decode([CollectionSchema].self, from: portablePackage.collectionsJSONData)
        guard space.storageMode != .localOnly, !schemas.contains(where: { schema in
            CloudPrivacyPolicy.isCollectionLocalOnly(schema) || schema.fields.contains(where: { $0.privacy == .localOnly })
        }) else {
            throw PersonalCloudBackupError.ioFailure("This archive contains data restricted to this device. Use an explicitly encrypted local export.")
        }
        let serializedArchiveData = try encoder.encode(portablePackage)

        let backupId = UUID()
        let aadString = "arca.personal-cloud-backup.v1:\(provider.rawValue):space:\(space.id.uuidString):archive:\(portablePackage.manifest.archiveId.uuidString)"
        let encryptedEnvelope = try ClientCryptoEngine.encryptPayload(
            serializedArchiveData,
            using: spaceKeyRing.symmetricKey,
            keyId: spaceKeyRing.keyId,
            aad: Data(aadString.utf8),
            aadDescription: "personal-cloud-archive-v1"
        )

        let ciphertextData = try encoder.encode(encryptedEnvelope)
        let ciphertextSha = ClientCryptoEngine.sha256Hex(of: ciphertextData)

        let spaceFolder = stagingRootDirectory.appendingPathComponent(space.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: spaceFolder, withIntermediateDirectories: true)

        let fileName = "\(backupId.uuidString).arcaarchive.cloudenc"
        let targetURL = spaceFolder.appendingPathComponent(fileName, isDirectory: false)
        try ciphertextData.write(to: targetURL, options: .atomic)

        let receipt = PersonalCloudBackupReceipt(
            backupId: backupId,
            provider: provider,
            spaceId: space.id,
            archiveId: portablePackage.manifest.archiveId,
            keyId: spaceKeyRing.keyId,
            uploadedAt: Date(),
            ciphertextByteCount: ciphertextData.count,
            ciphertextSha256Hex: ciphertextSha,
            remoteRelativePath: "\(space.id.uuidString)/\(fileName)",
            proxiedPlaintextThroughArcaServers: false,
            isSimulatedLocalStaging: true
        )
        receiptsById[backupId] = receipt
        return receipt
    }

    /// Downloads the encrypted envelope from the provider staging area, verifies its SHA-256 digest,
    /// decrypts it on-device using `ClientCryptoEngine`, and writes the restored `.arcaarchive` bundle.
    public func downloadAndDecryptBackup(
        receipt: PersonalCloudBackupReceipt,
        spaceKeyRing: SpaceKeyRing,
        destinationDirectory: URL
    ) async throws -> URL {
        guard isOnline else {
            throw PersonalCloudBackupError.providerOffline(provider)
        }

        let sourceURL = stagingRootDirectory.appendingPathComponent(receipt.remoteRelativePath, isDirectory: false)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw PersonalCloudBackupError.backupNotFound(receipt.backupId)
        }

        let ciphertextData = try Data(contentsOf: sourceURL)
        let actualSha = ClientCryptoEngine.sha256Hex(of: ciphertextData)
        guard actualSha == receipt.ciphertextSha256Hex else {
            throw PersonalCloudBackupError.ciphertextIntegrityMismatch(
                expected: receipt.ciphertextSha256Hex,
                actual: actualSha
            )
        }

        let envelope = try decoder.decode(EncryptedEnvelope.self, from: ciphertextData)
        let aadString = "arca.personal-cloud-backup.v1:\(provider.rawValue):space:\(receipt.spaceId.uuidString):archive:\(receipt.archiveId.uuidString)"
        let decryptedData = try ClientCryptoEngine.decryptPayload(
            envelope,
            using: spaceKeyRing.symmetricKey,
            expectedAAD: Data(aadString.utf8)
        )

        let portablePackage = try decoder.decode(PortableSpaceArchive.self, from: decryptedData)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        let restoredBundleURL = destinationDirectory.appendingPathComponent(
            "Restored-\(receipt.backupId.uuidString.prefix(8)).arcaarchive",
            isDirectory: true
        )
        try portablePackage.writeBundleDirectory(to: restoredBundleURL)
        return restoredBundleURL
    }

    public func listBackups(for spaceId: UUID) async throws -> [PersonalCloudBackupReceipt] {
        guard isOnline else {
            throw PersonalCloudBackupError.providerOffline(provider)
        }
        return receiptsById.values
            .filter { $0.spaceId == spaceId }
            .sorted { $0.uploadedAt > $1.uploadedAt }
    }

    public func deleteBackup(backupId: UUID) async throws {
        guard isOnline else {
            throw PersonalCloudBackupError.providerOffline(provider)
        }
        guard let receipt = receiptsById.removeValue(forKey: backupId) else {
            throw PersonalCloudBackupError.backupNotFound(backupId)
        }
        let targetURL = stagingRootDirectory.appendingPathComponent(receipt.remoteRelativePath, isDirectory: false)
        if FileManager.default.fileExists(atPath: targetURL.path) {
            try? FileManager.default.removeItem(at: targetURL)
        }
    }

    /// Reads the raw stored bytes at the provider target path so tests can verify that only ciphertext (no plaintext) is stored.
    public func inspectRawStoredBytes(for receipt: PersonalCloudBackupReceipt) throws -> Data {
        let targetURL = stagingRootDirectory.appendingPathComponent(receipt.remoteRelativePath, isDirectory: false)
        guard FileManager.default.fileExists(atPath: targetURL.path) else {
            throw PersonalCloudBackupError.backupNotFound(receipt.backupId)
        }
        return try Data(contentsOf: targetURL)
    }
}
