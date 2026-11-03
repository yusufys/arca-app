import Foundation
import SQLite3
import ArcaCore
import ArcaPersistence
import ArcaUI

@available(macOS 14.0, iOS 17.0, *)
@MainActor
func verifyInitialSyncSnapshot() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ArcaLegacySnapshot-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let bundle = SampleDataFactory.createDefaultPersonalSpace(storageMode: .localOnly)
    let catalog = CatalogStore(baseDirectoryURL: root)
    await catalog.saveSpace(bundle.space)
    let store = SpaceStore(spaceId: bundle.space.id, baseDirectoryURL: root)
    for schema in bundle.collections { await store.saveCollection(schema, enqueueSync: false) }
    for record in bundle.records {
        guard let schema = bundle.collections.first(where: { $0.id == record.collectionId }) else { continue }
        try await store.saveRecord(record, schema: schema, enqueueSync: false)
    }
    let originalQueue = await store.pendingOutboxItems()
    try check(originalQueue.isEmpty, "Legacy test starts with existing records and an empty queue")
    if let record = bundle.records.first { await store.deleteRecord(id: record.id, enqueueSync: false) }
    let liveRecords = await store.listRecords(includeDeleted: false)
    let liveSchemas = await store.listCollections(includeDeleted: false)
    try check(!liveRecords.isEmpty, "Snapshot fixture must include surviving records")
    var handle: OpaquePointer?
    guard sqlite3_open(store.databaseURL.path, &handle) == SQLITE_OK, let db = handle else { throw VerificationFailure("Cannot open snapshot fault-injection database") }
    defer { sqlite3_close(db) }
    func sql(_ statement: String) throws {
        guard sqlite3_exec(db, statement, nil, nil, nil) == SQLITE_OK else { throw VerificationFailure("Snapshot test SQL failed") }
    }
    // Orphan rows can remain in old databases. Exclude both missing and deleted schema parents.
    let orphan = UUID()
    let missingParent = UUID()
    try sql("INSERT INTO records SELECT '\(orphan.uuidString)','\(missingParent.uuidString)',schema_version,is_favorite,is_deleted,revision,updated_at,created_at,payload_json FROM records WHERE is_deleted=0 LIMIT 1;")
    let deletedParent = UUID()
    try sql("INSERT INTO collections SELECT '\(deletedParent.uuidString)',schema_version,1,updated_at,payload_json FROM collections LIMIT 1;")
    try sql("INSERT INTO records SELECT '\(UUID().uuidString)','\(deletedParent.uuidString)',schema_version,is_favorite,is_deleted,revision,updated_at,created_at,payload_json FROM records WHERE is_deleted=0 LIMIT 1;")
    try await store.enqueueInitialSyncSnapshot()
    let first = await store.pendingOutboxItems()
    try checkEqual(first.count, liveSchemas.count + liveRecords.count)
    try checkEqual(first.prefix(liveSchemas.count).map(\.entityType), Array(repeating: "collection_upsert", count: liveSchemas.count))
    try checkEqual(Set(first.filter { $0.entityType == "record_upsert" }.map(\.entityId)), Set(liveRecords.map(\.id)))
    try check(first.allSatisfy { $0.baseRevision == 0 }, "First publication must use remote revision zero")

    let attachmentId = UUID()
    try sql("INSERT INTO sync_outbox VALUES ('\(attachmentId.uuidString)','attachment_upload','\(UUID().uuidString)',0,0,3,'preserve','{}');")
    try await store.enqueueInitialSyncSnapshot()
    let second = await store.pendingOutboxItems()
    try check(Set(first.map(\.operationId)).isDisjoint(with: Set(second.map(\.operationId))), "Snapshot must use fresh operation IDs")
    let attachment = try second.first(where: { $0.operationId == attachmentId }).unwrapSnapshot("Attachment operation must remain queued")
    try checkEqual(attachment.retryCount, 3)
    try checkEqual(attachment.lastError, "preserve")
    try sql("CREATE TRIGGER snapshot_fault BEFORE INSERT ON sync_outbox WHEN NEW.entity_type='record_upsert' BEGIN SELECT RAISE(ABORT,'injected snapshot failure'); END;")
    var failed = false
    do { try await store.enqueueInitialSyncSnapshot() } catch { failed = true }
    try check(failed, "Injected SQLite failure must propagate")
    let afterFailure = await store.pendingOutboxItems()
    try checkEqual(afterFailure, second, "Failure must roll back deletions and all partially inserted schemas")
    print("[PASS] Legacy empty-outbox snapshot restores live schemas/records in order; preserves attachment queue and rolls back SQLite failures")
}

private extension Optional {
    func unwrapSnapshot(_ message: String) throws -> Wrapped {
        guard let value = self else { throw VerificationFailure(message) }
        return value
    }
}
