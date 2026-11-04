import XCTest
import CryptoKit
import ArcaCore
import ArcaCrypto
import ArcaPersistence
import ArcaSync
@testable import ArcaUI

final class AccountDeletionCleanupTests: XCTestCase {
    func testVerifiedDeletionPreservesLocalRecordsAndKeysAcrossRelaunch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ArcaDeletion-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let keyStore = InMemoryKeyStore()
        let identity = try WorkspaceIdentityStore(directory: root, namespace: "deletion", keyStore: keyStore)
        let oldMaster = identity.masterAccountKey
        let oldRecovery = identity.recoveryPhrase
        try identity.bindCloudAccount(accountId: "account", bearer: "old-token", masterAccountKey: oldMaster, recoveryPhrase: oldRecovery)
        let catalog = CatalogStore(baseDirectoryURL: root)
        let space = SpaceMetadata(name: "Keep these records", storageMode: .arcaSync, cloudSyncAcceptedAt: Date())
        await catalog.saveSpace(space)
        let field = FieldDefinition(label: "Title", type: .shortText, privacy: .syncWithConsent)
        let schema = CollectionSchema(spaceId: space.id, name: "Records", privacy: .syncWithConsent, fields: [field])
        let record = RecordItem(spaceId: space.id, collectionId: schema.id, values: [field.id: .shortText("Preserved")])
        let store = SpaceStore(space: space, baseDirectoryURL: root)
        await store.saveCollection(schema, enqueueSync: false)
        try await store.saveRecord(record, schema: schema, enqueueSync: false)
        let ring = try identity.activeSpaceKeyRing(for: space.id)
        let receipt = RemoteDeletionReceipt(accountId: "account", deletedSpaceId: nil, didDeleteEntireAccount: true,
                                            purgedOperationsCount: 1, purgedAttachmentsCount: 0, purgedBytesCount: 0)
        try await AccountDeletionCleanup.apply(receipt, catalog: catalog, identity: identity)
        let savedSpace = await catalog.fetchSpace(id: space.id)
        XCTAssertEqual(savedSpace?.storageMode, .localOnly)
        XCTAssertNil(savedSpace?.cloudSyncAcceptedAt)
        let savedSchema = await store.fetchCollection(id: schema.id)
        XCTAssertEqual(savedSchema?.privacy, .localOnly)
        XCTAssertEqual(savedSchema?.fields.first?.privacy, .localOnly)
        let savedRecord = await store.fetchRecord(id: record.id)
        XCTAssertEqual(savedRecord?.values[field.id], .shortText("Preserved"))
        let relaunched = try WorkspaceIdentityStore(directory: root, namespace: "deletion", keyStore: keyStore)
        XCTAssertNil(relaunched.cloudSession)
        XCTAssertEqual(try relaunched.activeSpaceKeyRing(for: space.id), ring)
        XCTAssertNotEqual(relaunched.masterAccountKey, oldMaster)
        XCTAssertNotEqual(relaunched.recoveryPhrase, oldRecovery)
        // Receipt cleanup is safe to retry after a crash following the Keychain write.
        try await AccountDeletionCleanup.apply(receipt, catalog: catalog, identity: relaunched)
    }

    func testWrongOrUnverifiedReceiptNeverDetachesIdentityOrChangesSpace() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ArcaDeletion-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = try WorkspaceIdentityStore(directory: root, namespace: "deletion", keyStore: InMemoryKeyStore())
        try identity.bindCloudAccount(accountId: "account", bearer: "keep-token", masterAccountKey: identity.masterAccountKey, recoveryPhrase: identity.recoveryPhrase)
        let catalog = CatalogStore(baseDirectoryURL: root)
        let space = SpaceMetadata(name: "Cloud", storageMode: .arcaSync)
        await catalog.saveSpace(space)
        for (id, verified) in [("wrong", true), ("account", false)] {
            let receipt = RemoteDeletionReceipt(accountId: id, deletedSpaceId: nil, didDeleteEntireAccount: true,
                                                purgedOperationsCount: 0, purgedAttachmentsCount: 0, purgedBytesCount: 0,
                                                verifiedZeroRemainingRecords: verified)
            do { try await AccountDeletionCleanup.apply(receipt, catalog: catalog, identity: identity); XCTFail("Must reject receipt") }
            catch { }
        }
        XCTAssertEqual(identity.cloudSession?.bearer, "keep-token")
        let saved = await catalog.fetchSpace(id: space.id)
        XCTAssertEqual(saved?.storageMode, .arcaSync)
    }
}
