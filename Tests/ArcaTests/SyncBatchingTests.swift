import XCTest
import Foundation
import ArcaCore
import ArcaCrypto
import ArcaPersistence
import ArcaSync

final class SyncBatchingTests: XCTestCase {
    func testPagedPullCompletesBeforeBatchedPushAndRetryKeepsOnlyUnacknowledgedIds() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let spaceId = UUID()
        let device = DeviceIdentity(deviceName: "Batch test")
        let ring = SpaceKeyRing(spaceId: spaceId)
        let field = FieldDefinition(label: "Title", type: .shortText)
        let schema = CollectionSchema(spaceId: spaceId, name: "Encrypted schema", fields: [field])
        let store = SpaceStore(spaceId: spaceId, baseDirectoryURL: directory)
        await store.saveCollection(schema)

        var localRecords: [RecordItem] = []
        for index in 0..<502 {
            let record = RecordItem(spaceId: spaceId, collectionId: schema.id,
                                    values: [field.id: .shortText("Local \(index)")],
                                    lastModifiedByDeviceId: device.deviceId)
            try await store.saveRecord(record, schema: schema)
            localRecords.append(record)
        }
        var remoteOperations = [try EncryptedSyncOperation.encryptSchemaOperation(
            schema: schema, baseRevision: 0, authorDeviceId: "other-device", spaceKeyRing: ring
        )]
        for index in 0..<500 {
            let remote = RecordItem(spaceId: spaceId, collectionId: schema.id,
                                    values: [field.id: .shortText("Remote \(index)")])
            remoteOperations.append(try EncryptedSyncOperation.encryptRecordOperation(
                record: remote, baseRevision: 0, authorDeviceId: "other-device", spaceKeyRing: ring
            ))
        }
        // The conflict is on the second incoming page. Publishing after only page one would leak a conflicting write.
        var conflicting = localRecords[0]
        conflicting.values[field.id] = .shortText("Concurrent remote edit")
        conflicting.revision = 2
        remoteOperations.append(try EncryptedSyncOperation.encryptRecordOperation(
            record: conflicting, baseRevision: 0, authorDeviceId: "other-device", spaceKeyRing: ring
        ))
        let fixture = SyncBatchFixture(spaceId: spaceId, operations: remoteOperations)
        SyncBatchURLProtocol.fixture = fixture
        defer { SyncBatchURLProtocol.fixture = nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SyncBatchURLProtocol.self]
        let backend = LaravelArcaSyncBackend(baseURL: URL(string: "https://sync.test")!,
                                            apiToken: "test-token", session: URLSession(configuration: configuration))
        let coordinator = SyncCoordinator(accountId: "batch-account", deviceIdentity: device, backend: backend)
        await coordinator.registerSpaceKeyRing(ring)
        do {
            _ = try await coordinator.synchronizeSpaceStore(store)
            XCTFail("The second upload response must fail")
        } catch {
            XCTAssertEqual((error as NSError).code, 503)
        }
        XCTAssertEqual(fixture.pushSizes, [500, 2])
        XCTAssertEqual(fixture.events.prefix(3), ["pull:500", "pull:2", "push:500"])
        let localConflictIds = await coordinator.activeConflicts(for: spaceId).map(\.recordId)
        XCTAssertEqual(localConflictIds, [conflicting.id])
        XCTAssertFalse(fixture.pushedEntityIds.contains(conflicting.id))

        let restartedStore = SpaceStore(spaceId: spaceId, baseDirectoryURL: directory)
        let pending = await restartedStore.pendingOutboxItems()
        XCTAssertEqual(pending.count, 2)
        let retryIds = Set(pending.map(\.operationId))
        XCTAssertEqual(retryIds, Set(fixture.pushIds[1]))
        // Prior failures must never cause a durable operation to fall out of eligibility permanently.
        for item in pending {
            for _ in 0..<12 {
                await restartedStore.markOutboxFailure(operationId: item.operationId, error: "Prior transient failure")
            }
        }
        let restarted = SyncCoordinator(accountId: "batch-account", deviceIdentity: device, backend: backend)
        await restarted.registerSpaceKeyRing(ring)
        let report = try await restarted.synchronizeSpaceStore(restartedStore)
        XCTAssertEqual(report.pushedOperationsCount + report.deduplicatedOperationsCount, 2)
        XCTAssertEqual(fixture.pushSizes, [500, 2, 2])
        XCTAssertEqual(Set(fixture.pushIds[2]), retryIds)
        let remaining = await restartedStore.pendingOutboxItems()
        XCTAssertTrue(remaining.isEmpty)
        let conflicts = await restarted.activeConflicts(for: spaceId)
        XCTAssertEqual(conflicts.count, 1)
        let cursor = try await restartedStore.syncCursorSequence(accountId: "batch-account")
        XCTAssertEqual(cursor, 1004)
        XCTAssertFalse(fixture.wireContainsPlaintext)
    }
}

