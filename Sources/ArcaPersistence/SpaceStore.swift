import Foundation
import SQLite3
import ArcaCore
import ArcaCrypto

// MARK: - Outbox Models

/// Identifies the operation/entity type recorded in `sync_outbox`.
public enum OutboxEntityType: String, Codable, Sendable, Equatable, Hashable {
    case collectionUpsert = "collection_upsert"
    case collectionTombstone = "collection_tombstone"
    case recordUpsert = "record_upsert"
    case recordTombstone = "record_tombstone"
    case attachmentUpload = "attachment_upload"
}

/// Durable operation log entry stored in `sync_outbox` inside the same ACID transaction as local mutations.
public struct OutboxRecord: Identifiable, Codable, Sendable, Equatable, Hashable {
    public var id: UUID { operationId }
    public let operationId: UUID
    public let entityType: String
    public let entityId: UUID
    public let baseRevision: Int64
    public let createdAt: Date
    public var retryCount: Int
    public var lastError: String?
    public let payloadJSON: String

    public init(
        operationId: UUID = UUID(),
        entityType: String,
        entityId: UUID,
        baseRevision: Int64,
        createdAt: Date = Date(),
        retryCount: Int = 0,
        lastError: String? = nil,
        payloadJSON: String
    ) {
        self.operationId = operationId
        self.entityType = entityType
        self.entityId = entityId
        self.baseRevision = baseRevision
        self.createdAt = createdAt
        self.retryCount = retryCount
        self.lastError = lastError
        self.payloadJSON = payloadJSON
    }

    public var parsedEntityType: OutboxEntityType? {
        OutboxEntityType(rawValue: entityType)
    }
}

// MARK: - SpaceStore Actor

