import Foundation
import SQLite3
import ArcaCore
import ArcaCrypto

// MARK: - SQLite Constants & Memory-Safe Helpers

internal let SQLITE_TRANSIENT_DESTRUCTOR = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum PersistenceError: LocalizedError, Sendable, Equatable {
    case databaseOpenFailed(String)
    case sqlExecutionFailed(String)
    case statementPreparationFailed(String)
    case encodingFailed
    case decodingFailed
    case spaceNotFound(UUID)
    case collectionNotFound(UUID)
    case recordValidationFailed([RecordValidationError])
    case attachmentNotFound(String)
    case attachmentIntegrityMismatch(expected: String, actual: String)
    case ioError(String)

    public var errorDescription: String? {
        switch self {
        case .databaseOpenFailed(let msg):
            return "Failed to open local database: \(msg)"
        case .sqlExecutionFailed(let msg):
            return "Database operation failed: \(msg)"
        case .statementPreparationFailed(let msg):
            return "Database query preparation failed: \(msg)"
        case .encodingFailed:
            return "Failed to encode data payload."
        case .decodingFailed:
            return "Failed to decode stored payload."
        case .spaceNotFound(let id):
            return "Space \(id.uuidString) could not be found."
        case .collectionNotFound(let id):
            return "Collection \(id.uuidString) could not be found."
        case .recordValidationFailed(let errors):
            return errors.compactMap(\.errorDescription).joined(separator: " ")
        case .attachmentNotFound(let path):
            return "Attachment file not found at \(path)."
        case .attachmentIntegrityMismatch(let expected, let actual):
            return "Attachment integrity verification failed (expected SHA-256 \(expected.prefix(12))..., got \(actual.prefix(12))...)."
        case .ioError(let msg):
            return "File system error: \(msg)"
        }
    }
}

/// Applies platform file protection attributes and backup exclusion policies for local spaces.
public enum DataProtectionConfigurator {

    /// Applies `FileProtectionType` attributes when supported by the underlying OS/filesystem.
    public static func applyProtection(
        at url: URL,
        isSensitiveLocalOnly: Bool,
        excludeFromUnencryptedBackup: Bool = false
    ) {
        let protection: FileProtectionType = isSensitiveLocalOnly
            ? .complete
            : .completeUntilFirstUserAuthentication

        try? FileManager.default.setAttributes(
            [.protectionKey: protection],
            ofItemAtPath: url.path
        )

        if excludeFromUnencryptedBackup {
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            var mutableURL = url
            try? mutableURL.setResourceValues(resourceValues)
        }
    }
}

// MARK: - CatalogStore Actor