private final class SyncBatchURLProtocol: URLProtocol {
    static var fixture: SyncBatchFixture?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        do {
            guard let fixture = Self.fixture else { throw URLError(.badServerResponse) }
            let result = try fixture.respond(to: request)
            let response = HTTPURLResponse(url: request.url!, statusCode: result.status,
                                           httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: result.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}

private final class SyncBatchFixture {
    let spaceId: UUID
    var operations: [EncryptedSyncOperation]
    var events: [String] = []
    var pushSizes: [Int] = []
    var pushIds: [[UUID]] = []
    var pushedEntityIds: Set<UUID> = []
    var submittedIds: Set<UUID> = []
    var wireContainsPlaintext = false
    private let lock = NSLock()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(spaceId: UUID, operations: [EncryptedSyncOperation]) {
        self.spaceId = spaceId
        self.operations = operations
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func respond(to request: URLRequest) throws -> (status: Int, data: Data) {
        lock.lock()
        defer { lock.unlock() }
        if request.url!.path.hasSuffix("/pull") {
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            let since = Int(query.first { $0.name == "since_cursor" }!.value!)!
            let end = min(since + 500, operations.count)
            let page = operations[since..<end]
            events.append("pull:\(page.count)")
            let rows = try page.enumerated().map { offset, operation -> [String: Any] in
                ["server_cursor": since + offset + 1,
                 "encrypted_envelope_json": ["operation": try JSONSerialization.jsonObject(with: encoder.encode(operation))]]
            }
            return (200, try JSONSerialization.data(withJSONObject: [
                "operations": rows, "latest_cursor": end, "has_more": end < operations.count
            ]))
        }
        let body: Data
        if let data = request.httpBody {
            body = data
        } else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count >= 0 else { throw URLError(.cannotDecodeRawData) }
                if count == 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            body = data
        } else {
            throw URLError(.badServerResponse)
        }
        let payload = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        let rows = payload["operations"] as! [[String: Any]]
        let wire = String(data: body, encoding: .utf8)!
        wireContainsPlaintext = wireContainsPlaintext || wire.contains("Concurrent remote edit") || wire.contains("Encrypted schema")
        guard rows.count <= 500 else { return (422, Data("{}".utf8)) }
        events.append("push:\(rows.count)")
        pushSizes.append(rows.count)
        var acknowledged: [String] = []
        var accepted: [String] = []
        var deduplicated: [String] = []
        var ids: [UUID] = []
        for row in rows {
            let envelope = row["encrypted_envelope"] as! [String: Any]
            let operation = try decoder.decode(EncryptedSyncOperation.self, from: JSONSerialization.data(withJSONObject: envelope["operation"]!))
            ids.append(operation.operationId)
            acknowledged.append(operation.operationId.uuidString)
            pushedEntityIds.insert(operation.entityId)
            if submittedIds.insert(operation.operationId).inserted {
                operations.append(operation)
                accepted.append(operation.operationId.uuidString)
            } else {
                deduplicated.append(operation.operationId.uuidString)
            }
        }
        pushIds.append(ids)
        // Simulate a response lost after commit: replay must reuse the original IDs.
        if pushSizes.count == 2 { return (503, Data("{}".utf8)) }
        return (200, try JSONSerialization.data(withJSONObject: [
            "acknowledged_operation_ids": acknowledged, "accepted_operation_ids": accepted,
            "deduplicated_operation_ids": deduplicated, "latest_cursor": operations.count
        ]))
    }
}
