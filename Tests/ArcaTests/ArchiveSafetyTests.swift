import XCTest
import ArcaCore
import ArcaPersistence
import ArcaCrypto
@testable import ArcaArchive

final class ArchiveSafetyTests: XCTestCase {
    func testExplicitEmptyEncryptionPasswordNeverFallsBackToPlaintext() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ArcaArchiveSafety-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let space = SpaceMetadata(name: "Private", storageMode: .localOnly)
        let store = SpaceStore(space: space, baseDirectoryURL: root)
        let destination = root.appendingPathComponent("exports")
        for password in ["", "  \n"] {
            do {
                _ = try await ArchiveService.exportSpace(space: space, store: store,
                                                        destinationDirectory: destination, encryptionPassphrase: password)
                XCTFail("An empty encryption password must throw")
            } catch { XCTAssertEqual(error as? ArchiveError, .passphraseRequired) }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testRestoreResetsSensitiveConsentAndKeepsLocalOnlyStorage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ArcaArchiveSafety-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let space = SpaceMetadata(name: "Sensitive", storageMode: .arcaSync)
        let catalog = CatalogStore(baseDirectoryURL: root)
        await catalog.saveSpace(space)
        let store = SpaceStore(space: space, baseDirectoryURL: root)
        let field = FieldDefinition(label: "Private detail", type: .shortText, privacy: .syncWithConsent)
        let schema = CollectionSchema(spaceId: space.id, name: "Private collection", privacy: .syncWithConsent, fields: [field])
        await store.saveCollection(schema, enqueueSync: false)
        let url = try await ArchiveService.exportSpace(space: space, store: store,
                                                     destinationDirectory: root.appendingPathComponent("exports"), encryptionPassphrase: "Backup Password")
        let restored = try await ArchiveService.restoreArchiveAsNewSpace(from: url, passphrase: "Backup Password", into: catalog, spacesRootDirectory: root)
        XCTAssertEqual(restored.storageMode, .localOnly)
        let restoredStore = SpaceStore(space: restored, baseDirectoryURL: root)
        let schemas = await restoredStore.listCollections()
        XCTAssertEqual(schemas.first?.privacy, .localOnly)
        XCTAssertEqual(schemas.first?.fields.first?.privacy, .localOnly)
        do {
            _ = try await ArchiveService.exportSpace(space: restored, store: restoredStore,
                                                    destinationDirectory: root.appendingPathComponent("plain"))
            XCTFail("Local-only sensitive data requires an explicitly encrypted export")
        } catch { XCTAssertEqual(error as? ArchiveError, .passphraseRequired) }
    }

    func testTamperedEncryptedImportLeavesExistingCatalogUnchanged() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ArcaArchiveSafety-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let space = SpaceMetadata(name: "Private", storageMode: .localOnly)
        let catalog = CatalogStore(baseDirectoryURL: root)
        await catalog.saveSpace(space)
        let store = SpaceStore(space: space, baseDirectoryURL: root)
        let url = try await ArchiveService.exportSpace(space: space, store: store,
                                                     destinationDirectory: root.appendingPathComponent("exports"), encryptionPassphrase: "Strong Password")
        var data = try Data(contentsOf: url)
        data[data.count - 1] ^= 1
        try data.write(to: url)
        do {
            _ = try await ArchiveService.restoreArchiveAsNewSpace(from: url, passphrase: "Strong Password",
                                                                into: catalog, spacesRootDirectory: root)
            XCTFail("Tampered encrypted import must throw")
        } catch { XCTAssertEqual(error as? ArchiveError, .decryptionFailed) }
        let spaces = await catalog.listSpaces()
        XCTAssertEqual(spaces.map(\.id), [space.id])
    }

    func testInvalidRecordReferenceIsRejectedBeforeNewSpaceIsPublished() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ArcaArchiveSafety-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let space = SpaceMetadata(name: "Private", storageMode: .localOnly)
        let catalog = CatalogStore(baseDirectoryURL: root)
        await catalog.saveSpace(space)
        let encoder = PortableSpaceArchive.makeCanonicalEncoder()
        let collections = try encoder.encode([CollectionSchema]())
        let records = try encoder.encode([RecordItem(spaceId: space.id, collectionId: UUID(), values: [:])])
        let manifest = ArchiveManifest(spaceMetadata: space, collectionCount: 0, recordCount: 1,
                                       attachmentDigests: [:], collectionsSha256Hex: ClientCryptoEngine.sha256Hex(of: collections),
                                       recordsSha256Hex: ClientCryptoEngine.sha256Hex(of: records))
        let package = PortableSpaceArchive(manifest: manifest, collectionsJSONData: collections,
                                           recordsJSONData: records, attachmentBlobs: [:])
        let url = root.appendingPathComponent("bad.arcaarchive")
        try package.writeBundleDirectory(to: url)
        do {
            _ = try await ArchiveService.restoreArchiveAsNewSpace(from: url, into: catalog, spacesRootDirectory: root)
            XCTFail("An internally hashed but invalid record reference must be rejected")
        } catch { XCTAssertNotNil(error as? ArchiveError) }
        let spaces = await catalog.listSpaces()
        XCTAssertEqual(spaces.map(\.id), [space.id])
        let liveDirectories = root.appendingPathComponent("Spaces")
        let directories = try FileManager.default.contentsOfDirectory(atPath: liveDirectories.path)
        XCTAssertEqual(directories, [space.id.uuidString])
    }
}
