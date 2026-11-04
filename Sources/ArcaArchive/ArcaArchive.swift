import Foundation
import CryptoKit
import ArcaCore
import ArcaCrypto
import ArcaPersistence

// MARK: - Archive Errors & Duplicate Policies

/// Errors thrown during portable archive export, inspection, or staged restore.
/// Never logs or embeds user record plaintext, schema labels, attachment filenames, or encryption keys.
public enum ArchiveError: LocalizedError, Sendable, Equatable {
    case unsafePathDetected(String)
    case integrityCheckFailed(String)
    case unsupportedFormatVersion(String)
    case passphraseRequired
    case decryptionFailed
    case corruptedArchive(String)
    case missingRequiredComponent(String)

    public var errorDescription: String? {
        switch self {
        case .unsafePathDetected(let reason):
            return "Archive rejected due to an unsafe relative path (\(reason))."
        case .integrityCheckFailed(let reason):
            return "Archive integrity verification failed: \(reason)"
        case .unsupportedFormatVersion(let version):
            return "Unsupported archive format version (\(version))."
        case .passphraseRequired:
            return "A nonempty password is required for encrypted backup export or restore."
        case .decryptionFailed:
            return "Failed to decrypt archive. The passphrase may be incorrect or the ciphertext was modified."
        case .corruptedArchive(let reason):
            return "Archive structure is corrupted: \(reason)"
        case .missingRequiredComponent(let component):
            return "Archive is missing required component: \(component)"
        }
    }
}

/// Policy controlling how identity and duplicate IDs are handled when restoring a portable archive.
public enum RestoreDuplicatePolicy: String, Codable, CaseIterable, Sendable, Equatable {
    /// Default safe behavior: restores into a brand-new Space with fresh Space, Collection, Record, and Attachment UUIDs
    /// so existing live Spaces can never be overwritten or mutated.
    case restoreAsNewSpaceWithFreshIdentity = "restore_as_new_space_fresh_identity"
    /// Preserves the archive's original UUIDs if no Space with that ID exists in the catalog; otherwise assigns a fresh Space ID.
    case preserveOriginalIdentityIfUnused = "preserve_original_identity_if_unused"
}

// MARK: - Archive Manifest (Format Version 1.0)

/// Versioned manifest (`manifest.json`) stored inside every `.arcaarchive` bundle.
/// Contains SHA-256 digests for `collections.json`, `records.json`, every relative attachment path,
/// and an overall canonical manifest integrity SHA-256 digest.
public struct ArchiveManifest: Codable, Sendable, Equatable, Hashable {
    public static let currentFormatVersion: String = "1.0"

    public var formatVersion: String
    public var archiveId: UUID
    public var exportedAt: Date
    public var spaceMetadata: SpaceMetadata
    public var collectionCount: Int
    public var recordCount: Int
    /// Maps relative attachment path (e.g. `attachments/<uuid>.bin`) -> lowercase SHA-256 hex digest.
    public var attachmentDigests: [String: String]
    public var collectionsSha256Hex: String
    public var recordsSha256Hex: String
    public var manifestIntegritySha256Hex: String

    public init(
        formatVersion: String = ArchiveManifest.currentFormatVersion,
        archiveId: UUID = UUID(),
        exportedAt: Date = Date(),
        spaceMetadata: SpaceMetadata,
        collectionCount: Int,
        recordCount: Int,
        attachmentDigests: [String: String],
        collectionsSha256Hex: String,
        recordsSha256Hex: String,
        manifestIntegritySha256Hex: String = ""
    ) {
        self.formatVersion = formatVersion
        self.archiveId = archiveId
        self.exportedAt = exportedAt
        self.spaceMetadata = spaceMetadata
        self.collectionCount = collectionCount
        self.recordCount = recordCount
        self.attachmentDigests = attachmentDigests
        self.collectionsSha256Hex = collectionsSha256Hex
        self.recordsSha256Hex = recordsSha256Hex
        if manifestIntegritySha256Hex.isEmpty {
            self.manifestIntegritySha256Hex = Self.computeIntegrityDigest(
                formatVersion: formatVersion,
                archiveId: archiveId,
                exportedAt: exportedAt,
                spaceId: spaceMetadata.id,
                collectionCount: collectionCount,
                recordCount: recordCount,
                attachmentDigests: attachmentDigests,
                collectionsSha256Hex: collectionsSha256Hex,
                recordsSha256Hex: recordsSha256Hex
            )
        } else {
            self.manifestIntegritySha256Hex = manifestIntegritySha256Hex
        }
    }

    /// Deterministically computes the canonical SHA-256 integrity digest over all manifest fields.
    public func computeCanonicalIntegrityDigest() -> String {
        Self.computeIntegrityDigest(
            formatVersion: formatVersion,
            archiveId: archiveId,
            exportedAt: exportedAt,
            spaceId: spaceMetadata.id,
            collectionCount: collectionCount,
            recordCount: recordCount,
            attachmentDigests: attachmentDigests,
            collectionsSha256Hex: collectionsSha256Hex,
            recordsSha256Hex: recordsSha256Hex
        )
    }

    public static func computeIntegrityDigest(
        formatVersion: String,
        archiveId: UUID,
        exportedAt: Date,
        spaceId: UUID,
        collectionCount: Int,
        recordCount: Int,
        attachmentDigests: [String: String],
        collectionsSha256Hex: String,
        recordsSha256Hex: String
    ) -> String {
        let sortedAttachments = attachmentDigests
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.lowercased())" }
            .joined(separator: ";")

