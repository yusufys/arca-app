import XCTest
import ArcaCore
@testable import ArcaUI

final class CollectionBlueprintTests: XCTestCase {
    func testBackendContractMatchesBundledRulesAndRendererTypes() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try Data(contentsOf: repo.appendingPathComponent("backend/resources/contracts/collection-v1.json"))
        let bundled = try Data(contentsOf: repo.appendingPathComponent("Sources/ArcaCore/Resources/collection-v1.json"))
        XCTAssertEqual(source, bundled)
        let fields = FieldType.allCases.map { type -> [String: Any] in
            var field: [String: Any] = ["label": type.rawValue, "type": type.rawValue]
            if type == .singleSelect || type == .multiSelect { field["options"] = ["New", "Used"] }
            return field
        }
        let schema = try CollectionBlueprint.schema(from: ["name": "All types", "fields": fields], spaceID: UUID())
        XCTAssertEqual(schema.activeFields.map(\.type), FieldType.allCases)
    }

    func testExtractOneFencedReplyPreservesQuotedBracesAndRejectsAmbiguity() throws {
        let json = #"{"name":"Books {read}","fields":[{"label":"Title \"}\"","type":"short_text"}]}"#
        let id = UUID()
        let schema = try CollectionBlueprint.schema(fromReply: "Here you go!\n```json\n" + json + "\n```\nEnjoy.", spaceID: id)
        XCTAssertEqual(schema.name, "Books {read}")
        XCTAssertEqual(schema.fields[0].label, "Title \"}\"")
        XCTAssertEqual(schema.spaceId, id)
        for bad in ["[" + json + "]", json + "\n" + json, String(json.dropLast()), "{}"] {
            XCTAssertThrowsError(try CollectionBlueprint.schema(fromReply: bad, spaceID: id))
        }
    }

    func testUnrenderableAndUnsafeRepliesFailBeforeWriting() {
        for fields in [
            #"[{"label":"X","type":"unknown"}]"#,
            #"[{"label":"X","type":"single_select"}]"#,
            #"[{"label":"X","type":"multi_select","options":["","ok"]}]"#,
            #"[{"label":"X","type":"multi_select","options":["ok","ok"]}]"#,
            #"[{"label":"X","type":"number","isPrimaryTitle":true}]"#,
            #"[{"label":"X","type":"short_text","isRequired":1}]"#,
            #"[{"label":"X","type":"short_text","isPrimaryTitle":true},{"label":"Y","type":"short_text","isPrimaryTitle":true}]"#,
            #"[{"label":"Secret","type":"short_text","privacy":"syncWithConsent"}]"#
        ] {
            XCTAssertThrowsError(try CollectionBlueprint.schema(fromReply: "{\"name\":\"Example\",\"fields\":" + fields + "}", spaceID: UUID()), fields)
        }
    }

    @MainActor
    func testNewCatalogIDCopiesToOnboardingAndPersistsIndependentlyOfCatalog() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let payload = #"{"version":1,"templates":[{"id":"camera_gear","subtitle":"My cameras","schema":{"name":"Cameras","fields":[{"label":"Model","type":"short_text"}]}}]}"#
        let templates = try CollectionCatalogClient.templates(in: Data(payload.utf8))
        let vm = ArcaAppViewModel(rootDirectoryURL: dir)
        await vm.finishOnboarding(defaultMode: .localOnly, acceptedCloudTerms: false, selectedTemplates: templates)
        let original = try XCTUnwrap(vm.collectionsInCurrentSpace.first)
        XCTAssertEqual(vm.collectionsInCurrentSpace.count, 1)
        XCTAssertEqual(original.name, "Cameras")
        try await vm.createCollectionFromTemplate(templates[0], createDedicatedLocalSpaceIfSensitive: false)
        let copy = try XCTUnwrap(vm.collectionsInCurrentSpace.first { $0.id != original.id })
        XCTAssertNotEqual(original.fields[0].id, copy.fields[0].id)
        let reply = #"{"name":"AI cameras","fields":[{"label":"Camera","type":"short_text"}]}"#
        let preview = try vm.previewAICollectionReply(reply)
        XCTAssertEqual(vm.collectionsInCurrentSpace.count, 2)
        try await vm.createAICollection(from: preview)
        let resumed = ArcaAppViewModel(rootDirectoryURL: dir)
        await resumed.bootstrapIfNeeded()
        XCTAssertEqual(Set(resumed.collectionsInCurrentSpace.map(\.id)), [original.id, copy.id, preview.id])
    }
}
