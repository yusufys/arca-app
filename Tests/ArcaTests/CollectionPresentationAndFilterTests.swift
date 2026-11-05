import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import ArcaCore
@testable import ArcaUI

@available(macOS 14.0, iOS 17.0, *)
final class CollectionPresentationAndFilterTests: XCTestCase {

    private var tempDirectory: URL!
    private var suiteName: String!
    private var userDefaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArcaCollectionPresTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        suiteName = "group.arca.tests.\(UUID().uuidString)"
        userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        if let suiteName {
            userDefaults?.removePersistentDomain(forName: suiteName)
        }
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try super.tearDownWithError()
    }

    // MARK: - 1. Default Preferences & Persistence Across Re-Instantiation (Force-Quit Simulation)

    @MainActor
    func testCollectionPreferencesPersistAcrossForceQuitAndDefaultToLibraryIcon() throws {
        let collectionId = UUID()
        let secondaryFieldId = UUID()
        let keyPrefix = "arca.collection.presentation.test.v1."

        let store1 = CollectionPresentationStore(
            userDefaults: userDefaults,
            keyPrefix: keyPrefix,
            imageDirectoryURL: tempDirectory
        )

        // Existing schema with no stored preferences defaults to .normal list mode, .popup add mode, and nil icon override (falls back to schema SF Symbol)
        XCTAssertEqual(store1.listMode(for: collectionId), .normal)
        XCTAssertEqual(store1.addFormMode(for: collectionId), .popup)
        XCTAssertNil(store1.preferences(for: collectionId).iconPreference)
        XCTAssertNil(store1.preferences(for: collectionId).compactSecondaryFieldId)

        // Mutate all preferences for this collection
        store1.setListMode(.box, for: collectionId)
        store1.setAddFormMode(.fullScreen, for: collectionId)
        store1.setCompactSecondaryField(secondaryFieldId, for: collectionId)
        store1.setIcon(.monogram("hi"), for: collectionId)

        // Re-instantiate store against the same UserDefaults and directory (simulating app force-quit & relaunch)
        let store2 = CollectionPresentationStore(
            userDefaults: userDefaults,
            keyPrefix: keyPrefix,
            imageDirectoryURL: tempDirectory
        )

        XCTAssertEqual(store2.listMode(for: collectionId), .box)
        XCTAssertEqual(store2.addFormMode(for: collectionId), .fullScreen)
        XCTAssertEqual(store2.preferences(for: collectionId).compactSecondaryFieldId, secondaryFieldId)
        XCTAssertEqual(store2.preferences(for: collectionId).iconPreference, .monogram("HI"))
    }

    // MARK: - 2. Malformed Preference Fallback

    @MainActor
    func testMalformedPreferencesFallBackCleanlyWithoutLosingValidEntries() throws {
        let validId = UUID()
        let partialId = UUID()
        let corruptId = UUID()
        let keyPrefix = "arca.collection.presentation.malformed.v1."

        let validJSON = """
        {
            "listMode": "compact",
            "addFormMode": "screen"
        }
        """
        let partialJSON = """
        {
            "listMode": "box",
            "addFormMode": "not-a-valid-mode",
            "compactSecondaryFieldId": "not-a-uuid",
            "iconPreference": {
                "type": "unknown_kind",
                "value": "???"
            }
        }
        """
        userDefaults.set(Data(validJSON.utf8), forKey: keyPrefix + validId.uuidString.lowercased())
        userDefaults.set(Data(partialJSON.utf8), forKey: keyPrefix + partialId.uuidString.lowercased())
        userDefaults.set(Data("<<<corrupt-json>>>".utf8), forKey: keyPrefix + corruptId.uuidString.lowercased())

        let store = CollectionPresentationStore(
            userDefaults: userDefaults,
            keyPrefix: keyPrefix,
            imageDirectoryURL: tempDirectory
        )

        XCTAssertEqual(store.listMode(for: validId), .compact)
        XCTAssertEqual(store.addFormMode(for: validId), .fullScreen)

        // Partial entry keeps valid listMode ("box") and falls back to defaults for malformed fields
        XCTAssertEqual(store.listMode(for: partialId), .box)
        XCTAssertEqual(store.addFormMode(for: partialId), .popup)
        XCTAssertNil(store.preferences(for: partialId).compactSecondaryFieldId)
        XCTAssertNil(store.preferences(for: partialId).iconPreference)

        // Totally corrupt JSON falls back to defaults without crashing
        XCTAssertEqual(store.listMode(for: corruptId), .normal)
        XCTAssertEqual(store.addFormMode(for: corruptId), .popup)
    }

    // MARK: - 3. Secondary Field Resolution & Automatic Fallback on Archive/Purge

    @MainActor
    func testSecondaryFieldResolutionFallsBackWhenSelectedFieldIsArchivedOrPurged() throws {
        let spaceId = UUID()
        var schema = StarterTemplateCatalog.vehicleMaintenance.instantiateSchema(for: spaceId)
        let store = CollectionPresentationStore(
            userDefaults: userDefaults,
            keyPrefix: "arca.collection.secondary.v1.",
            imageDirectoryURL: tempDirectory
        )

        let candidates = CollectionPresentationStore.secondaryFieldCandidates(for: schema)
        XCTAssertFalse(candidates.contains(where: { $0.id == schema.primaryTitleField?.id }))
        XCTAssertGreaterThanOrEqual(candidates.count, 2)

        // Default secondary field picks the first non-title candidate
        let defaultField = try XCTUnwrap(store.resolvedSecondaryField(for: schema))
        XCTAssertEqual(defaultField.id, candidates[0].id)

        // Select the second candidate explicitly
        let chosenField = candidates[1]
        store.setCompactSecondaryField(chosenField.id, for: schema.id)
        XCTAssertEqual(store.resolvedSecondaryField(for: schema)?.id, chosenField.id)

        // Archive the chosen field: resolvedSecondaryField must automatically fall back to an active non-title field
        let (archivedSchema, _) = SchemaEngine.removeField(
            in: schema,
            fieldId: chosenField.id,
            policy: .archiveAndRetainValues,
            records: []
        )
        let fallbackAfterArchive = try XCTUnwrap(store.resolvedSecondaryField(for: archivedSchema))
        XCTAssertNotEqual(fallbackAfterArchive.id, chosenField.id)
        XCTAssertEqual(fallbackAfterArchive.id, candidates[0].id)

        // Restore the archived field: preference recovers automatically
        let restoredSchema = SchemaEngine.restoreArchivedField(in: archivedSchema, fieldId: chosenField.id)
        XCTAssertEqual(store.resolvedSecondaryField(for: restoredSchema)?.id, chosenField.id)

        // Permanently purge the chosen field: resolvedSecondaryField falls back cleanly
        let (purgedSchema, _) = SchemaEngine.removeField(
            in: restoredSchema,
            fieldId: chosenField.id,
            policy: .permanentlyPurgeValues,
            records: []
        )
        schema = purgedSchema
        XCTAssertEqual(store.resolvedSecondaryField(for: schema)?.id, candidates[0].id)
    }

    // MARK: - 4. Bounded Custom Icon Image Persistence & Path Traversal Rejection

    @MainActor
    func testCustomIconDownsamplesAndRejectsInvalidDataAndPathTraversal() throws {
        let collectionId = UUID()
        let store = CollectionPresentationStore(
            userDefaults: userDefaults,
            keyPrefix: "arca.collection.icons.v1.",
            imageDirectoryURL: tempDirectory
        )

        // 1. Empty data is rejected
        XCTAssertThrowsError(try store.saveCustomIconImageData(Data(), for: collectionId))

        // 2. Corrupt non-image bytes are rejected
        XCTAssertThrowsError(try store.saveCustomIconImageData(Data("not an image".utf8), for: collectionId))

        // 3. Valid large image (600x400 RGBA) is downsampled to <= 256px and <= 512KB PNG
        let largePNG = try makeSolidPNGData(width: 600, height: 400)
        try store.saveCustomIconImageData(largePNG, for: collectionId)

        guard case .customImage(let filename) = store.preferences(for: collectionId).iconPreference else {
            return XCTFail("Expected customImage preference after saving valid image")
        }
        XCTAssertFalse(filename.contains("/"))
        XCTAssertFalse(filename.contains(".."))

        let savedData = try XCTUnwrap(store.customImageData(for: collectionId))
        XCTAssertLessThanOrEqual(savedData.count, CollectionPresentationStore.maxStoredIconBytes)

        let imageSource = try XCTUnwrap(CGImageSourceCreateWithData(savedData as CFData, nil))
        let cgImage = try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
        XCTAssertLessThanOrEqual(cgImage.width, CollectionPresentationStore.maxIconPixelDimension)
        XCTAssertLessThanOrEqual(cgImage.height, CollectionPresentationStore.maxIconPixelDimension)

        // 4. Switching to library icon removes the custom image file from disk
        store.setIcon(.library(symbol: "shield.lefthalf.filled"), for: collectionId)
        XCTAssertNil(store.customImageData(for: collectionId))

        // 5. Path traversal filename injected into preferences is rejected by customImageData(for:)
        store.setIcon(.customImage(filename: "../outside.png"), for: collectionId)
        XCTAssertNil(store.customImageData(for: collectionId))
    }

    // MARK: - 5. Collection Metadata Updates & Field-Based Filtering Regression

    @MainActor
    func testUpdateCollectionMetadataPersistsWithoutMutatingRecordsAndSupportsFieldFilters() async throws {
        let appDir = tempDirectory.appendingPathComponent("AppStoreData", isDirectory: true)
        let vm = ArcaAppViewModel(rootDirectoryURL: appDir, startWithCompletedOnboarding: false)
        await vm.finishOnboarding(
            defaultMode: .localOnly,
            acceptedCloudTerms: false,
            selectedTemplates: [StarterTemplateCatalog.vehicleMaintenance]
        )

        let originalSchema = try XCTUnwrap(vm.collectionsInCurrentSpace.first)
        let titleField = try XCTUnwrap(originalSchema.primaryTitleField)
        let numberField = try XCTUnwrap(originalSchema.activeFields.first(where: { $0.type == .number }))
        let dateField = try XCTUnwrap(originalSchema.activeFields.first(where: { $0.type == .date }))
        let selectField = try XCTUnwrap(originalSchema.activeFields.first(where: { $0.type == .singleSelect }))
        let firstOptionId = try XCTUnwrap(selectField.options.first?.id)
        let lastOptionId = try XCTUnwrap(selectField.options.last?.id)

        try await vm.saveRecord(
            existingRecord: nil,
            schema: originalSchema,
            values: [
                titleField.id: .shortText("15,000-Mile Inspection"),
                numberField.id: .number(15000),
                dateField.id: .date(CalendarDate(year: 2024, month: 6, day: 15)),
                selectField.id: .singleSelect(firstOptionId)
            ],
            isFavorite: false
        )
        try await vm.saveRecord(
            existingRecord: nil,
            schema: originalSchema,
            values: [
                titleField.id: .shortText("60,000-Mile Major Service"),
                numberField.id: .number(60250),
                dateField.id: .date(CalendarDate(year: 2026, month: 3, day: 10)),
                selectField.id: .singleSelect(lastOptionId)
            ],
            isFavorite: true
        )

        let originalRecords = vm.recordsInCurrentSpace.filter { $0.collectionId == originalSchema.id }
        XCTAssertEqual(originalRecords.count, 2)
        let originalFieldIds = originalSchema.fields.map(\.id)

        // Update collection name, iconName, and colorHex
        await vm.updateCollectionMetadata(
            collectionId: originalSchema.id,
            name: "Updated Garage Log",
            iconName: "car.fill",
            colorHex: "#7C3AED"
        )

        let updatedSchema = try XCTUnwrap(vm.schema(for: originalSchema.id))
        XCTAssertEqual(updatedSchema.name, "Updated Garage Log")
        XCTAssertEqual(updatedSchema.iconName, "car.fill")
        XCTAssertEqual(updatedSchema.colorHex, "#7C3AED")
        XCTAssertEqual(updatedSchema.fields.map(\.id), originalFieldIds)

        // Verify records were not mutated by metadata update
        let recordsAfterMetadataUpdate = vm.recordsInCurrentSpace.filter { $0.collectionId == originalSchema.id }
        XCTAssertEqual(recordsAfterMetadataUpdate.count, originalRecords.count)
        for original in originalRecords {
            let current = try XCTUnwrap(recordsAfterMetadataUpdate.first(where: { $0.id == original.id }))
            XCTAssertEqual(current.values, original.values)
        }

        // Reload a fresh ArcaAppViewModel against the same disk directory to verify persistence across force-quit
        let vmReloaded = ArcaAppViewModel(rootDirectoryURL: appDir, startWithCompletedOnboarding: true)
        await vmReloaded.bootstrapIfNeeded()
        let persistedSchema = try XCTUnwrap(vmReloaded.schema(for: originalSchema.id))
        XCTAssertEqual(persistedSchema.name, "Updated Garage Log")
        XCTAssertEqual(persistedSchema.iconName, "car.fill")
        XCTAssertEqual(persistedSchema.colorHex, "#7C3AED")

        // Verify field-based filters (number range, date range, favorites) on real records
        let highMileageRecords = vmReloaded.queryRecords(
            RecordQuery(
                collectionId: persistedSchema.id,
                filters: [.numberRange(fieldId: numberField.id, min: 30000, max: nil)]
            )
        )
        XCTAssertEqual(highMileageRecords.count, 1)
        XCTAssertEqual(highMileageRecords.first?.title(using: persistedSchema), "60,000-Mile Major Service")

        let cutoff = CalendarDate(year: 2025, month: 1, day: 1)
        let recentServiceRecords = vmReloaded.queryRecords(
            RecordQuery(
                collectionId: persistedSchema.id,
                filters: [.dateRange(fieldId: dateField.id, from: cutoff, to: nil), .favoritesOnly]
            )
        )
        XCTAssertEqual(recentServiceRecords.count, 1)
        XCTAssertEqual(recentServiceRecords.first?.title(using: persistedSchema), "60,000-Mile Major Service")
    }

    // MARK: - Helpers

    private func makeSolidPNGData(width: Int, height: Int) throws -> Data {
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 180, count: height * bytesPerRow)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            pixels[i] = 31      // R
            pixels[i + 1] = 93  // G
            pixels[i + 2] = 63  // B
            pixels[i + 3] = 255 // A
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let cgImage = context.makeImage() else {
            throw NSError(domain: "TestImageError", code: 1)
        }
        let output = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            output as CFMutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw NSError(domain: "TestImageError", code: 2)
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "TestImageError", code: 3)
        }
        return output as Data
    }
}