        let epochSeconds = Int64(exportedAt.timeIntervalSince1970)
        let canonicalString = [
            "v:\(formatVersion)",
            "archive:\(archiveId.uuidString.lowercased())",
            "exported:\(epochSeconds)",
            "space:\(spaceId.uuidString.lowercased())",
            "collectionsCount:\(collectionCount)",
            "recordsCount:\(recordCount)",
            "collectionsSha:\(collectionsSha256Hex.lowercased())",
            "recordsSha:\(recordsSha256Hex.lowercased())",
            "attachments:[\(sortedAttachments)]"
        ].joined(separator: "|")

        return ClientCryptoEngine.sha256Hex(of: Data(canonicalString.utf8))
    }
}

// MARK: - PortableSpaceArchive Container

/// Portable container representing a Space archive (`.arcaarchive` bundle directory or `.arcaarchive.enc` encrypted file)
/// containing `manifest.json`, `collections.json`, `records.json`, and `attachments/<relativePath>`.
public struct PortableSpaceArchive: Codable, Sendable, Equatable {
    public static let manifestFileName = "manifest.json"
    public static let collectionsFileName = "collections.json"
    public static let recordsFileName = "records.json"
    public static let attachmentsDirectoryName = "attachments"

    public var manifest: ArchiveManifest
    public var collectionsJSONData: Data
    public var recordsJSONData: Data
    /// Keyed by relative path inside the archive (e.g., `attachments/<filename>`).
    public var attachmentBlobs: [String: Data]

    public init(
        manifest: ArchiveManifest,
        collectionsJSONData: Data,
        recordsJSONData: Data,
        attachmentBlobs: [String: Data]
    ) {
        self.manifest = manifest
        self.collectionsJSONData = collectionsJSONData
        self.recordsJSONData = recordsJSONData
        self.attachmentBlobs = attachmentBlobs
    }

    /// Writes the portable archive as a `.arcaarchive` bundle directory on disk containing
    /// `manifest.json`, `collections.json`, `records.json`, and `attachments/<relativePath>`.
    public func writeBundleDirectory(to bundleURL: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: bundleURL.path) {
            try fm.removeItem(at: bundleURL)
        }
        try fm.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        let attachmentsRoot = bundleURL.appendingPathComponent(Self.attachmentsDirectoryName, isDirectory: true)
        try fm.createDirectory(at: attachmentsRoot, withIntermediateDirectories: true)

        let encoder = Self.makeCanonicalEncoder()
        let manifestData = try encoder.encode(manifest)

        try manifestData.write(
            to: bundleURL.appendingPathComponent(Self.manifestFileName, isDirectory: false),
            options: .atomic
        )
        try collectionsJSONData.write(
            to: bundleURL.appendingPathComponent(Self.collectionsFileName, isDirectory: false),
            options: .atomic
        )
        try recordsJSONData.write(
            to: bundleURL.appendingPathComponent(Self.recordsFileName, isDirectory: false),
            options: .atomic
        )