/// Manages an individual Space's isolated SQLite database (`Spaces/<spaceId>/space.sqlite`)
/// and local attachment directory (`Spaces/<spaceId>/Attachments/`).
public actor SpaceStore {
    public nonisolated let spaceId: UUID
    public nonisolated let baseDirectoryURL: URL
    public nonisolated let spaceDirectoryURL: URL
    public nonisolated let databaseURL: URL
    public nonisolated let attachmentsDirectoryURL: URL

    private var db: OpaquePointer?
    private var isFTS5Available: Bool = false
    private let isSensitiveLocal: Bool
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        spaceId: UUID,
        baseDirectoryURL: URL = CatalogStore.defaultBaseDirectoryURL(),
        isSensitiveLocal: Bool = false
    ) {
        self.spaceId = spaceId
        self.baseDirectoryURL = baseDirectoryURL
        let spaceDir = baseDirectoryURL
            .appendingPathComponent("Spaces", isDirectory: true)
            .appendingPathComponent(spaceId.uuidString, isDirectory: true)
        self.spaceDirectoryURL = spaceDir
        self.databaseURL = spaceDir.appendingPathComponent("space.sqlite", isDirectory: false)
        self.attachmentsDirectoryURL = spaceDir.appendingPathComponent("Attachments", isDirectory: true)
        self.isSensitiveLocal = isSensitiveLocal

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.sortedKeys]
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec

        try? FileManager.default.createDirectory(at: spaceDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: attachmentsDirectoryURL, withIntermediateDirectories: true)

        DataProtectionConfigurator.applyProtection(
            at: spaceDir,
            isSensitiveLocalOnly: isSensitiveLocal,
            excludeFromUnencryptedBackup: isSensitiveLocal
        )
        DataProtectionConfigurator.applyProtection(
            at: attachmentsDirectoryURL,
            isSensitiveLocalOnly: isSensitiveLocal,
            excludeFromUnencryptedBackup: isSensitiveLocal
        )

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(databaseURL.path, &handle, flags, nil) == SQLITE_OK, let opened = handle {
            self.db = opened
            sqlite3_busy_timeout(opened, 5_000)
            Self.executeRawSQL(on: opened, sql: "PRAGMA foreign_keys = ON;")
            Self.executeRawSQL(on: opened, sql: "PRAGMA journal_mode = WAL;")
            Self.initializeSchema(on: opened, ftsAvailable: &self.isFTS5Available)
            DataProtectionConfigurator.applyProtection(
                at: databaseURL,
                isSensitiveLocalOnly: isSensitiveLocal,
                excludeFromUnencryptedBackup: isSensitiveLocal
            )
        }
    }

    public init(space: SpaceMetadata, baseDirectoryURL: URL = CatalogStore.defaultBaseDirectoryURL()) {
        let sensitive = (space.storageMode == .localOnly) || space.containsSensitiveHealthTemplate
        self.init(spaceId: space.id, baseDirectoryURL: baseDirectoryURL, isSensitiveLocal: sensitive)
    }

    deinit {
        if let db {
            sqlite3_close_v2(db)
        }
    }

    private static func initializeSchema(on db: OpaquePointer, ftsAvailable: inout Bool) {
        let coreDDL = """
        CREATE TABLE IF NOT EXISTS collections (
            id TEXT PRIMARY KEY,
            schema_version INTEGER NOT NULL,
            is_deleted INTEGER NOT NULL DEFAULT 0,
            updated_at REAL NOT NULL,
            payload_json TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS records (
            id TEXT PRIMARY KEY,
            collection_id TEXT NOT NULL,
            schema_version INTEGER NOT NULL,
            is_favorite INTEGER NOT NULL DEFAULT 0,
            is_deleted INTEGER NOT NULL DEFAULT 0,
            revision INTEGER NOT NULL DEFAULT 1,
            updated_at REAL NOT NULL,
            created_at REAL NOT NULL,
            payload_json TEXT NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_records_collection_deleted
            ON records (collection_id, is_deleted, updated_at DESC);

        CREATE TABLE IF NOT EXISTS record_field_projections (
            record_id TEXT NOT NULL,
            collection_id TEXT NOT NULL,
            field_id TEXT NOT NULL,
            text_val TEXT,
            num_val REAL,
            date_val TEXT,
            bool_val INTEGER,
            PRIMARY KEY (record_id, field_id)
        );

        CREATE INDEX IF NOT EXISTS idx_projections_num
            ON record_field_projections (collection_id, field_id, num_val);

        CREATE INDEX IF NOT EXISTS idx_projections_date
            ON record_field_projections (collection_id, field_id, date_val);

        CREATE INDEX IF NOT EXISTS idx_projections_text
            ON record_field_projections (collection_id, field_id, text_val);

        CREATE TABLE IF NOT EXISTS sync_conflicts (account_id TEXT NOT NULL, record_id TEXT NOT NULL, payload_json TEXT NOT NULL, PRIMARY KEY(account_id, record_id));

        CREATE TABLE IF NOT EXISTS sync_cursors (account_id TEXT PRIMARY KEY, sequence_number INTEGER NOT NULL);

        CREATE TABLE IF NOT EXISTS sync_outbox (
            operation_id TEXT PRIMARY KEY,
            entity_type TEXT NOT NULL,
            entity_id TEXT NOT NULL,
            base_revision INTEGER NOT NULL,
            created_at REAL NOT NULL,
            retry_count INTEGER NOT NULL DEFAULT 0,
            last_error TEXT,
            payload_json TEXT NOT NULL
        );
        """
        executeRawSQL(on: db, sql: coreDDL)

        let ftsDDL = """
        CREATE VIRTUAL TABLE IF NOT EXISTS records_fts USING fts5(
            record_id UNINDEXED,
            collection_id UNINDEXED,
            searchable_text
        );
        """
        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, ftsDDL, nil, nil, &errMsg)
        if rc == SQLITE_OK {
            ftsAvailable = true
        } else {
            if let errMsg { sqlite3_free(errMsg) }
            ftsAvailable = false
        }
    }

    // MARK: - Collections CRUD

    /// Lists all `CollectionSchema` definitions in this Space.
    public func listCollections(includeDeleted: Bool = false) -> [CollectionSchema] {
        guard let db else { return [] }
        let sql: String
        if includeDeleted {
            sql = "SELECT payload_json FROM collections ORDER BY updated_at ASC, id ASC;"
        } else {
            sql = "SELECT payload_json FROM collections WHERE is_deleted = 0 ORDER BY updated_at ASC, id ASC;"
        }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }

        var schemas: [CollectionSchema] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let jsonString = Self.columnText(stmt, index: 0),
                  let data = jsonString.data(using: .utf8),
                  let schema = try? decoder.decode(CollectionSchema.self, from: data) else {
                continue
            }
            if includeDeleted || !schema.isDeleted {
                schemas.append(schema)
            }
        }
        return schemas
    }

    /// Fetches a single `CollectionSchema` by ID.
    public func fetchCollection(id: UUID) -> CollectionSchema? {
        guard let db else { return nil }
        let sql = "SELECT payload_json FROM collections WHERE id = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        Self.bindText(stmt, index: 1, value: id.uuidString)
        guard sqlite3_step(stmt) == SQLITE_ROW,
              let jsonString = Self.columnText(stmt, index: 0),
              let data = jsonString.data(using: .utf8) else {
            return nil
        }
        return try? decoder.decode(CollectionSchema.self, from: data)
    }

    /// Inserts or updates a `CollectionSchema`, optionally recording an outbox item in the same transaction.
    public func saveCollection(_ schema: CollectionSchema, enqueueSync: Bool = true) {
        guard let db else { return }
        guard let payloadData = try? encoder.encode(schema),
              let payloadJSON = String(data: payloadData, encoding: .utf8) else {
            return
        }

        let existing = fetchCollection(id: schema.id)
        let baseRevision = existing?.revision ?? max(0, schema.revision - 1)

        Self.executeRawSQL(on: db, sql: "BEGIN IMMEDIATE TRANSACTION;")
        let upsertSQL = """
        INSERT INTO collections (id, schema_version, is_deleted, updated_at, payload_json)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            schema_version = excluded.schema_version,
            is_deleted = excluded.is_deleted,
            updated_at = excluded.updated_at,
            payload_json = excluded.payload_json;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, upsertSQL, -1, &stmt, nil) == SQLITE_OK {
            Self.bindText(stmt, index: 1, value: schema.id.uuidString)
            sqlite3_bind_int(stmt, 2, Int32(schema.schemaVersion))
            sqlite3_bind_int(stmt, 3, schema.isDeleted ? 1 : 0)
            sqlite3_bind_double(stmt, 4, schema.updatedAt.timeIntervalSince1970)
            Self.bindText(stmt, index: 5, value: payloadJSON)
            _ = sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }

        if enqueueSync {
            let entityType: OutboxEntityType = schema.isDeleted ? .collectionTombstone : .collectionUpsert
            insertOutboxItemInternal(
                on: db,
                entityType: entityType.rawValue,
                entityId: schema.id,
                baseRevision: baseRevision,
                payloadJSON: payloadJSON
            )
        }
        Self.executeRawSQL(on: db, sql: "COMMIT;")
    }

    /// Commits remote schemas before the sync cursor can advance.
    public func applyRemoteCollection(_ schema: CollectionSchema) throws {
        guard schema.spaceId == spaceId, let db else { throw PersistenceError.databaseOpenFailed("Space database unavailable.") }
        let payload = try encoder.encode(schema)
        guard let json = String(data: payload, encoding: .utf8) else { throw PersistenceError.encodingFailed }
        try executeSQLStrict("BEGIN IMMEDIATE TRANSACTION;")
        do {
            let sql = "INSERT INTO collections (id,schema_version,is_deleted,updated_at,payload_json) VALUES (?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET schema_version=excluded.schema_version,is_deleted=excluded.is_deleted,updated_at=excluded.updated_at,payload_json=excluded.payload_json;"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw PersistenceError.statementPreparationFailed("Remote schema write failed.") }
            defer { sqlite3_finalize(statement) }
            Self.bindText(statement, index: 1, value: schema.id.uuidString)
            sqlite3_bind_int(statement, 2, Int32(schema.schemaVersion)); sqlite3_bind_int(statement, 3, schema.isDeleted ? 1 : 0)
            sqlite3_bind_double(statement, 4, schema.updatedAt.timeIntervalSince1970); Self.bindText(statement, index: 5, value: json)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw PersistenceError.sqlExecutionFailed("Remote schema write failed.") }
            try executeSQLStrict("COMMIT;")
        } catch { Self.executeRawSQL(on: db, sql: "ROLLBACK;"); throw error }
    }

    public func saveSyncConflictPayload(_ payload: Data, recordId: UUID, accountId: String) throws {
        guard let db, let json = String(data: payload, encoding: .utf8) else { throw PersistenceError.encodingFailed }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO sync_conflicts(account_id,record_id,payload_json) VALUES (?,?,?) ON CONFLICT(account_id,record_id) DO UPDATE SET payload_json=excluded.payload_json;", -1, &statement, nil) == SQLITE_OK else { throw PersistenceError.statementPreparationFailed("Conflict preservation failed.") }
        defer { sqlite3_finalize(statement) }
        Self.bindText(statement, index: 1, value: accountId.lowercased()); Self.bindText(statement, index: 2, value: recordId.uuidString); Self.bindText(statement, index: 3, value: json)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw PersistenceError.sqlExecutionFailed("Conflict preservation failed.") }
    }

    public func syncConflictPayloads(accountId: String) throws -> [Data] {
        guard let db else { throw PersistenceError.databaseOpenFailed("Space database unavailable.") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT payload_json FROM sync_conflicts WHERE account_id=?;", -1, &statement, nil) == SQLITE_OK else { throw PersistenceError.statementPreparationFailed("Conflict read failed.") }
        defer { sqlite3_finalize(statement) }
        Self.bindText(statement, index: 1, value: accountId.lowercased())
        var results: [Data] = []
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            guard let json = Self.columnText(statement, index: 0) else { throw PersistenceError.decodingFailed }
            results.append(Data(json.utf8)); status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { throw PersistenceError.sqlExecutionFailed("Conflict read failed.") }
        return results
    }

    public func removeSyncConflict(recordId: UUID, accountId: String) throws {
        guard let db else { throw PersistenceError.databaseOpenFailed("Space database unavailable.") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM sync_conflicts WHERE account_id=? AND record_id=?;", -1, &statement, nil) == SQLITE_OK else { throw PersistenceError.statementPreparationFailed("Conflict removal failed.") }
        defer { sqlite3_finalize(statement) }
        Self.bindText(statement, index: 1, value: accountId.lowercased()); Self.bindText(statement, index: 2, value: recordId.uuidString)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw PersistenceError.sqlExecutionFailed("Conflict removal failed.") }
    }

    public func syncCursorSequence(accountId: String) throws -> Int64 {
        guard let db else { throw PersistenceError.databaseOpenFailed("Space database unavailable.") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT sequence_number FROM sync_cursors WHERE account_id=?;", -1, &statement, nil) == SQLITE_OK else { throw PersistenceError.statementPreparationFailed("Sync cursor read failed.") }
        defer { sqlite3_finalize(statement) }
        Self.bindText(statement, index: 1, value: accountId.lowercased())
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return 0 }
        guard result == SQLITE_ROW else { throw PersistenceError.sqlExecutionFailed("Sync cursor read failed.") }
        return sqlite3_column_int64(statement, 0)
    }

    public func saveSyncCursorSequence(_ sequence: Int64, accountId: String) throws {
        guard let db else { throw PersistenceError.databaseOpenFailed("Space database unavailable.") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO sync_cursors(account_id,sequence_number) VALUES (?,?) ON CONFLICT(account_id) DO UPDATE SET sequence_number=excluded.sequence_number;", -1, &statement, nil) == SQLITE_OK else { throw PersistenceError.statementPreparationFailed("Sync cursor write failed.") }
        defer { sqlite3_finalize(statement) }
        Self.bindText(statement, index: 1, value: accountId.lowercased()); sqlite3_bind_int64(statement, 2, sequence)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw PersistenceError.sqlExecutionFailed("Sync cursor write failed.") }
    }

    private func executeSQLStrict(_ sql: String) throws {
        guard let db else { throw PersistenceError.databaseOpenFailed("Space database unavailable.") }
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw PersistenceError.sqlExecutionFailed("Sync transaction failed.") }
    }

    /// Marks a collection as deleted (tombstone) and soft-deletes its records.
    public func deleteCollection(id: UUID, enqueueSync: Bool = true) {
        guard let db else { return }
        guard var schema = fetchCollection(id: id) else { return }
        let baseRevision = schema.revision
        schema.isDeleted = true
        schema.revision += 1
        schema.updatedAt = Date()

        guard let payloadData = try? encoder.encode(schema),
              let payloadJSON = String(data: payloadData, encoding: .utf8) else {
            return
        }

        Self.executeRawSQL(on: db, sql: "BEGIN IMMEDIATE TRANSACTION;")
        let sql = """
        UPDATE collections
        SET is_deleted = 1, schema_version = ?, updated_at = ?, payload_json = ?
        WHERE id = ?;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, Int32(schema.schemaVersion))
            sqlite3_bind_double(stmt, 2, schema.updatedAt.timeIntervalSince1970)
            Self.bindText(stmt, index: 3, value: payloadJSON)
            Self.bindText(stmt, index: 4, value: id.uuidString)
            _ = sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }

        if enqueueSync {
            insertOutboxItemInternal(
                on: db,
                entityType: OutboxEntityType.collectionTombstone.rawValue,
                entityId: id,
                baseRevision: baseRevision,
                payloadJSON: payloadJSON
            )
        }
        Self.executeRawSQL(on: db, sql: "COMMIT;")
    }

    // MARK: - Records CRUD & Indexing

    /// Validates `record` via `SchemaEngine.validate`, writes to `records`, updates `record_field_projections`
    /// and `records_fts`, and appends to `sync_outbox` atomically inside a single SQLite transaction.
    public func saveRecord(
        _ record: RecordItem,
        schema: CollectionSchema,
        enqueueSync: Bool = true
    ) throws {
        guard let db else {
            throw PersistenceError.databaseOpenFailed("Space database is not open.")
        }

        if !record.isDeleted {
            let validationErrors = SchemaEngine.validate(values: record.values, against: schema)
            if !validationErrors.isEmpty {
                throw PersistenceError.recordValidationFailed(validationErrors)
            }
        }

        let existing = fetchRecord(id: record.id)
        let baseRevision = existing?.revision ?? max(0, record.revision - 1)

        guard let payloadData = try? encoder.encode(record),
              let payloadJSON = String(data: payloadData, encoding: .utf8) else {
            throw PersistenceError.encodingFailed
        }

        try executeSQLStrict("BEGIN IMMEDIATE TRANSACTION;")
        do {
            try writeRecordRowInternal(on: db, record: record, payloadJSON: payloadJSON)
            updateProjectionsInternal(on: db, record: record, schema: schema)
            updateFTSIndexInternal(on: db, record: record, schema: schema)

            if enqueueSync {
                let entityType: OutboxEntityType = record.isDeleted ? .recordTombstone : .recordUpsert
                insertOutboxItemInternal(
                    on: db,
                    entityType: entityType.rawValue,
                    entityId: record.id,
                    baseRevision: baseRevision,
                    payloadJSON: payloadJSON
                )
            }
            try executeSQLStrict("COMMIT;")
        } catch {
            Self.executeRawSQL(on: db, sql: "ROLLBACK;")
            throw error
        }
    }

    /// Fetches a single `RecordItem` by ID (including tombstoned records if present).
    public func fetchRecord(id: UUID) -> RecordItem? {
        guard let db else { return nil }
        let sql = "SELECT payload_json FROM records WHERE id = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        Self.bindText(stmt, index: 1, value: id.uuidString)
        guard sqlite3_step(stmt) == SQLITE_ROW,
              let jsonString = Self.columnText(stmt, index: 0),
              let data = jsonString.data(using: .utf8) else {
            return nil
        }
        return try? decoder.decode(RecordItem.self, from: data)
    }

    /// Lists records in this Space, optionally scoped to a specific `collectionId` and optionally including deleted tombstones.
    public func listRecords(collectionId: UUID? = nil, includeDeleted: Bool = false) -> [RecordItem] {
        guard let db else { return [] }
        var clauses: [String] = []
        if collectionId != nil {
            clauses.append("collection_id = ?")
        }
        if !includeDeleted {
            clauses.append("is_deleted = 0")
        }
        let whereClause = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")
        let sql = "SELECT payload_json FROM records \(whereClause) ORDER BY updated_at DESC, id ASC;"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }

        if let collectionId {
            Self.bindText(stmt, index: 1, value: collectionId.uuidString)
        }

        var items: [RecordItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let jsonString = Self.columnText(stmt, index: 0),
                  let data = jsonString.data(using: .utf8),
                  let item = try? decoder.decode(RecordItem.self, from: data) else {
                continue
            }
            if includeDeleted || !item.isDeleted {
                items.append(item)
            }
        }
        return items
    }

    /// Creates a deletion tombstone for `id` (`is_deleted = 1`, increments `revision`, clears projections & FTS, and appends outbox tombstone).
    public func deleteRecord(id: UUID, enqueueSync: Bool = true) {
        guard let db else { return }
        guard var record = fetchRecord(id: id) else { return }
        let baseRevision = record.revision
        record.isDeleted = true
        record.revision += 1
        record.updatedAt = Date()

        guard let payloadData = try? encoder.encode(record),
              let payloadJSON = String(data: payloadData, encoding: .utf8) else {
            return
        }

        Self.executeRawSQL(on: db, sql: "BEGIN IMMEDIATE TRANSACTION;")
        try? writeRecordRowInternal(on: db, record: record, payloadJSON: payloadJSON)
        clearProjectionsAndFTSInternal(on: db, recordId: id)

        if enqueueSync {
            insertOutboxItemInternal(
                on: db,
                entityType: OutboxEntityType.recordTombstone.rawValue,
                entityId: id,
                baseRevision: baseRevision,
                payloadJSON: payloadJSON
            )
        }
        Self.executeRawSQL(on: db, sql: "COMMIT;")
    }

    // MARK: - Full-Text Search, Filter & Sort Query Engine

    /// Executes a `RecordQuery` across the Space using `records_fts` (with graceful `LIKE` fallback),
    /// `record_field_projections` index pushdowns, and deterministic sorting.
    public func queryRecords(
        _ query: RecordQuery,
        schemas: [UUID: CollectionSchema]
    ) -> [RecordItem] {
        guard let db else { return [] }

        // Step 1: Obtain candidate records scoped by collectionId & favorites SQL pushdown
        var sqlClauses: [String] = ["r.is_deleted = 0"]
        var bindStrings: [String] = []

        if let colId = query.collectionId {
            sqlClauses.append("r.collection_id = ?")
            bindStrings.append(colId.uuidString)
        }

        if query.filters.contains(.favoritesOnly) {
            sqlClauses.append("r.is_favorite = 1")
        }

        // Step 2: If searchText is non-empty, compute matching record IDs via FTS5 (with LIKE fallback)
        let trimmedSearch = query.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var ftsMatchedIds: Set<UUID>?
        if !trimmedSearch.isEmpty {
            ftsMatchedIds = matchingRecordIDsForSearchText(trimmedSearch, collectionId: query.collectionId, on: db)
            if let ftsMatchedIds, ftsMatchedIds.isEmpty {
                return []
            }
        }

        // Step 3: Push down numeric/date/rating/boolean filters via `record_field_projections` SQL subqueries
        let sql = "SELECT r.payload_json FROM records r WHERE " + sqlClauses.joined(separator: " AND ") + ";"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }

        for (idx, val) in bindStrings.enumerated() {
            Self.bindText(stmt, index: Int32(idx + 1), value: val)
        }

        var candidates: [RecordItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let jsonString = Self.columnText(stmt, index: 0),
                  let data = jsonString.data(using: .utf8),
                  let record = try? decoder.decode(RecordItem.self, from: data),
                  !record.isDeleted else {
                continue
            }
            if let ftsMatchedIds, !ftsMatchedIds.contains(record.id) {
                continue
            }
            if matchesAllFilters(record: record, filters: query.filters, schemas: schemas, on: db) {
                candidates.append(record)
            }
        }

        // Step 4: Sort candidates according to `query.sort`
        return sortRecords(candidates, by: query.sort, schemas: schemas)
    }

    // MARK: - Local Attachment Storage & Integrity Verification

    /// Computes the SHA-256 digest via `ClientCryptoEngine.sha256Hex`, writes the attachment bytes
    /// to `Spaces/<spaceId>/Attachments/<uuid>_<sanitizedName>`, and returns an `AttachmentReference`.
    public func storeAttachment(
        data: Data,
        filename: String,
        mimeType: String
    ) throws -> AttachmentReference {
        let attachmentId = UUID()
        let sanitizedName = Self.sanitizeAttachmentFilename(filename)
        let storedFileName = "\(attachmentId.uuidString)_\(sanitizedName)"
        let relativePath = "Attachments/\(storedFileName)"
        let destinationURL = spaceDirectoryURL.appendingPathComponent(relativePath, isDirectory: false)

        try? FileManager.default.createDirectory(at: attachmentsDirectoryURL, withIntermediateDirectories: true)

        do {
            try data.write(to: destinationURL, options: [.atomic])
        } catch {
            throw PersistenceError.ioError("Could not write attachment to local storage.")
        }

        DataProtectionConfigurator.applyProtection(
            at: destinationURL,
            isSensitiveLocalOnly: isSensitiveLocal,
            excludeFromUnencryptedBackup: isSensitiveLocal
        )

        let digest = ClientCryptoEngine.sha256Hex(of: data)
        return AttachmentReference(
            id: attachmentId,
            filename: filename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? sanitizedName : filename,
            mimeType: mimeType,
            byteSize: Int64(data.count),
            sha256Hex: digest,
            localRelativePath: relativePath,
            uploadState: .localOnly,
            createdAt: Date()
        )
    }

    /// Loads an attachment's raw bytes from `Spaces/<spaceId>/Attachments/...` and verifies its SHA-256 checksum on read.
    public func loadAttachmentData(for reference: AttachmentReference) throws -> Data {
        let cleanRelative = reference.localRelativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !cleanRelative.contains("..") else {
            throw PersistenceError.attachmentNotFound(reference.localRelativePath)
        }

        let fileURL = spaceDirectoryURL.appendingPathComponent(cleanRelative, isDirectory: false)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw PersistenceError.attachmentNotFound(reference.localRelativePath)
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw PersistenceError.ioError("Failed to read attachment data from disk.")
        }

        let actualDigest = ClientCryptoEngine.sha256Hex(of: data)
        let expectedDigest = reference.sha256Hex.lowercased()
        guard actualDigest == expectedDigest else {
            throw PersistenceError.attachmentIntegrityMismatch(
                expected: expectedDigest,
                actual: actualDigest
            )
        }

        return data
    }

    // MARK: - Outbox Accessors for ArcaSync

    /// Rebuilds the first publication snapshot from live local data, including legacy Spaces whose queue was drained.
    /// Schema operations precede records; attachment and future queue types remain unchanged.
    public func enqueueInitialSyncSnapshot() throws {
        guard let db else { throw PersistenceError.databaseOpenFailed("Space database unavailable.") }
        try executeSQLStrict("BEGIN IMMEDIATE TRANSACTION;")
        do {
            var snapshot: [(type: String, id: UUID, json: String)] = []
            for (table, type) in [("collections", OutboxEntityType.collectionUpsert), ("records", OutboxEntityType.recordUpsert)] {
                var statement: OpaquePointer?
                let sql = table == "records"
                    ? "SELECT r.payload_json FROM records r INNER JOIN collections c ON c.id = r.collection_id WHERE r.is_deleted = 0 AND c.is_deleted = 0 ORDER BY r.id ASC;"
                    : "SELECT payload_json FROM collections WHERE is_deleted = 0 ORDER BY id ASC;"
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                    throw PersistenceError.statementPreparationFailed("Initial sync snapshot read failed.")
                }
                defer { sqlite3_finalize(statement) }
                var result = sqlite3_step(statement)
                while result == SQLITE_ROW {
                    guard let json = Self.columnText(statement, index: 0), let data = json.data(using: .utf8) else {
                        throw PersistenceError.decodingFailed
                    }
                    let id: UUID
                    if type == .collectionUpsert {
                        let schema = try decoder.decode(CollectionSchema.self, from: data)
                        guard schema.spaceId == spaceId, !schema.isDeleted else { throw PersistenceError.decodingFailed }
                        id = schema.id
                    } else {
                        let record = try decoder.decode(RecordItem.self, from: data)
                        guard record.spaceId == spaceId, !record.isDeleted else { throw PersistenceError.decodingFailed }
                        id = record.id
                    }
                    snapshot.append((type.rawValue, id, json))
                    result = sqlite3_step(statement)
                }
                guard result == SQLITE_DONE else { throw PersistenceError.sqlExecutionFailed("Initial sync snapshot read failed.") }
            }
            try executeSQLStrict("DELETE FROM sync_outbox WHERE entity_type IN ('collection_upsert','collection_tombstone','record_upsert','record_tombstone');")
            var statement: OpaquePointer?
            let sql = "INSERT INTO sync_outbox(operation_id,entity_type,entity_id,base_revision,created_at,retry_count,last_error,payload_json) VALUES(?,?,?,0,?,0,NULL,?);"
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw PersistenceError.statementPreparationFailed("Initial sync snapshot write failed.")
            }
            defer { sqlite3_finalize(statement) }
            let createdAt = Date().timeIntervalSince1970
            for (index, item) in snapshot.enumerated() {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                Self.bindText(statement, index: 1, value: UUID().uuidString)
                Self.bindText(statement, index: 2, value: item.type)
                Self.bindText(statement, index: 3, value: item.id.uuidString)
                // A first publication has no remote base, even when local revisions have advanced.
                sqlite3_bind_double(statement, 4, createdAt + Double(index) * 0.000001)
                Self.bindText(statement, index: 5, value: item.json)
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw PersistenceError.sqlExecutionFailed("Initial sync snapshot write failed.")
                }
            }
            try executeSQLStrict("COMMIT;")
        } catch {
            Self.executeRawSQL(on: db, sql: "ROLLBACK;")
            throw error
        }
    }

    /// Returns all pending `OutboxRecord` items ordered chronologically by creation time.
    public func pendingOutboxItems() -> [OutboxRecord] {
        guard let db else { return [] }
        let sql = """
        SELECT operation_id, entity_type, entity_id, base_revision, created_at, retry_count, last_error, payload_json
        FROM sync_outbox
        ORDER BY created_at ASC, operation_id ASC;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }

        var items: [OutboxRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let opIdStr = Self.columnText(stmt, index: 0),
                  let opId = UUID(uuidString: opIdStr),
                  let entityType = Self.columnText(stmt, index: 1),
                  let entityIdStr = Self.columnText(stmt, index: 2),
                  let entityId = UUID(uuidString: entityIdStr),
                  let payloadJSON = Self.columnText(stmt, index: 7) else {
                continue
            }
            let baseRev = sqlite3_column_int64(stmt, 3)
            let createdAtTimestamp = sqlite3_column_double(stmt, 4)
            let retryCount = Int(sqlite3_column_int(stmt, 5))
            let lastError = Self.columnText(stmt, index: 6)

            items.append(OutboxRecord(
                operationId: opId,
                entityType: entityType,
                entityId: entityId,
                baseRevision: baseRev,
                createdAt: Date(timeIntervalSince1970: createdAtTimestamp),
                retryCount: retryCount,
                lastError: lastError,
                payloadJSON: payloadJSON
            ))
        }
        return items
    }

    /// Commits acknowledgements for one uploaded batch. A failed transaction preserves the entire batch for retry.
    public func acknowledgeOutboxOperations(_ operationIds: [UUID]) throws {
        guard let db else {
            throw PersistenceError.databaseOpenFailed("Space database unavailable.")
        }
        guard !operationIds.isEmpty else { return }
        try executeSQLStrict("BEGIN IMMEDIATE TRANSACTION;")
        do {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, "DELETE FROM sync_outbox WHERE operation_id = ?;", -1, &statement, nil) == SQLITE_OK else {
                throw PersistenceError.statementPreparationFailed("Sync acknowledgement failed.")
            }
            defer { sqlite3_finalize(statement) }
            for operationId in operationIds {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                Self.bindText(statement, index: 1, value: operationId.uuidString)
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw PersistenceError.sqlExecutionFailed("Sync acknowledgement failed.")
                }
            }
            try executeSQLStrict("COMMIT;")
        } catch {
            Self.executeRawSQL(on: db, sql: "ROLLBACK;")
            throw error
        }
    }

    /// Removes a completed operation from `sync_outbox`.
    public func removeOutboxItem(operationId: UUID) {
        guard let db else { return }
        let sql = "DELETE FROM sync_outbox WHERE operation_id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(stmt) }

        Self.bindText(stmt, index: 1, value: operationId.uuidString)
        _ = sqlite3_step(stmt)
    }

    /// Increments `retry_count` and records `last_error` for a failed sync outbox operation.
    public func markOutboxFailure(operationId: UUID, error: String) {
        guard let db else { return }
        let sql = """
        UPDATE sync_outbox
        SET retry_count = retry_count + 1, last_error = ?
        WHERE operation_id = ?;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(stmt) }

        Self.bindText(stmt, index: 1, value: error)
        Self.bindText(stmt, index: 2, value: operationId.uuidString)
        _ = sqlite3_step(stmt)
    }

    // MARK: - Internal SQL & Indexing Helpers

    private func writeRecordRowInternal(
        on db: OpaquePointer,
        record: RecordItem,
        payloadJSON: String
    ) throws {
        let sql = """
        INSERT INTO records (
            id, collection_id, schema_version, is_favorite, is_deleted,
            revision, updated_at, created_at, payload_json
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            collection_id = excluded.collection_id,
            schema_version = excluded.schema_version,
            is_favorite = excluded.is_favorite,
            is_deleted = excluded.is_deleted,
            revision = excluded.revision,
            updated_at = excluded.updated_at,
            created_at = excluded.created_at,
            payload_json = excluded.payload_json;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw PersistenceError.statementPreparationFailed("Failed to prepare record upsert statement.")
        }
        defer { sqlite3_finalize(stmt) }

        Self.bindText(stmt, index: 1, value: record.id.uuidString)
        Self.bindText(stmt, index: 2, value: record.collectionId.uuidString)
        sqlite3_bind_int(stmt, 3, Int32(record.schemaVersionAtWrite))
        sqlite3_bind_int(stmt, 4, record.isFavorite ? 1 : 0)
        sqlite3_bind_int(stmt, 5, record.isDeleted ? 1 : 0)
        sqlite3_bind_int64(stmt, 6, record.revision)
        sqlite3_bind_double(stmt, 7, record.updatedAt.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 8, record.createdAt.timeIntervalSince1970)
        Self.bindText(stmt, index: 9, value: payloadJSON)

        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE else {
            throw PersistenceError.sqlExecutionFailed("Failed to execute record upsert (\(rc)).")
        }
    }

    private func clearProjectionsAndFTSInternal(on db: OpaquePointer, recordId: UUID) {
        let idStr = recordId.uuidString
        let delProjSQL = "DELETE FROM record_field_projections WHERE record_id = ?;"
        var projStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, delProjSQL, -1, &projStmt, nil) == SQLITE_OK {
            Self.bindText(projStmt, index: 1, value: idStr)
            _ = sqlite3_step(projStmt)
            sqlite3_finalize(projStmt)
        }

        if isFTS5Available {
            let delFTSSQL = "DELETE FROM records_fts WHERE record_id = ?;"
            var ftsStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, delFTSSQL, -1, &ftsStmt, nil) == SQLITE_OK {
                Self.bindText(ftsStmt, index: 1, value: idStr)
                _ = sqlite3_step(ftsStmt)
                sqlite3_finalize(ftsStmt)
            }
        }
    }

    private func updateProjectionsInternal(
        on db: OpaquePointer,
        record: RecordItem,
        schema: CollectionSchema
    ) {
        let delSQL = "DELETE FROM record_field_projections WHERE record_id = ?;"
        var delStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, delSQL, -1, &delStmt, nil) == SQLITE_OK {
            Self.bindText(delStmt, index: 1, value: record.id.uuidString)
            _ = sqlite3_step(delStmt)
            sqlite3_finalize(delStmt)
        }

        guard !record.isDeleted else { return }

        let insSQL = """
        INSERT INTO record_field_projections (
            record_id, collection_id, field_id, text_val, num_val, date_val, bool_val
        ) VALUES (?, ?, ?, ?, ?, ?, ?);
        """
        var insStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insSQL, -1, &insStmt, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(insStmt) }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for (fieldId, value) in record.values {
            guard !value.isNullOrEmpty else { continue }

            var textVal: String?
            var numVal: Double?
            var dateVal: String?
            var boolVal: Int32?

            switch value {
            case .null:
                continue
            case .shortText(let s), .longText(let s):
                textVal = s
            case .number(let n):
                numVal = n
                textVal = String(n)
            case .currency(let money):
                numVal = money.doubleApproximationForChartsOnly
                textVal = money.currencyCode
            case .date(let calDate):
                dateVal = calDate.isoString
                textVal = calDate.isoString
            case .dateTime(let dt):
                let iso = isoFormatter.string(from: dt)
                dateVal = CalendarDate(date: dt).isoString
                textVal = iso
                numVal = dt.timeIntervalSince1970
            case .boolean(let b):
                boolVal = b ? 1 : 0
                textVal = b ? "true" : "false"
            case .singleSelect(let optId):
                textVal = optId
            case .multiSelect(let optIds):
                textVal = "|" + optIds.joined(separator: "|") + "|"
            case .rating(let stars):
                numVal = Double(stars)
            case .attachments(let refs):
                numVal = Double(refs.count)
                textVal = refs.map(\.filename).joined(separator: " ")
            }

            sqlite3_reset(insStmt)
            sqlite3_clear_bindings(insStmt)

            Self.bindText(insStmt, index: 1, value: record.id.uuidString)
            Self.bindText(insStmt, index: 2, value: record.collectionId.uuidString)
            Self.bindText(insStmt, index: 3, value: fieldId.uuidString)
            Self.bindText(insStmt, index: 4, value: textVal)

            if let numVal {
                sqlite3_bind_double(insStmt, 5, numVal)
            } else {
                sqlite3_bind_null(insStmt, 5)
            }

            Self.bindText(insStmt, index: 6, value: dateVal)

            if let boolVal {
                sqlite3_bind_int(insStmt, 7, boolVal)
            } else {
                sqlite3_bind_null(insStmt, 7)
            }

            _ = sqlite3_step(insStmt)
        }
    }

    private func updateFTSIndexInternal(
        on db: OpaquePointer,
        record: RecordItem,
        schema: CollectionSchema
    ) {
        guard isFTS5Available else { return }

        let delSQL = "DELETE FROM records_fts WHERE record_id = ?;"
        var delStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, delSQL, -1, &delStmt, nil) == SQLITE_OK {
            Self.bindText(delStmt, index: 1, value: record.id.uuidString)
            _ = sqlite3_step(delStmt)
            sqlite3_finalize(delStmt)
        }

        guard !record.isDeleted else { return }

        let searchableText = Self.buildSearchableText(for: record, schema: schema)
        let insSQL = "INSERT INTO records_fts (record_id, collection_id, searchable_text) VALUES (?, ?, ?);"
        var insStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, insSQL, -1, &insStmt, nil) == SQLITE_OK {
            Self.bindText(insStmt, index: 1, value: record.id.uuidString)
            Self.bindText(insStmt, index: 2, value: record.collectionId.uuidString)
            Self.bindText(insStmt, index: 3, value: searchableText)
            _ = sqlite3_step(insStmt)
            sqlite3_finalize(insStmt)
        }
    }

    private static func buildSearchableText(for record: RecordItem, schema: CollectionSchema) -> String {
        var tokens: [String] = [schema.name]
        let fieldsById = Dictionary(uniqueKeysWithValues: schema.fields.map { ($0.id, $0) })

        for (fieldId, value) in record.values {
            guard !value.isNullOrEmpty else { continue }
            let fieldDef = fieldsById[fieldId]
            let summary = value.plainTextSummary(for: fieldDef)
            if !summary.isEmpty {
                tokens.append(summary)
            }
            switch value {
            case .singleSelect(let optId):
                tokens.append(optId)
            case .multiSelect(let optIds):
                tokens.append(contentsOf: optIds)
            case .date(let calDate):
                tokens.append(calDate.isoString)
            case .currency(let money):
                tokens.append("\(money.decimalValue)")
                tokens.append(money.currencyCode)
            case .attachments(let refs):
                for ref in refs {
                    tokens.append(ref.filename)
                }
            default:
                break
            }
        }
        return tokens.joined(separator: " ")
    }

    private func insertOutboxItemInternal(
        on db: OpaquePointer,
        entityType: String,
        entityId: UUID,
        baseRevision: Int64,
        payloadJSON: String
    ) {
        let sql = """
        INSERT INTO sync_outbox (
            operation_id, entity_type, entity_id, base_revision, created_at, retry_count, last_error, payload_json
        ) VALUES (?, ?, ?, ?, ?, 0, NULL, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(stmt) }

        Self.bindText(stmt, index: 1, value: UUID().uuidString)
        Self.bindText(stmt, index: 2, value: entityType)
        Self.bindText(stmt, index: 3, value: entityId.uuidString)
        sqlite3_bind_int64(stmt, 4, baseRevision)
        sqlite3_bind_double(stmt, 5, Date().timeIntervalSince1970)
        Self.bindText(stmt, index: 6, value: payloadJSON)
        _ = sqlite3_step(stmt)
    }

    // MARK: - Search & Filter Evaluation

    private func matchingRecordIDsForSearchText(
        _ rawSearchText: String,
        collectionId: UUID?,
        on db: OpaquePointer
    ) -> Set<UUID> {
        var matched = Set<UUID>()

        if isFTS5Available {
            let ftsQuery = Self.buildSafeFTS5MatchExpression(from: rawSearchText)
            if !ftsQuery.isEmpty {
                let sql: String
                if collectionId != nil {
                    sql = "SELECT record_id FROM records_fts WHERE records_fts MATCH ? AND collection_id = ?;"
                } else {
                    sql = "SELECT record_id FROM records_fts WHERE records_fts MATCH ?;"
                }
                var stmt: OpaquePointer?
                if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                    Self.bindText(stmt, index: 1, value: ftsQuery)
                    if let collectionId {
                        Self.bindText(stmt, index: 2, value: collectionId.uuidString)
                    }
                    while sqlite3_step(stmt) == SQLITE_ROW {
                        if let idStr = Self.columnText(stmt, index: 0),
                           let uuid = UUID(uuidString: idStr) {
                            matched.insert(uuid)
                        }
                    }
                    sqlite3_finalize(stmt)
                }
            }

            // Substring fallback on `records_fts.searchable_text` when mid-word substring is searched
            if matched.isEmpty {
                let likePattern = "%\(rawSearchText)%"
                let likeSQL: String
                if collectionId != nil {
                    likeSQL = "SELECT record_id FROM records_fts WHERE searchable_text LIKE ? AND collection_id = ?;"
                } else {
                    likeSQL = "SELECT record_id FROM records_fts WHERE searchable_text LIKE ?;"
                }
                var stmt: OpaquePointer?
                if sqlite3_prepare_v2(db, likeSQL, -1, &stmt, nil) == SQLITE_OK {
                    Self.bindText(stmt, index: 1, value: likePattern)
                    if let collectionId {
                        Self.bindText(stmt, index: 2, value: collectionId.uuidString)
                    }
                    while sqlite3_step(stmt) == SQLITE_ROW {
                        if let idStr = Self.columnText(stmt, index: 0),
                           let uuid = UUID(uuidString: idStr) {
                            matched.insert(uuid)
                        }
                    }
                    sqlite3_finalize(stmt)
                }
            }
        } else {
            // Graceful fallback to LIKE on `records.payload_json` when FTS5 is unavailable
            let likePattern = "%\(rawSearchText)%"
            let likeSQL: String
            if collectionId != nil {
                likeSQL = "SELECT id FROM records WHERE is_deleted = 0 AND payload_json LIKE ? AND collection_id = ?;"
            } else {
                likeSQL = "SELECT id FROM records WHERE is_deleted = 0 AND payload_json LIKE ?;"
            }
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, likeSQL, -1, &stmt, nil) == SQLITE_OK {
                Self.bindText(stmt, index: 1, value: likePattern)
                if let collectionId {
                    Self.bindText(stmt, index: 2, value: collectionId.uuidString)
                }
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let idStr = Self.columnText(stmt, index: 0),
                       let uuid = UUID(uuidString: idStr) {
                        matched.insert(uuid)
                    }
                }
                sqlite3_finalize(stmt)
            }
        }

        return matched
    }

    private static func buildSafeFTS5MatchExpression(from rawQuery: String) -> String {
        let components = rawQuery
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.replacingOccurrences(of: "\"", with: "") }
            .filter { !$0.isEmpty }
        guard !components.isEmpty else { return "" }
        return components.map { "\"\($0)\"*" }.joined(separator: " AND ")
    }

    private func matchesAllFilters(
        record: RecordItem,
        filters: [RecordFieldFilter],
        schemas: [UUID: CollectionSchema],
        on db: OpaquePointer
    ) -> Bool {
        let schema = schemas[record.collectionId]
        for filter in filters {
            switch filter {
            case .favoritesOnly:
                if !record.isFavorite { return false }

            case .booleanEquals(let fieldId, let expected):
                if !projectionMatchesBoolean(recordId: record.id, fieldId: fieldId, expected: expected, on: db) {
                    if case .boolean(let actual) = record.values[fieldId], actual == expected {
                        continue
                    }
                    return false
                }

            case .selectContains(let fieldId, let optionId):
                let targetLower = optionId.lowercased()
                let fieldDef = schema?.fields.first(where: { $0.id == fieldId })
                let matchingOptionIds: Set<String> = {
                    var set: Set<String> = [optionId]
                    if let opts = fieldDef?.options {
                        for opt in opts where opt.id.lowercased() == targetLower || opt.label.lowercased() == targetLower {
                            set.insert(opt.id)
                            set.insert(opt.label)
                        }
                    }
                    return set
                }()

                guard let val = record.values[fieldId] else { return false }
                switch val {
                case .singleSelect(let stored):
                    if !matchingOptionIds.contains(stored) && stored.lowercased() != targetLower {
                        return false
                    }
                case .multiSelect(let storedArr):
                    let intersects = storedArr.contains { item in
                        matchingOptionIds.contains(item) || item.lowercased() == targetLower
                    }
                    if !intersects { return false }
                default:
                    return false
                }

            case .numberRange(let fieldId, let minVal, let maxVal):
                if !projectionMatchesNumberRange(recordId: record.id, fieldId: fieldId, min: minVal, max: maxVal, on: db) {
                    return false
                }

            case .dateRange(let fieldId, let fromDate, let toDate):
                if !projectionMatchesDateRange(recordId: record.id, fieldId: fieldId, from: fromDate, to: toDate, on: db) {
                    return false
                }

            case .minimumRating(let fieldId, let minStars):
                if !projectionMatchesNumberRange(recordId: record.id, fieldId: fieldId, min: Double(minStars), max: nil, on: db) {
                    return false
                }

            case .hasAttachments:
                if record.allAttachments.isEmpty {
                    return false
                }
            }
        }
        return true
    }

    private func projectionMatchesBoolean(
        recordId: UUID,
        fieldId: UUID,
        expected: Bool,
        on db: OpaquePointer
    ) -> Bool {
        let sql = """
        SELECT 1 FROM record_field_projections
        WHERE record_id = ? AND field_id = ? AND bool_val = ?
        LIMIT 1;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(stmt) }

        Self.bindText(stmt, index: 1, value: recordId.uuidString)
        Self.bindText(stmt, index: 2, value: fieldId.uuidString)
        sqlite3_bind_int(stmt, 3, expected ? 1 : 0)
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    private func projectionMatchesNumberRange(
        recordId: UUID,
        fieldId: UUID,
        min: Double?,
        max: Double?,
        on db: OpaquePointer
    ) -> Bool {
        var sql = "SELECT num_val FROM record_field_projections WHERE record_id = ? AND field_id = ? AND num_val IS NOT NULL"
        if min != nil { sql += " AND num_val >= ?" }
        if max != nil { sql += " AND num_val <= ?" }
        sql += " LIMIT 1;"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(stmt) }

        Self.bindText(stmt, index: 1, value: recordId.uuidString)
        Self.bindText(stmt, index: 2, value: fieldId.uuidString)
        var bindIdx: Int32 = 3
        if let min {
            sqlite3_bind_double(stmt, bindIdx, min)
            bindIdx += 1
        }
        if let max {
            sqlite3_bind_double(stmt, bindIdx, max)
        }
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    private func projectionMatchesDateRange(
        recordId: UUID,
        fieldId: UUID,
        from: CalendarDate?,
        to: CalendarDate?,
        on db: OpaquePointer
    ) -> Bool {
        var sql = "SELECT date_val FROM record_field_projections WHERE record_id = ? AND field_id = ? AND date_val IS NOT NULL"
        if from != nil { sql += " AND date_val >= ?" }
        if to != nil { sql += " AND date_val <= ?" }
        sql += " LIMIT 1;"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(stmt) }

        Self.bindText(stmt, index: 1, value: recordId.uuidString)
        Self.bindText(stmt, index: 2, value: fieldId.uuidString)
        var bindIdx: Int32 = 3
        if let from {
            Self.bindText(stmt, index: bindIdx, value: from.isoString)
            bindIdx += 1
        }
        if let to {
            Self.bindText(stmt, index: bindIdx, value: to.isoString)
        }
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    // MARK: - Sorting

    private func sortRecords(
        _ records: [RecordItem],
        by criterion: RecordSortCriterion,
        schemas: [UUID: CollectionSchema]
    ) -> [RecordItem] {
        switch criterion {
        case .updatedAtDescending:
            return records.sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.id.uuidString < $1.id.uuidString
            }
        case .updatedAtAscending:
            return records.sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt < $1.updatedAt }
                return $0.id.uuidString < $1.id.uuidString
            }
        case .createdAtDescending:
            return records.sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
        case .titleAscending:
            return records.sorted { lhs, rhs in
                let lhsTitle = Self.resolveRecordTitle(lhs, schemas: schemas)
                let rhsTitle = Self.resolveRecordTitle(rhs, schemas: schemas)
                let cmp = lhsTitle.localizedStandardCompare(rhsTitle)
                if cmp != .orderedSame { return cmp == .orderedAscending }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        case .titleDescending:
            return records.sorted { lhs, rhs in
                let lhsTitle = Self.resolveRecordTitle(lhs, schemas: schemas)
                let rhsTitle = Self.resolveRecordTitle(rhs, schemas: schemas)
                let cmp = lhsTitle.localizedStandardCompare(rhsTitle)
                if cmp != .orderedSame { return cmp == .orderedDescending }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        case .fieldAscending(let fieldId):
            return records.sorted { lhs, rhs in
                Self.compareFieldValues(
                    lhs.values[fieldId] ?? .null,
                    rhs.values[fieldId] ?? .null,
                    ascending: true,
                    lhsId: lhs.id,
                    rhsId: rhs.id
                )
            }
        case .fieldDescending(let fieldId):
            return records.sorted { lhs, rhs in
                Self.compareFieldValues(
                    lhs.values[fieldId] ?? .null,
                    rhs.values[fieldId] ?? .null,
                    ascending: false,
                    lhsId: lhs.id,
                    rhsId: rhs.id
                )
            }
        }
    }

    private static func resolveRecordTitle(_ record: RecordItem, schemas: [UUID: CollectionSchema]) -> String {
        if let schema = schemas[record.collectionId] {
            return record.title(using: schema)
        }
        for (_, val) in record.values {
            if case .shortText(let text) = val, !text.isEmpty {
                return text
            }
        }
        return "Untitled Record"
    }

    private static func compareFieldValues(
        _ lhs: FieldValue,
        _ rhs: FieldValue,
        ascending: Bool,
        lhsId: UUID,
        rhsId: UUID
    ) -> Bool {
        let lhsEmpty = lhs.isNullOrEmpty
        let rhsEmpty = rhs.isNullOrEmpty
        if lhsEmpty && rhsEmpty {
            return lhsId.uuidString < rhsId.uuidString
        }
        // Always place null/empty values at the end regardless of sort direction
        if lhsEmpty { return false }
        if rhsEmpty { return true }

        switch (lhs, rhs) {
        case (.number(let a), .number(let b)):
            if a != b { return ascending ? (a < b) : (a > b) }
        case (.currency(let a), .currency(let b)):
            let da = a.doubleApproximationForChartsOnly
            let db = b.doubleApproximationForChartsOnly
            if da != db { return ascending ? (da < db) : (da > db) }
        case (.rating(let a), .rating(let b)):
            if a != b { return ascending ? (a < b) : (a > b) }
        case (.date(let a), .date(let b)):
            if a != b { return ascending ? (a < b) : (b < a) }
        case (.dateTime(let a), .dateTime(let b)):
            if a != b { return ascending ? (a < b) : (a > b) }
        case (.boolean(let a), .boolean(let b)):
            if a != b {
                let intA = a ? 1 : 0
                let intB = b ? 1 : 0
                return ascending ? (intA < intB) : (intA > intB)
            }
        default:
            let strA = lhs.plainTextSummary()
            let strB = rhs.plainTextSummary()
            let cmp = strA.localizedStandardCompare(strB)
            if cmp != .orderedSame {
                return ascending ? (cmp == .orderedAscending) : (cmp == .orderedDescending)
            }
        }
        return lhsId.uuidString < rhsId.uuidString
    }

    // MARK: - Low-Level SQLite & Filename Sanitization Helpers

    private static func sanitizeAttachmentFilename(_ filename: String) -> String {
        let baseName = URL(fileURLWithPath: filename).lastPathComponent
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let cleanedScalars = baseName.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let cleaned = String(cleanedScalars).trimmingCharacters(in: CharacterSet(charactersIn: "._"))
        return cleaned.isEmpty ? "attachment.bin" : cleaned
    }

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

    private static func columnText(_ stmt: OpaquePointer?, index: Int32) -> String? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL,
              let cStr = sqlite3_column_text(stmt, index) else {
            return nil
        }
        return String(cString: cStr)
    }
}