/// Manages `catalog.sqlite` inside `baseDirectoryURL`, storing all `SpaceMetadata` entries
/// and coordinating per-Space isolated directory lifecycles (`Spaces/<id>/`).
public actor CatalogStore {
    public nonisolated let baseDirectoryURL: URL
    public nonisolated let catalogDatabaseURL: URL
    public nonisolated let spacesRootDirectoryURL: URL

    private var db: OpaquePointer?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public static func defaultBaseDirectoryURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport.appendingPathComponent("Arca", isDirectory: true)
    }

    public init(baseDirectoryURL: URL = CatalogStore.defaultBaseDirectoryURL()) {
        self.baseDirectoryURL = baseDirectoryURL
        self.catalogDatabaseURL = baseDirectoryURL.appendingPathComponent("catalog.sqlite", isDirectory: false)
        self.spacesRootDirectoryURL = baseDirectoryURL.appendingPathComponent("Spaces", isDirectory: true)

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.sortedKeys]
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec

        try? FileManager.default.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: spacesRootDirectoryURL, withIntermediateDirectories: true)

        DataProtectionConfigurator.applyProtection(at: baseDirectoryURL, isSensitiveLocalOnly: false)
        DataProtectionConfigurator.applyProtection(at: spacesRootDirectoryURL, isSensitiveLocalOnly: false)

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(catalogDatabaseURL.path, &handle, flags, nil) == SQLITE_OK, let opened = handle {
            self.db = opened
            sqlite3_busy_timeout(opened, 5_000)
            Self.executeRawSQL(on: opened, sql: "PRAGMA foreign_keys = ON;")
            Self.executeRawSQL(on: opened, sql: "PRAGMA journal_mode = WAL;")
            Self.executeRawSQL(
                on: opened,
                sql: """
                CREATE TABLE IF NOT EXISTS spaces (
                    id TEXT PRIMARY KEY,
                    payload_json TEXT NOT NULL,
                    updated_at REAL NOT NULL
                );
                """
            )
            DataProtectionConfigurator.applyProtection(at: catalogDatabaseURL, isSensitiveLocalOnly: false)
        }
    }

    deinit {
        if let db {
            sqlite3_close_v2(db)
        }
    }

    /// Returns the dedicated directory URL (`Spaces/<id>/`) for a given Space.
    public nonisolated func spaceDirectoryURL(for spaceId: UUID) -> URL {
        spacesRootDirectoryURL.appendingPathComponent(spaceId.uuidString, isDirectory: true)
    }

    // MARK: - CRUD Operations

    /// Lists all persisted `SpaceMetadata` rows ordered by creation/update timestamp.
    public func listSpaces() -> [SpaceMetadata] {
        guard let db else { return [] }
        let sql = "SELECT payload_json FROM spaces ORDER BY updated_at ASC, id ASC;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }

        var results: [SpaceMetadata] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let cStr = sqlite3_column_text(stmt, 0) else { continue }
            let jsonString = String(cString: cStr)
            if let data = jsonString.data(using: .utf8),
               let space = try? decoder.decode(SpaceMetadata.self, from: data) {
                results.append(space)
            }
        }
        return results
    }

    /// Fetches a single `SpaceMetadata` by ID if present.
    public func fetchSpace(id: UUID) -> SpaceMetadata? {
        guard let db else { return nil }
        let sql = "SELECT payload_json FROM spaces WHERE id = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        Self.bindText(stmt, index: 1, value: id.uuidString)
        guard sqlite3_step(stmt) == SQLITE_ROW,
              let cStr = sqlite3_column_text(stmt, 0) else {
            return nil
        }
        let jsonString = String(cString: cStr)
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? decoder.decode(SpaceMetadata.self, from: data)
    }

    /// Inserts or updates a `SpaceMetadata` row and ensures its isolated `Spaces/<id>/` directory exists with appropriate file protection.
    public func saveSpace(_ space: SpaceMetadata) {
        guard let db else { return }
        guard let jsonData = try? encoder.encode(space),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }

        let spaceDir = spaceDirectoryURL(for: space.id)
        try? FileManager.default.createDirectory(at: spaceDir, withIntermediateDirectories: true)

        let isSensitiveLocal = (space.storageMode == .localOnly) || space.containsSensitiveHealthTemplate
        DataProtectionConfigurator.applyProtection(
            at: spaceDir,
            isSensitiveLocalOnly: isSensitiveLocal,
            excludeFromUnencryptedBackup: space.storageMode == .localOnly
        )

        let sql = """
        INSERT INTO spaces (id, payload_json, updated_at)
        VALUES (?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            payload_json = excluded.payload_json,
            updated_at = excluded.updated_at;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(stmt) }

        Self.bindText(stmt, index: 1, value: space.id.uuidString)
        Self.bindText(stmt, index: 2, value: jsonString)
        sqlite3_bind_double(stmt, 3, space.updatedAt.timeIntervalSince1970)
        _ = sqlite3_step(stmt)
    }

    /// Renames a Space, increments its revision, persists it to `catalog.sqlite`, and returns the updated `SpaceMetadata`.
    @discardableResult
    public func renameSpace(id: UUID, newName: String) -> SpaceMetadata {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        var space = fetchSpace(id: id) ?? SpaceMetadata(id: id, name: trimmed.isEmpty ? "Untitled Space" : trimmed)
        if !trimmed.isEmpty {
            space.name = trimmed
        }
        space.updatedAt = Date()
        space.revision += 1
        saveSpace(space)
        return space
    }

    /// Updates the storage mode (and optional sync opt-in timestamp or personal cloud provider) for a Space.
    @discardableResult
    public func updateStorageMode(
        id: UUID,
        mode: SpaceStorageMode,
        acceptedCloudSyncAt: Date? = nil,
        provider: PersonalCloudProvider? = nil
    ) -> SpaceMetadata {
        var space = fetchSpace(id: id) ?? SpaceMetadata(id: id, name: "Space", storageMode: mode)
        space.storageMode = mode
        switch mode {
        case .arcaSync:
            space.cloudSyncAcceptedAt = acceptedCloudSyncAt ?? space.cloudSyncAcceptedAt ?? Date()
            space.personalCloudProvider = nil
        case .localOnly:
            space.personalCloudProvider = nil
        case .personalCloudBackup:
            space.personalCloudProvider = provider ?? space.personalCloudProvider
        }
        space.updatedAt = Date()
        space.revision += 1
        saveSpace(space)
        return space
    }

    /// Removes the Space from `catalog.sqlite` and deletes its dedicated directory (`Spaces/<id>/`).
    public func deleteSpace(id: UUID) {
        if let db {
            let sql = "DELETE FROM spaces WHERE id = ?;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                Self.bindText(stmt, index: 1, value: id.uuidString)
                _ = sqlite3_step(stmt)
                sqlite3_finalize(stmt)
            }
        }

        let spaceDir = spaceDirectoryURL(for: id)
        if FileManager.default.fileExists(atPath: spaceDir.path) {
            try? FileManager.default.removeItem(at: spaceDir)
        }
    }

    // MARK: - Internal SQLite Helpers

    private static func executeRawSQL(on db: OpaquePointer, sql: String) {
        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if rc != SQLITE_OK, let errMsg {
            sqlite3_free(errMsg)
        }
    }

    private static func bindText(_ stmt: OpaquePointer?, index: Int32, value: String?) {
        if let value {
            value.withCString { cStr in
                _ = sqlite3_bind_text(stmt, index, cStr, -1, SQLITE_TRANSIENT_DESTRUCTOR)
            }
        } else {
            _ = sqlite3_bind_null(stmt, index)
        }
    }
}