        for (relativePath, data) in attachmentBlobs {
            try ArchivePathValidator.validateRelativePath(relativePath, withinRoot: bundleURL)
            let targetURL = bundleURL.appendingPathComponent(relativePath, isDirectory: false)
            try fm.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: targetURL, options: .atomic)
        }
    }

    /// Loads a `PortableSpaceArchive` from either a `.arcaarchive` directory bundle or a serialized/encrypted file.
    public static func loadPackage(from url: URL, passphrase: String? = nil) throws -> PortableSpaceArchive {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
            throw ArchiveError.missingRequiredComponent("Archive file or directory does not exist.")
        }

        if isDir.boolValue {
            return try loadFromBundleDirectory(url)
        } else {
            return try loadFromSingleFile(url, passphrase: passphrase)
        }
    }

    private static func loadFromBundleDirectory(_ bundleURL: URL) throws -> PortableSpaceArchive {
        let fm = FileManager.default

        // Check for symlinks anywhere in the bundle directory before reading
        try ArchivePathValidator.rejectSymlinksRecursively(in: bundleURL)

        let manifestURL = bundleURL.appendingPathComponent(Self.manifestFileName, isDirectory: false)
        let collectionsURL = bundleURL.appendingPathComponent(Self.collectionsFileName, isDirectory: false)
        let recordsURL = bundleURL.appendingPathComponent(Self.recordsFileName, isDirectory: false)

        guard fm.fileExists(atPath: manifestURL.path) else {
            throw ArchiveError.missingRequiredComponent(Self.manifestFileName)
        }
        guard fm.fileExists(atPath: collectionsURL.path) else {
            throw ArchiveError.missingRequiredComponent(Self.collectionsFileName)
        }
        guard fm.fileExists(atPath: recordsURL.path) else {
            throw ArchiveError.missingRequiredComponent(Self.recordsFileName)
        }

        let manifestData = try Data(contentsOf: manifestURL)
        let collectionsData = try Data(contentsOf: collectionsURL)
        let recordsData = try Data(contentsOf: recordsURL)

        let decoder = makeCanonicalDecoder()
        let manifest: ArchiveManifest
        do {
            manifest = try decoder.decode(ArchiveManifest.self, from: manifestData)
        } catch {
            throw ArchiveError.integrityCheckFailed("manifest.json is corrupted or unreadable.")
        }

        var blobs: [String: Data] = [:]
        // Read all declared attachment paths (validating path safety first)
        for relativePath in manifest.attachmentDigests.keys {
            try ArchivePathValidator.validateRelativePath(relativePath, withinRoot: bundleURL)
            let fileURL = bundleURL.appendingPathComponent(relativePath, isDirectory: false)
            guard fm.fileExists(atPath: fileURL.path) else {
                throw ArchiveError.integrityCheckFailed("Declared attachment is missing from archive.")
            }
            blobs[relativePath] = try Data(contentsOf: fileURL)
        }

        // Also scan attachments directory for any undeclared files
        let attachmentsDir = bundleURL.appendingPathComponent(Self.attachmentsDirectoryName, isDirectory: true)
        if fm.fileExists(atPath: attachmentsDir.path) {
            if let enumerator = fm.enumerator(at: attachmentsDir, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) {
                for case let fileURL as URL in enumerator {
                    let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                    if values?.isSymbolicLink == true {
                        throw ArchiveError.unsafePathDetected("Symbolic link detected in attachments directory")
                    }
                    if values?.isRegularFile == true {
                        let relPath = "\(Self.attachmentsDirectoryName)/\(fileURL.lastPathComponent)"
                        if blobs[relPath] == nil {
                            blobs[relPath] = try Data(contentsOf: fileURL)
                        }
                    }
                }
            }
        }

        return PortableSpaceArchive(
            manifest: manifest,
            collectionsJSONData: collectionsData,
            recordsJSONData: recordsData,
            attachmentBlobs: blobs
        )
    }

    private static func loadFromSingleFile(_ fileURL: URL, passphrase: String?) throws -> PortableSpaceArchive {
        try ArchivePathValidator.rejectIfSymlink(at: fileURL)
        let rawData = try Data(contentsOf: fileURL)
        let magicHeader = Data("ARCAENC1".utf8)
        let isEncrypted = (rawData.count >= magicHeader.count && rawData.prefix(magicHeader.count) == magicHeader)
            || fileURL.pathExtension.lowercased() == "enc"

        let packageData: Data
        if isEncrypted {
            guard let passphrase, !passphrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ArchiveError.passphraseRequired
            }
            do {
                packageData = try ClientCryptoEngine.decryptArchiveWithPassphrase(rawData, passphrase: passphrase)
            } catch {
                throw ArchiveError.decryptionFailed
            }
        } else {
            packageData = rawData
        }

        let decoder = makeCanonicalDecoder()
        do {
            return try decoder.decode(PortableSpaceArchive.self, from: packageData)
        } catch {
            throw ArchiveError.integrityCheckFailed("Archive container payload is corrupted or invalid JSON.")
        }
    }

    internal static func makeCanonicalEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return encoder
    }

    internal static func makeCanonicalDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

// MARK: - Path Traversal & Symlink Validator

/// Enforces strict path safety rules on all relative paths inside `.arcaarchive` packages and staging directories.
public enum ArchivePathValidator {

    /// Rejects unsafe relative paths (`..`, leading `/`, backslashes `\`, null bytes, control chars, or paths escaping `rootURL`).
    public static func validateRelativePath(_ relativePath: String, withinRoot rootURL: URL) throws {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == relativePath, !trimmed.isEmpty,
              relativePath.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw ArchiveError.unsafePathDetected("Empty path")
        }
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            throw ArchiveError.unsafePathDetected("Absolute or home-relative path prohibited")
        }
        if trimmed.contains("\\") {
            throw ArchiveError.unsafePathDetected("Backslash path separator prohibited")
        }
        if trimmed.contains("\0") {
            throw ArchiveError.unsafePathDetected("Null byte in path prohibited")
        }

        let rawSegments = trimmed.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        for segment in rawSegments {
            if segment.isEmpty || segment == "." || segment == ".." {
                throw ArchiveError.unsafePathDetected("Path traversal segment '\(segment)' prohibited")
            }
        }

        let canonicalRoot = canonicalURLResolvingExistingAncestors(rootURL)
        let standardizedRoot = canonicalRoot.path
        let candidateURL = canonicalURLResolvingExistingAncestors(canonicalRoot.appendingPathComponent(trimmed, isDirectory: false))
        let rootPrefix = standardizedRoot.hasSuffix("/") ? standardizedRoot : standardizedRoot + "/"
        guard candidateURL.path.hasPrefix(rootPrefix) else {
            throw ArchiveError.unsafePathDetected("Resolved path escapes staging directory")
        }
    }

    // iOS can preserve /var aliases for missing leaf paths while resolving an existing root
    // to /private/var. Resolve the existing ancestor first, then append missing components.
    private static func canonicalURLResolvingExistingAncestors(_ url: URL) -> URL {
        var ancestor = url.standardizedFileURL
        var missing: [String] = []
        while (try? FileManager.default.attributesOfItem(atPath: ancestor.path)) == nil && ancestor.path != "/" {
            missing.append(ancestor.lastPathComponent)
            ancestor.deleteLastPathComponent()
        }
        var result = ancestor.resolvingSymlinksInPath()
        for component in missing.reversed() { result.appendPathComponent(component) }
        return result.standardizedFileURL
    }

    /// Rejects any symbolic link at `url`.
    public static func rejectIfSymlink(at url: URL) throws {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let fileType = attrs[.type] as? FileAttributeType,
           fileType == .typeSymbolicLink {
            throw ArchiveError.unsafePathDetected("Symbolic link is not permitted")
        }
        if let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]),
           values.isSymbolicLink == true {
            throw ArchiveError.unsafePathDetected("Symbolic link is not permitted")
        }
    }

    /// Recursively scans a directory and throws `ArchiveError.unsafePathDetected` if any symbolic link is present.
    public static func rejectSymlinksRecursively(in directoryURL: URL) throws {
        try rejectIfSymlink(at: directoryURL)
        let fm = FileManager.default
        guard let items = try? fm.subpathsOfDirectory(atPath: directoryURL.path) else { return }
        for subpath in items {
            let fullURL = directoryURL.appendingPathComponent(subpath)
            try rejectIfSymlink(at: fullURL)
        }
    }
}

