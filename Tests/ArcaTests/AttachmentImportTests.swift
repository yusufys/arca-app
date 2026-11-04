import XCTest
import ArcaCore
import ArcaPersistence
@testable import ArcaUI

@MainActor
final class AttachmentImportTests: XCTestCase {
    func testFilesImportCopiesActualBytesAndRejectsCloudSpace() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ArcaFiles-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let vm = ArcaAppViewModel(rootDirectoryURL: root)
        let space = SpaceMetadata(name: "Local", storageMode: .localOnly)
        await vm.catalogStore.saveSpace(space)
        let input = root.appendingPathComponent("receipt.txt")
        let content = Data("My actual receipt\nTotal: 42".utf8)
        try content.write(to: input)
        let ref = try await vm.attachFile(from: input, to: space.id)
        let store = SpaceStore(space: space, baseDirectoryURL: root)
        let copied = try await store.loadAttachmentData(for: ref)
        XCTAssertEqual(copied, content)
        XCTAssertEqual(ref.filename, "receipt.txt")
        XCTAssertEqual(ref.mimeType, "text/plain")
        try FileManager.default.removeItem(at: input)
        let retained = try await store.loadAttachmentData(for: ref)
        XCTAssertEqual(retained, content, "The imported attachment must survive removing the source file")
        let cloud = SpaceMetadata(name: "Cloud", storageMode: .arcaSync)
        await vm.catalogStore.saveSpace(cloud)
        do { _ = try await vm.attachFile(from: input, to: cloud.id); XCTFail("Cloud attachment import is not supported") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Local-Only")) }
    }

    func testDirectoryIsNotAcceptedAsAnAttachment() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ArcaFiles-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let vm = ArcaAppViewModel(rootDirectoryURL: root)
        let space = SpaceMetadata(name: "Local", storageMode: .localOnly)
        await vm.catalogStore.saveSpace(space)
        do { _ = try await vm.attachFile(from: root, to: space.id); XCTFail("Directory must not be accepted") }
        catch { XCTAssertTrue(error.localizedDescription.contains("regular file")) }
    }
}
