import XCTest
import Foundation
import ImageIO
import UniformTypeIdentifiers
import ArcaCore
import ArcaCrypto
import ArcaPersistence
import ArcaSync
@testable import ArcaUI

final class RecordImageTests: XCTestCase {
    func testImageImportBoundsDimensionsAndRemovesLocationMetadata() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 3200, height: 1600, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.8, green: 0.3, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 3200, height: 1600))
        let image = try XCTUnwrap(context.makeImage())
        let original = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(original, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 41.0,
            kCGImagePropertyGPSLongitude: 29.0]] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let prepared = try RecordImageCodec.prepare(original as Data)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(prepared as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth as String] as? Int, 2048)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight as String] as? Int, 1024)
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary as String])
        XCTAssertLessThanOrEqual(prepared.count, 5 * 1024 * 1024)
        XCTAssertThrowsError(try RecordImageCodec.prepare(Data("not a photo".utf8)))
        XCTAssertThrowsError(try RecordImageCodec.prepare(Data(repeating: 0, count: 15 * 1024 * 1024 + 1)))
    }

    func testMultipleImageFieldsValidateAndThumbnailSelectionSurvivesSchemaEdits() throws {
        let first = FieldDefinition(label: "Cover", type: .image)
        let second = FieldDefinition(label: "Ingredients", type: .image)
        var schema = CollectionSchema(spaceId: UUID(), name: "Recipes", fields: [first, second])
        XCTAssertEqual(schema.imageFields.count, 2)
        XCTAssertNil(schema.thumbnailField(preferredId: nil))
        XCTAssertEqual(schema.thumbnailField(preferredId: second.id)?.id, second.id)
        schema.fields[1].isArchived = true
        XCTAssertEqual(schema.thumbnailField(preferredId: second.id)?.id, first.id)
        let ref = AttachmentReference(filename: "image.jpg", mimeType: "image/jpeg", byteSize: 10,
            sha256Hex: "digest", localRelativePath: "Attachments/image.jpg")
        schema.fields[1].isArchived = false
        XCTAssertTrue(SchemaEngine.validate(values: [first.id: .attachments([ref]), second.id: .attachments([ref])], against: schema).isEmpty)
        XCTAssertFalse(SchemaEngine.validate(values: [first.id: .attachments([ref, ref])], against: schema).isEmpty)
        var wrong = ref; wrong.mimeType = "application/pdf"
        XCTAssertFalse(SchemaEngine.validate(values: [first.id: .attachments([wrong])], against: schema).isEmpty)
        let decoded = try JSONDecoder().decode(CollectionSchema.self, from: JSONEncoder().encode(schema))
        XCTAssertEqual(decoded.imageFields.count, 2)
    }

    func testTwoClientsReceiveEncryptedImagesAndReopenedStoreRetainsBytes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let backend = InMemoryArcaSyncBackend()
        let space = UUID(), key = SpaceKeyRing(spaceId: space)
        let a = SyncCoordinator(accountId: "images", deviceIdentity: DeviceIdentity(deviceName: "A"), backend: backend)
        let b = SyncCoordinator(accountId: "images", deviceIdentity: DeviceIdentity(deviceName: "B"), backend: backend)
        _ = try await a.enrollCurrentDevice(); _ = try await b.enrollCurrentDevice()
        await a.registerSpaceKeyRing(key); await b.registerSpaceKeyRing(key)
        let sa = SpaceStore(spaceId: space, baseDirectoryURL: root.appendingPathComponent("A"))
        let sb = SpaceStore(spaceId: space, baseDirectoryURL: root.appendingPathComponent("B"))
        let cover = FieldDefinition(label: "Cover", type: .image)
        let other = FieldDefinition(label: "Ingredients", type: .image)
        let secret = FieldDefinition(label: "Private photo", type: .image, privacy: .localOnly)
        let schema = CollectionSchema(spaceId: space, name: "Recipes", fields: [cover, other, secret])
        try await sa.saveCollectionStrict(schema)
        let bytes = Data("private photo payload".utf8)
        let ref = try await sa.storeAttachment(data: bytes, filename: "image.jpg", mimeType: "image/jpeg")
        let second = try await sa.storeAttachment(data: Data("second photo".utf8), filename: "image.jpg", mimeType: "image/jpeg")
        let hidden = try await sa.storeAttachment(data: Data("not for cloud".utf8), filename: "secret.jpg", mimeType: "image/jpeg")
        let record = RecordItem(spaceId: space, collectionId: schema.id,
            values: [cover.id: .attachments([ref]), other.id: .attachments([second]), secret.id: .attachments([hidden])])
        try await sa.saveRecord(record, schema: schema)
        _ = try await a.synchronizeSpaceStore(sa)
        _ = try await b.synchronizeSpaceStore(sb)
        let loaded = try await sb.loadAttachmentData(for: ref)
        XCTAssertEqual(loaded, bytes)
        let received = await sb.fetchRecord(id: record.id)
        XCTAssertNil(received?.values[secret.id])
        let reopened = SpaceStore(spaceId: space, baseDirectoryURL: root.appendingPathComponent("B"))
        let retained = try await reopened.loadAttachmentData(for: second)
        XCTAssertEqual(retained, Data("second photo".utf8))
        let retainedRecord = await reopened.fetchRecord(id: record.id)
        if case .attachments(let restored) = retainedRecord?.values[cover.id] {
            XCTAssertEqual(restored.first?.id, ref.id)
            XCTAssertEqual(restored.first?.sha256Hex, ref.sha256Hex)
        } else { XCTFail("Image reference did not survive reopening") }
        // Retry must not break another device's already authenticated reference.
        _ = try await a.synchronizeSpaceStore(sa)
        let blob = try EncryptedAttachmentBlob.encryptAttachment(reference: ref, collectionId: schema.id,
            rawData: bytes, spaceId: space, recordId: record.id, authorDeviceId: "test", spaceKeyRing: key)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(blob), as: UTF8.self).contains("private photo payload"))
        XCTAssertEqual(try blob.decryptAndVerify(using: key).data, bytes)
        XCTAssertThrowsError(try blob.decryptAndVerify(using: SpaceKeyRing(spaceId: space)))
        var traversal = ref; traversal.localRelativePath = "Attachments/../../outside"
        do { try await sb.restoreAttachment(data: bytes, reference: traversal); XCTFail("Unsafe path accepted") } catch { }
        do { try await sb.restoreAttachment(data: Data("tampered".utf8), reference: ref); XCTFail("Tampering accepted") } catch { }
    }

    @MainActor
    func testImagesRoundTripOverLaravelHTTPAndPrivacyPurge() async throws {
        guard let raw = ProcessInfo.processInfo.environment["ARCA_INTEGRATION_API_URL"], let url = URL(string: raw) else {
            throw XCTSkip("Requires isolated Laravel HTTP server")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let ba = LaravelArcaSyncBackend(baseURL: url, apiToken: nil)
        let bb = LaravelArcaSyncBackend(baseURL: url, apiToken: nil)
        let email = "images-\(UUID())@example.test", password = "image-integration-password"
        let session = try await ba.signIn(email: email, password: password, name: "Image integration")
        addTeardownBlock { _ = try await ba.deleteAccountAndRemoteData(accountId: session.accountId) }
        _ = try await bb.signIn(email: email, password: password)
        let da = DeviceIdentity(deviceName: "Image A"), db = DeviceIdentity(deviceName: "Image B")
        let a = SyncCoordinator(accountId: session.accountId, deviceIdentity: da, backend: ba)
        let b = SyncCoordinator(accountId: session.accountId, deviceIdentity: db, backend: bb)
        _ = try await a.enrollCurrentDevice(); _ = try await b.enrollCurrentDevice()
        let space = UUID(), ring = SpaceKeyRing(spaceId: space)
        await a.registerSpaceKeyRing(ring); await b.registerSpaceKeyRing(ring)
        try await ba.publishWrappedSpaceKey(accountId: session.accountId, deviceId: da.deviceId,
            wrappedSpaceKey: ring.wrap(usingMasterAccountKey: ClientCryptoEngine.generateSymmetricKey(), makKeyId: UUID()))
        let sa = SpaceStore(spaceId: space, baseDirectoryURL: root.appendingPathComponent("A"))
        let sb = SpaceStore(spaceId: space, baseDirectoryURL: root.appendingPathComponent("B"))
        let cover = FieldDefinition(label: "Cover", type: .image)
        let detail = FieldDefinition(label: "Detail", type: .image)
        var schema = CollectionSchema(spaceId: space, name: "Recipes", fields: [cover, detail])
        try await sa.saveCollectionStrict(schema)
        let bytes = Data(repeating: 42, count: 128_000)
        let ref = try await sa.storeAttachment(data: bytes, filename: "image.jpg", mimeType: "image/jpeg")
        let ref2 = try await sa.storeAttachment(data: Data("second image".utf8), filename: "image.jpg", mimeType: "image/jpeg")
        let record = RecordItem(spaceId: space, collectionId: schema.id, values: [cover.id: .attachments([ref]), detail.id: .attachments([ref2])])
        try await sa.saveRecord(record, schema: schema)
        _ = try await a.synchronizeSpaceStore(sa); _ = try await b.synchronizeSpaceStore(sb)
        let loaded = try await sb.loadAttachmentData(for: ref)
        XCTAssertEqual(loaded, bytes)
        let blob = try await bb.downloadEncryptedAttachment(accountId: session.accountId, spaceId: space, attachmentId: ref.id, deviceId: db.deviceId)
        XCTAssertEqual(try blob.decryptAndVerify(using: ring).data, bytes)
        // A reopened client reads existing bytes without downloading or changing its keys.
        let reopened = SpaceStore(spaceId: space, baseDirectoryURL: root.appendingPathComponent("B"))
        let retained = try await reopened.loadAttachmentData(for: ref2)
        XCTAssertEqual(retained, Data("second image".utf8))
        schema.fields[0].privacy = .localOnly; schema.revision += 1
        try await sa.saveCollectionStrict(schema)
        _ = try await a.synchronizeSpaceStore(sa)
        let pending = try await sa.pendingPrivacyRules()
        XCTAssertTrue(pending.isEmpty)
        do {
            _ = try await bb.downloadEncryptedAttachment(accountId: session.accountId, spaceId: space, attachmentId: ref.id, deviceId: db.deviceId)
            XCTFail("Private image remains on the server")
        } catch let error as NSError { XCTAssertEqual(error.code, 404) }
        _ = try await b.synchronizeSpaceStore(sb)
        let remaining = try await bb.downloadEncryptedAttachment(accountId: session.accountId, spaceId: space, attachmentId: ref2.id, deviceId: db.deviceId)
        XCTAssertEqual(try remaining.decryptAndVerify(using: ring).data, Data("second image".utf8))
    }

    @MainActor
    func testThumbnailPreferencePersistsAndDoesNotChangeOtherViewSettings() throws {
        let suite = "image-tests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let collectionId = UUID(), fieldId = UUID()
        let store = CollectionPresentationStore(userDefaults: defaults)
        store.setListMode(.box, for: collectionId)
        store.setAddFormMode(.fullScreen, for: collectionId)
        store.setThumbnailField(fieldId, for: collectionId)
        let reopened = CollectionPresentationStore(userDefaults: defaults).preferences(for: collectionId)
        XCTAssertEqual(reopened.thumbnailFieldId, fieldId)
        XCTAssertEqual(reopened.listMode, .box)
        XCTAssertEqual(reopened.addFormMode, .fullScreen)
        // Preferences remain backward compatible with build 7.
        let old = Data(#"{"listMode":"box","addFormMode":"screen"}"#.utf8)
        var preferences = try JSONDecoder().decode(CollectionPresentationPreferences.self, from: old)
        XCTAssertNil(preferences.thumbnailFieldId)
        preferences.thumbnailFieldId = UUID()
        let result = try JSONDecoder().decode(CollectionPresentationPreferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(result.thumbnailFieldId, preferences.thumbnailFieldId)
        XCTAssertEqual(result.listMode, .box)
        XCTAssertEqual(result.addFormMode, .fullScreen)
    }
}
