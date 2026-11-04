import XCTest
import ArcaArchive

final class ArchivePathSafetyTests: XCTestCase {
    func testNonexistentLeafWithinAliasedRootIsAllowedButEscapingSymlinkIsRejected() throws {
        let fm = FileManager.default
        let parent = fm.temporaryDirectory.appendingPathComponent("ArcaPaths-\(UUID())")
        defer { try? fm.removeItem(at: parent) }
        let root = parent.appendingPathComponent("real")
        let alias = parent.appendingPathComponent("alias")
        let outside = parent.appendingPathComponent("outside")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: alias, withDestinationURL: root)
        XCTAssertNoThrow(try ArchivePathValidator.validateRelativePath("attachments/missing.bin", withinRoot: alias))
        XCTAssertNoThrow(try ArchivePathValidator.validateRelativePath("attachments/missing.bin", withinRoot: root.appendingPathComponent("new-staging")))
        try fm.createSymbolicLink(at: root.appendingPathComponent("attachments"), withDestinationURL: outside)
        XCTAssertThrowsError(try ArchivePathValidator.validateRelativePath("attachments/missing.bin", withinRoot: root))
        for path in ["../outside", "attachments/../outside", "attachments/\nfile", " attachments/file"] {
            XCTAssertThrowsError(try ArchivePathValidator.validateRelativePath(path, withinRoot: root))
        }
    }
}