// MARK: - ArchiveService

/// Provides portable `.arcaarchive` / `.arcaarchive.enc` export, manifest inspection, and atomic staged restore.
public struct ArchiveService: Sendable {
    public static let shared = ArchiveService()

    public init() {}

    /// Exports a Space and all its active Collections, Records, and verified Attachments into a portable archive.
    ///
    /// - If `encryptionPassphrase` is `nil`, writes a `.arcaarchive` bundle directory containing
    ///   `manifest.json`, `collections.json`, `records.json`, and `attachments/<relativePath>`.
    /// - If `encryptionPassphrase` is non-empty, encrypts the serialized `PortableSpaceArchive` using
    ///   `ClientCryptoEngine.encryptArchiveWithPassphrase` and writes `<name>.arcaarchive.enc`.
    public func exportSpace(
        space: SpaceMetadata,
        store: SpaceStore,
        destinationDirectory: URL,
        encryptionPassphrase: String? = nil
    ) async throws -> URL {
        if let passphrase = encryptionPassphrase,
           passphrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ArchiveError.passphraseRequired
        }
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        let collections = await store.listCollections(includeDeleted: false)
        if encryptionPassphrase == nil && collections.contains(where: { schema in
            schema.privacy != nil || CloudPrivacyPolicy.isCollectionLocalOnly(schema) || schema.fields.contains(where: { $0.privacy != nil })
        }) {
            throw ArchiveError.passphraseRequired
        }
        let records = await store.listRecords(collectionId: nil, includeDeleted: false)

        var attachmentBlobs: [String: Data] = [:]
        var attachmentDigests: [String: String] = [:]
        var normalizedRecords: [RecordItem] = []

        for var record in records {
            for (fieldId, fieldValue) in record.values {
                if case .attachments(let refs) = fieldValue {
                    var updatedRefs: [AttachmentReference] = []
                    for var ref in refs {
                        let data = try await store.loadAttachmentData(for: ref)
                        let digest = ClientCryptoEngine.sha256Hex(of: data)
                        guard digest == ref.sha256Hex.lowercased() else {
                            throw ArchiveError.integrityCheckFailed("Source attachment SHA-256 mismatch during export.")
                        }
                        let archiveRelativePath = "\(PortableSpaceArchive.attachmentsDirectoryName)/\(ref.id.uuidString).bin"
                        try ArchivePathValidator.validateRelativePath(archiveRelativePath, withinRoot: destinationDirectory)
                        attachmentBlobs[archiveRelativePath] = data
                        attachmentDigests[archiveRelativePath] = digest
                        ref.localRelativePath = archiveRelativePath
                        updatedRefs.append(ref)
                    }
                    record.values[fieldId] = .attachments(updatedRefs)
                }
            }
            normalizedRecords.append(record)
        }

        let encoder = PortableSpaceArchive.makeCanonicalEncoder()
        let collectionsData = try encoder.encode(collections)
        let recordsData = try encoder.encode(normalizedRecords)

        let collectionsSha = ClientCryptoEngine.sha256Hex(of: collectionsData)
        let recordsSha = ClientCryptoEngine.sha256Hex(of: recordsData)

        let archiveId = UUID()
        let exportedAt = Date()
        let manifest = ArchiveManifest(
            formatVersion: ArchiveManifest.currentFormatVersion,
            archiveId: archiveId,
            exportedAt: exportedAt,
            spaceMetadata: space,
            collectionCount: collections.count,
            recordCount: normalizedRecords.count,
            attachmentDigests: attachmentDigests,
            collectionsSha256Hex: collectionsSha,
            recordsSha256Hex: recordsSha
        )

        let portableArchive = PortableSpaceArchive(
            manifest: manifest,
            collectionsJSONData: collectionsData,
            recordsJSONData: recordsData,
            attachmentBlobs: attachmentBlobs
        )

        let safeSpaceSlug = Self.sanitizeFileNameComponent(space.name)
        let shortId = archiveId.uuidString.prefix(8)

        if let passphrase = encryptionPassphrase, !passphrase.isEmpty {
            let plainArchiveBytes = try encoder.encode(portableArchive)
            let encryptedBytes = try ClientCryptoEngine.encryptArchiveWithPassphrase(
                plainArchiveBytes,
                passphrase: passphrase
            )
            let encryptedURL = destinationDirectory.appendingPathComponent(
                "\(safeSpaceSlug)-\(shortId).arcaarchive.enc",
                isDirectory: false
            )
            try encryptedBytes.write(to: encryptedURL, options: .atomic)
            return encryptedURL
        } else {
            let bundleURL = destinationDirectory.appendingPathComponent(
                "\(safeSpaceSlug)-\(shortId).arcaarchive",
                isDirectory: true
            )
            try portableArchive.writeBundleDirectory(to: bundleURL)
            return bundleURL
        }
    }

    /// Inspects an archive's manifest and verifies its format version and manifest integrity digest.
    public func inspectArchive(
        at url: URL,
        passphrase: String? = nil
    ) throws -> ArchiveManifest {
        let package = try PortableSpaceArchive.loadPackage(from: url, passphrase: passphrase)
        try Self.verifyPackageIntegrity(package)
        return package.manifest
    }

    /// Restores a portable archive safely into `catalog` by staging the entire unpack and full cryptographic
    /// SHA-256 verification inside an isolated temporary staging directory before touching any live data.
    ///
    /// Security & Integrity Guarantees:
    /// 1. Rejects unsafe paths (`..`, leading `/`, backslashes, symlinks, or paths escaping the staging directory)
    ///    with `ArchiveError.unsafePathDetected`.
    /// 2. Stages the entire unpack & verification in an isolated temporary staging directory first before modifying live data.
    /// 3. Verifies `collectionsSha256Hex`, `recordsSha256Hex`, `manifestIntegritySha256Hex`, and every single attachment's
    ///    SHA-256 digest against `attachmentDigests`. If any byte is corrupted or missing, throws `ArchiveError.integrityCheckFailed`
    ///    and cleans up staging without touching live data.
    /// 4. Supports encrypted archives using `ClientCryptoEngine.encryptArchiveWithPassphrase` / `decryptArchiveWithPassphrase`.
    public func restoreArchiveAsNewSpace(
        from url: URL,
        passphrase: String? = nil,
        into catalog: CatalogStore,
        spacesRootDirectory: URL,
        duplicateHandling: RestoreDuplicatePolicy = .restoreAsNewSpaceWithFreshIdentity
    ) async throws -> SpaceMetadata {
        let fm = FileManager.default
        let stagingDir = fm.temporaryDirectory
            .appendingPathComponent("ArcaArchiveStaging-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: stagingDir)
        }

        // Step 1: Load package (rejecting symlinks and decrypting if needed)
        let package = try PortableSpaceArchive.loadPackage(from: url, passphrase: passphrase)

        // Step 2: Validate all relative attachment paths against the isolated staging directory
        for relativePath in package.manifest.attachmentDigests.keys {
            try ArchivePathValidator.validateRelativePath(relativePath, withinRoot: stagingDir)
        }
        for relativePath in package.attachmentBlobs.keys {
            try ArchivePathValidator.validateRelativePath(relativePath, withinRoot: stagingDir)
        }

        // Reject invalid contents, references and schema values before creating any live state.
        let (decodedCollections, decodedRecords) = try Self.verifyPackageIntegrity(package)

        // Step 3: Materialize unpack into isolated staging directory and verify no symlinks
        let stagedBundleURL = stagingDir.appendingPathComponent("unpacked.arcaarchive", isDirectory: true)
        try package.writeBundleDirectory(to: stagedBundleURL)
        try ArchivePathValidator.rejectSymlinksRecursively(in: stagedBundleURL)


        // Step 5: Determine target Space identity & remap IDs according to `duplicateHandling`
        let existingSpaceWithSameId = await catalog.fetchSpace(id: package.manifest.spaceMetadata.id)
        let assignFreshIds: Bool
        switch duplicateHandling {
        case .restoreAsNewSpaceWithFreshIdentity:
            assignFreshIds = true
        case .preserveOriginalIdentityIfUnused:
            assignFreshIds = (existingSpaceWithSameId != nil)
        }

        let newSpaceId = assignFreshIds ? UUID() : package.manifest.spaceMetadata.id
        let restoredSpaceName: String = {
            let baseName = package.manifest.spaceMetadata.name
            if assignFreshIds && existingSpaceWithSameId != nil {
                return "\(baseName) (Restored)"
            }
            return baseName
        }()

        let now = Date()
        let restoredSpace = SpaceMetadata(
            id: newSpaceId,
            name: restoredSpaceName,
            iconName: package.manifest.spaceMetadata.iconName,
            accentHex: package.manifest.spaceMetadata.accentHex,
            storageMode: .localOnly,
            cloudSyncAcceptedAt: nil,
            personalCloudProvider: nil,
            containsSensitiveHealthTemplate: package.manifest.spaceMetadata.containsSensitiveHealthTemplate,
            createdAt: now,
            updatedAt: now,
            revision: 1
        )

        // Resolve baseDirectoryURL for SpaceStore consistent with CatalogStore
        let resolvedBaseDir: URL = {
            if spacesRootDirectory.lastPathComponent == "Spaces" {
                return spacesRootDirectory.deletingLastPathComponent()
            }
            return catalog.baseDirectoryURL
        }()

        // Step 6: Persist restored Space, Collections, Attachments, and Records into live store
        let targetDirectory = resolvedBaseDir.appendingPathComponent("Spaces").appendingPathComponent(newSpaceId.uuidString)
        guard !fm.fileExists(atPath: targetDirectory.path) else {
            throw ArchiveError.corruptedArchive("Restore destination already exists.")
        }
        var completed = false
        defer { if !completed { try? fm.removeItem(at: targetDirectory) } }
        let targetStore = SpaceStore(space: restoredSpace, baseDirectoryURL: resolvedBaseDir)

        var collectionIdMap: [UUID: UUID] = [:]
        var remappedSchemasByNewId: [UUID: CollectionSchema] = [:]

        for archivedSchema in decodedCollections {
            let originalSchema = CloudPrivacyPolicy.resettingConsent(archivedSchema)
            let newCollectionId = assignFreshIds ? UUID() : originalSchema.id
            collectionIdMap[originalSchema.id] = newCollectionId

            let remappedSchema = CollectionSchema(
                id: newCollectionId,
                spaceId: newSpaceId,
                name: originalSchema.name,
                iconName: originalSchema.iconName,
                colorHex: originalSchema.colorHex,
                schemaVersion: originalSchema.schemaVersion,
                sensitivityPosture: originalSchema.sensitivityPosture,
                privacy: originalSchema.privacy,
                fields: originalSchema.fields,
                createdAt: originalSchema.createdAt,
                updatedAt: now,
                revision: 1,
                isDeleted: originalSchema.isDeleted
            )
            remappedSchemasByNewId[newCollectionId] = remappedSchema
            await targetStore.saveCollection(remappedSchema, enqueueSync: false)
            guard await targetStore.fetchCollection(id: newCollectionId) != nil else {
                throw ArchiveError.corruptedArchive("A restored collection could not be saved.")
            }
        }

        for originalRecord in decodedRecords {
            guard let targetCollectionId = collectionIdMap[originalRecord.collectionId],
                  let targetSchema = remappedSchemasByNewId[targetCollectionId] else {
                throw ArchiveError.integrityCheckFailed("Record references a collection ID not present in collections.json.")
            }

            var remappedValues = originalRecord.values
            for (fieldId, fieldValue) in originalRecord.values {
                if case .attachments(let refs) = fieldValue {
                    var restoredRefs: [AttachmentReference] = []
                    for ref in refs {
                        try ArchivePathValidator.validateRelativePath(ref.localRelativePath, withinRoot: stagingDir)
                        guard let blobData = package.attachmentBlobs[ref.localRelativePath] else {
                            throw ArchiveError.integrityCheckFailed("Attachment blob missing for record attachment reference.")
                        }
                        let actualSha = ClientCryptoEngine.sha256Hex(of: blobData)
                        guard actualSha == ref.sha256Hex.lowercased() else {
                            throw ArchiveError.integrityCheckFailed("Attachment SHA-256 mismatch against record reference.")
                        }
                        let storedRef = try await targetStore.storeAttachment(
                            data: blobData,
                            filename: ref.filename,
                            mimeType: ref.mimeType
                        )
                        restoredRefs.append(storedRef)
                    }
                    remappedValues[fieldId] = .attachments(restoredRefs)
                }
            }

            let newRecordId = assignFreshIds ? UUID() : originalRecord.id
            let restoredRecord = RecordItem(
                id: newRecordId,
                spaceId: newSpaceId,
                collectionId: targetCollectionId,
                schemaVersionAtWrite: originalRecord.schemaVersionAtWrite,
                values: remappedValues,
                isFavorite: originalRecord.isFavorite,
                createdAt: originalRecord.createdAt,
                updatedAt: originalRecord.updatedAt,
                revision: 1,
                lastModifiedByDeviceId: originalRecord.lastModifiedByDeviceId,
                isDeleted: originalRecord.isDeleted
            )

            try await targetStore.saveRecord(restoredRecord, schema: targetSchema, enqueueSync: false)
        }

        // Publish only after every record and attachment was written successfully.
        await catalog.saveSpace(restoredSpace)
        guard await catalog.fetchSpace(id: restoredSpace.id) != nil else {
            throw ArchiveError.corruptedArchive("The restored Space could not be added to the catalog.")
        }
        completed = true
        return restoredSpace
    }

    // MARK: - Static Convenience Overloads

    public static func exportSpace(
        space: SpaceMetadata,
        store: SpaceStore,
        destinationDirectory: URL,
        encryptionPassphrase: String? = nil
    ) async throws -> URL {
        try await shared.exportSpace(
            space: space,
            store: store,
            destinationDirectory: destinationDirectory,
            encryptionPassphrase: encryptionPassphrase
        )
    }

    public static func inspectArchive(
        at url: URL,
        passphrase: String? = nil
    ) throws -> ArchiveManifest {
        try shared.inspectArchive(at: url, passphrase: passphrase)
    }

    public static func restoreArchiveAsNewSpace(
        from url: URL,
        passphrase: String? = nil,
        into catalog: CatalogStore,
        spacesRootDirectory: URL,
        duplicateHandling: RestoreDuplicatePolicy = .restoreAsNewSpaceWithFreshIdentity
    ) async throws -> SpaceMetadata {
        try await shared.restoreArchiveAsNewSpace(
            from: url,
            passphrase: passphrase,
            into: catalog,
            spacesRootDirectory: spacesRootDirectory,
            duplicateHandling: duplicateHandling
        )
    }

    // MARK: - Internal Verification Helpers

    @discardableResult
    internal static func verifyPackageIntegrity(
        _ package: PortableSpaceArchive
    ) throws -> (collections: [CollectionSchema], records: [RecordItem]) {
        let manifest = package.manifest

        guard manifest.formatVersion == ArchiveManifest.currentFormatVersion else {
            throw ArchiveError.unsupportedFormatVersion(manifest.formatVersion)
        }

        // 1. Verify overall manifest integrity digest
        let expectedManifestDigest = manifest.computeCanonicalIntegrityDigest()
        guard manifest.manifestIntegritySha256Hex.lowercased() == expectedManifestDigest.lowercased() else {
            throw ArchiveError.integrityCheckFailed("manifestIntegritySha256Hex mismatch.")
        }

        // 2. Verify collections.json SHA-256 digest
        let actualCollectionsSha = ClientCryptoEngine.sha256Hex(of: package.collectionsJSONData)
        guard actualCollectionsSha == manifest.collectionsSha256Hex.lowercased() else {
            throw ArchiveError.integrityCheckFailed("collectionsSha256Hex mismatch.")
        }

        // 3. Verify records.json SHA-256 digest
        let actualRecordsSha = ClientCryptoEngine.sha256Hex(of: package.recordsJSONData)
        guard actualRecordsSha == manifest.recordsSha256Hex.lowercased() else {
            throw ArchiveError.integrityCheckFailed("recordsSha256Hex mismatch.")
        }

        // 4. Verify every attachment digest and count
        guard package.attachmentBlobs.count == manifest.attachmentDigests.count else {
            throw ArchiveError.integrityCheckFailed("Attachment count does not match manifest attachmentDigests.")
        }

        for (relativePath, expectedSha) in manifest.attachmentDigests {
            guard let blobData = package.attachmentBlobs[relativePath] else {
                throw ArchiveError.integrityCheckFailed("Missing attachment file declared in manifest.")
            }
            let actualSha = ClientCryptoEngine.sha256Hex(of: blobData)
            guard actualSha == expectedSha.lowercased() else {
                throw ArchiveError.integrityCheckFailed("Attachment SHA-256 digest mismatch.")
            }
        }

        // 5. Decode collections & records and verify counts match manifest
        let decoder = PortableSpaceArchive.makeCanonicalDecoder()
        let collections: [CollectionSchema]
        let records: [RecordItem]
        do {
            collections = try decoder.decode([CollectionSchema].self, from: package.collectionsJSONData)
            records = try decoder.decode([RecordItem].self, from: package.recordsJSONData)
        } catch {
            throw ArchiveError.integrityCheckFailed("Failed to decode collections.json or records.json.")
        }

        guard collections.count == manifest.collectionCount else {
            throw ArchiveError.integrityCheckFailed("Decoded collection count does not match manifest collectionCount.")
        }
        guard records.count == manifest.recordCount else {
            throw ArchiveError.integrityCheckFailed("Decoded record count does not match manifest recordCount.")
        }

        let schemas = Dictionary(collections.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard schemas.count == collections.count, Set(records.map(\.id)).count == records.count else {
            throw ArchiveError.integrityCheckFailed("Duplicate collection or record identity.")
        }
        let validationRoot = FileManager.default.temporaryDirectory.appendingPathComponent("ArcaValidation")
        for path in package.attachmentBlobs.keys {
            try ArchivePathValidator.validateRelativePath(path, withinRoot: validationRoot)
            guard path.hasPrefix("attachments/") else {
                throw ArchiveError.unsafePathDetected("Attachment must be inside attachments directory")
            }
        }
        for schema in collections {
            guard schema.spaceId == manifest.spaceMetadata.id else {
                throw ArchiveError.integrityCheckFailed("Collection belongs to a different Space.")
            }
        }
        for record in records {
            guard record.spaceId == manifest.spaceMetadata.id,
                  let schema = schemas[record.collectionId],
                  SchemaEngine.validate(values: record.values, against: schema).isEmpty else {
                throw ArchiveError.integrityCheckFailed("Invalid record schema or collection reference.")
            }
            for ref in record.allAttachments {
                try ArchivePathValidator.validateRelativePath(ref.localRelativePath, withinRoot: validationRoot)
                guard let blob = package.attachmentBlobs[ref.localRelativePath],
                      blob.count == ref.byteSize,
                      ClientCryptoEngine.sha256Hex(of: blob) == ref.sha256Hex.lowercased() else {
                    throw ArchiveError.integrityCheckFailed("Invalid record attachment reference.")
                }
            }
        }
        return (collections, records)
    }

    private static func sanitizeFileNameComponent(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = raw
            .components(separatedBy: allowed.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return cleaned.isEmpty ? "Space" : String(cleaned.prefix(40))
    }
}

// MARK: - StorageModeMigrationPreview

/// Explicit impact preview computed before changing a Space's storage mode (`localOnly`, `arcaSync`, `personalCloudBackup`).
///
/// Honesty & Safety Rule:
/// Switching a Space from `arcaSync` to `localOnly` stops future uploads immediately, but NEVER implies that
/// existing encrypted cloud copies are automatically deleted unless remote deletion has been explicitly
/// requested and verified (`remoteDeletionVerified == true`).
public struct StorageModeMigrationPreview: Codable, Sendable, Equatable {
    public let fromMode: SpaceStorageMode
    public let toMode: SpaceStorageMode
    public let recordsToUploadCount: Int
    public let attachmentsToUploadCount: Int
    public let bytesToUpload: Int64
    public let whatRemainsLocalExplanation: String
    public let whatHappensToRemoteCopiesExplanation: String
    public let remoteDeletionVerified: Bool
    public let otherDevicesBehaviorExplanation: String

    public init(
        fromMode: SpaceStorageMode,
        toMode: SpaceStorageMode,
        recordsToUploadCount: Int,
        attachmentsToUploadCount: Int,
        bytesToUpload: Int64,
        whatRemainsLocalExplanation: String,
        whatHappensToRemoteCopiesExplanation: String,
        remoteDeletionVerified: Bool,
        otherDevicesBehaviorExplanation: String
    ) {
        self.fromMode = fromMode
        self.toMode = toMode
        self.recordsToUploadCount = recordsToUploadCount
        self.attachmentsToUploadCount = attachmentsToUploadCount
        self.bytesToUpload = bytesToUpload
        self.whatRemainsLocalExplanation = whatRemainsLocalExplanation
        self.whatHappensToRemoteCopiesExplanation = whatHappensToRemoteCopiesExplanation
        self.remoteDeletionVerified = remoteDeletionVerified
        self.otherDevicesBehaviorExplanation = otherDevicesBehaviorExplanation
    }

    /// Computes a deterministic preview for migrating `space` to `targetMode` given its current records.
    public static func compute(
        for space: SpaceMetadata,
        to targetMode: SpaceStorageMode,
        records: [RecordItem],
        remoteDeletionVerified: Bool = false
    ) -> StorageModeMigrationPreview {
        let activeRecords = records.filter { !$0.isDeleted }
        let allAttachments = activeRecords.flatMap(\.allAttachments)
        let attachmentBytes = allAttachments.reduce(Int64(0)) { $0 + max(0, $1.byteSize) }
        let estimatedRecordBytes = Int64(activeRecords.count * 512)

        let willUpload = (targetMode == .arcaSync || targetMode == .personalCloudBackup) && (space.storageMode != targetMode)
        let recordsToUpload = willUpload ? activeRecords.count : 0
        let attachmentsToUpload = willUpload ? allAttachments.count : 0
        let totalBytesToUpload = willUpload ? (estimatedRecordBytes + attachmentBytes) : 0

        let remainsLocalText =
            "All \(activeRecords.count) record(s) and \(allAttachments.count) attachment(s) remain stored in full " +
            "on this device inside the Space's local SQLite database. Local reading, search, and editing are never removed."

        let remoteCopiesText: String
        let otherDevicesText: String

        switch (space.storageMode, targetMode) {
        case (.arcaSync, .localOnly):
            if remoteDeletionVerified {
                remoteCopiesText =
                    "Future cloud uploads stop immediately, and deletion of existing encrypted remote copies on Arca Sync " +
                    "has been explicitly requested and verified."
                otherDevicesText =
                    "Other enrolled devices will stop receiving updates for this Space and their remote sync copy has been purged. " +
                    "Any data previously downloaded onto an offline device remains local to that device until removed there."
            } else {
                remoteCopiesText =
                    "Switching to Local-Only stops future uploads from this device immediately, but does NOT automatically " +
                    "delete existing encrypted copies already stored in Arca Cloud unless you explicitly request and verify remote deletion."
                otherDevicesText =
                    "This device will no longer push or pull changes for this Space. Other enrolled devices will retain their " +
                    "last synced state unless remote deletion is explicitly requested and verified."
            }

        case (.personalCloudBackup, .localOnly):
            if remoteDeletionVerified {
                remoteCopiesText =
                    "Automatic backup uploads stop and deletion of existing encrypted backup archives in your personal cloud " +
                    "has been explicitly requested and verified."
            } else {
                remoteCopiesText =
                    "Switching to Local-Only stops future backup uploads, but does NOT automatically delete existing encrypted " +
                    "archive files in your personal cloud drive unless you explicitly delete them and verify removal."
            }
            otherDevicesText =
                "This Space will operate strictly on this device with no external backup uploads."

        case (.localOnly, .arcaSync):
            remoteCopiesText =
                "\(recordsToUpload) record(s) and \(attachmentsToUpload) attachment(s) will be encrypted on this device " +
                "with AES-GCM-256 before being uploaded to Arca Sync."
            otherDevicesText =
                "Up to 2 active devices on the Free plan (or up to 10 on Arca Pro) enrolled with your Master Account Key " +
                "will be able to decrypt and synchronize this Space."

        case (.localOnly, .personalCloudBackup):
            remoteCopiesText =
                "A full portable archive containing \(recordsToUpload) record(s) and \(attachmentsToUpload) attachment(s) " +
                "will be encrypted on-device before being uploaded as a backup snapshot to your selected personal cloud provider."
            otherDevicesText =
                "Personal Cloud Backup creates encrypted snapshot archives for disaster recovery and is separate from live multi-device sync."

        default:
            remoteCopiesText =
                "Existing remote storage posture remains unchanged unless you initiate a mode transition or explicit remote deletion."
            otherDevicesText =
                "Enrolled devices continue following the current storage mode rules for this Space."
        }

        return StorageModeMigrationPreview(
            fromMode: space.storageMode,
            toMode: targetMode,
            recordsToUploadCount: recordsToUpload,
            attachmentsToUploadCount: attachmentsToUpload,
            bytesToUpload: totalBytesToUpload,
            whatRemainsLocalExplanation: remainsLocalText,
            whatHappensToRemoteCopiesExplanation: remoteCopiesText,
            remoteDeletionVerified: remoteDeletionVerified,
            otherDevicesBehaviorExplanation: otherDevicesText
        )
    }

    /// Async convenience overload that queries active records from `store`.
    public static func compute(
        for space: SpaceMetadata,
        to targetMode: SpaceStorageMode,
        store: SpaceStore,
        remoteDeletionVerified: Bool = false
    ) async -> StorageModeMigrationPreview {
        let records = await store.listRecords(collectionId: nil, includeDeleted: false)
        return compute(
            for: space,
            to: targetMode,
            records: records,
            remoteDeletionVerified: remoteDeletionVerified
        )
    }
}
