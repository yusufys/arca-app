import Foundation
import CryptoKit
import ArcaCore
import ArcaCrypto
import ArcaPersistence
import ArcaBilling

// MARK: - App Announcement Banner Model

/// Announcement banner model delivered by the Laravel app feed API.
public struct AppAnnouncementBanner: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let body: String
    public let ctaLabel: String?
    public let ctaUrl: String?
    public let placement: String
    public let targetPlatform: String
    public let targetTier: String
    public let priority: Int

    public init(
        id: String = UUID().uuidString,
        title: String,
        body: String,
        ctaLabel: String? = nil,
        ctaUrl: String? = nil,
        placement: String = "home_banner",
        targetPlatform: String = "all",
        targetTier: String = "all",
        priority: Int = 0
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.ctaLabel = ctaLabel
        self.ctaUrl = ctaUrl
        self.placement = placement
        self.targetPlatform = targetPlatform
        self.targetTier = targetTier
        self.priority = priority
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, body, placement, priority
        case ctaLabel = "cta_label"
        case ctaUrl = "cta_url"
        case targetPlatform = "target_platform"
        case targetTier = "target_tier"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.body = try container.decode(String.self, forKey: .body)
        self.ctaLabel = try container.decodeIfPresent(String.self, forKey: .ctaLabel)
        self.ctaUrl = try container.decodeIfPresent(String.self, forKey: .ctaUrl)
        self.placement = try container.decodeIfPresent(String.self, forKey: .placement) ?? "home_banner"
        self.targetPlatform = try container.decodeIfPresent(String.self, forKey: .targetPlatform) ?? "all"
        self.targetTier = try container.decodeIfPresent(String.self, forKey: .targetTier) ?? "all"
        self.priority = try container.decodeIfPresent(Int.self, forKey: .priority) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(body, forKey: .body)
        try container.encodeIfPresent(ctaLabel, forKey: .ctaLabel)
        try container.encodeIfPresent(ctaUrl, forKey: .ctaUrl)
        try container.encode(placement, forKey: .placement)
        try container.encode(targetPlatform, forKey: .targetPlatform)
        try container.encode(targetTier, forKey: .targetTier)
        try container.encode(priority, forKey: .priority)
    }
}

// MARK: - Mobile Environment & Runtime Configuration

/// Reads mobile environment variables and Info.plist build keys for the Laravel API and RevenueCat SDK.
/// Note: Mobile clients ONLY ever receive PUBLIC SDK keys (e.g. RevenueCat `appl_...`).
/// Secret keys (`REVENUECAT_WEBHOOK_SECRET`, DB credentials, S3 secret keys) live exclusively in `backend/.env`.
public enum ArcaEnvironmentConfig {
    public static var apiBaseURL: URL {
        let envValue = ProcessInfo.processInfo.environment["ARCA_API_BASE_URL"]
            ?? (Bundle.main.object(forInfoDictionaryKey: "ARCA_API_BASE_URL") as? String)
            ?? "http://127.0.0.1:8000"
        return URL(string: envValue) ?? URL(string: "http://127.0.0.1:8000")!
    }

    public static var apiToken: String? {
        ProcessInfo.processInfo.environment["ARCA_API_TOKEN"]
            ?? UserDefaults.standard.string(forKey: "arca.auth.api_token")
    }

    public static var revenueCatPublicSDKKey: String {
        ProcessInfo.processInfo.environment["REVENUECAT_IOS_PUBLIC_KEY"]
            ?? (Bundle.main.object(forInfoDictionaryKey: "REVENUECAT_IOS_PUBLIC_KEY") as? String)
            ?? "appl_replace_with_your_revenuecat_ios_public_sdk_key"
    }

    public static var revenueCatProEntitlementID: String {
        ProcessInfo.processInfo.environment["REVENUECAT_PRO_ENTITLEMENT_ID"]
            ?? (Bundle.main.object(forInfoDictionaryKey: "REVENUECAT_PRO_ENTITLEMENT_ID") as? String)
            ?? "arca_app_pro"
    }
}

// MARK: - Laravel HTTP Sync & Announcement Backend

/// Authenticated network transport. Failed requests always throw; they never acknowledge local outbox work.
public final class LaravelArcaSyncBackend: ArcaSyncBackendProtocol, @unchecked Sendable {
    public let baseURL: URL
    public var apiToken: String?
    public let session: URLSession
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder
    private var privacyGenerations: [UUID: Int] = [:]

    public init(baseURL: URL = ArcaEnvironmentConfig.apiBaseURL, apiToken: String? = ArcaEnvironmentConfig.apiToken,
                session: URLSession = .shared, fallback: InMemoryArcaSyncBackend = InMemoryArcaSyncBackend()) {
        self.baseURL = baseURL; self.apiToken = apiToken; self.session = session
        jsonEncoder = JSONEncoder(); jsonEncoder.dateEncodingStrategy = .iso8601
        jsonDecoder = JSONDecoder(); jsonDecoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "Invalid API timestamp")
        }
    }

    private func createRequest(path: String, method: String, body: Data? = nil, queryItems: [URLQueryItem]? = nil) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = queryItems
        var request = URLRequest(url: components.url!); request.httpMethod = method; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let apiToken { request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization") }
        return request
    }
    private func request(_ path: String, method: String = "GET", body: Data? = nil, deviceId: String? = nil,
                         query: [URLQueryItem]? = nil, authenticated: Bool = true) async throws -> Data {
        if authenticated && (apiToken?.isEmpty != false) { throw SyncServiceError.unauthenticated }
        var req = createRequest(path: "api/v1/" + path, method: method, body: body, queryItems: query)
        if let deviceId { req.setValue(deviceId, forHTTPHeaderField: "X-Device-Id") }
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200...299).contains(http.statusCode) else {
            // Do not propagate response bodies: they can contain echoed credentials or user content.
            throw NSError(domain: "ArcaSync.HTTP", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "Sync server request failed (HTTP \(http.statusCode))."])
        }
        return data
    }
    private struct AccountResponse: Decodable {
        struct User: Decodable { let uuid: String; let email: String; let remote_storage_bytes_used: Int64 }
        struct Entitlements: Decodable { let max_devices: Int; let max_storage_bytes: Int64 }
        let user: User; let entitlements: Entitlements; let api_token: String?
    }
    private func authSession(_ data: Data) throws -> SyncAuthSession {
        let value = try jsonDecoder.decode(AccountResponse.self, from: data)
        if let token = value.api_token { apiToken = token }
        guard let token = apiToken else { throw SyncServiceError.unauthenticated }
        return SyncAuthSession(accountId: value.user.uuid, email: value.user.email, authToken: token,
                               maxAllowedDevices: value.entitlements.max_devices, storageQuotaBytes: value.entitlements.max_storage_bytes)
    }
    public func signIn(email: String, password: String, name: String? = nil) async throws -> SyncAuthSession {
        var payload = ["email": email, "password": password]
        if let name { payload["name"] = name }
        return try authSession(await request(name == nil ? "auth/login" : "auth/register", method: "POST",
                                            body: jsonEncoder.encode(payload), authenticated: false))
    }
    public func authenticate(email: String, credentialProof: String, maxAllowedDevices: Int, storageQuotaBytes: Int64) async throws -> SyncAuthSession {
        if apiToken?.isEmpty == false { return try authSession(await request("auth/me")) }
        return try await signIn(email: email, password: credentialProof)
    }
    public func deleteAccountAndRemoteData(accountId: String) async throws -> RemoteDeletionReceipt {
        let receipt = try jsonDecoder.decode(RemoteDeletionReceipt.self, from: await request("account", method: "DELETE"))
        guard receipt.accountId == accountId, receipt.didDeleteEntireAccount,
              receipt.deletedSpaceId == nil, receipt.verifiedZeroRemainingRecords else {
            throw SyncServiceError.invalidOperationEnvelope("The server did not verify complete account deletion.")
        }
        apiToken = nil; return receipt
    }
    private struct DeviceWire: Decodable {
        let id: String; let device_name: String; let platform: String; let public_key_x25519: String?
        let created_at: Date; let last_synced_at: Date?; let revoked_at: Date?
        var model: EnrolledDevice { EnrolledDevice(deviceId: id, deviceName: device_name, platform: platform,
            publicKeyBase64: public_key_x25519 ?? "", enrolledAt: created_at, lastSyncAt: last_synced_at,
            isRevoked: revoked_at != nil, revokedAt: revoked_at) }
    }
    public func registerAnonymousDevice(deviceId: UUID, deviceToken: String, deviceName: String, platform: String, publicKeyBase64: String? = nil) async throws {
        var payload = ["device_id": deviceId.uuidString, "device_token": deviceToken, "device_name": deviceName, "platform": platform.lowercased()]
        payload["public_key_x25519"] = publicKeyBase64
        _ = try await request("devices/register", method: "POST", body: jsonEncoder.encode(payload), authenticated: false)
    }
    public func loginAndAssociateDevice(email: String, password: String, deviceId: UUID, deviceToken: String, deviceName: String) async throws -> String {
        let payload = ["email": email, "password": password, "device_id": deviceId.uuidString, "device_token": deviceToken, "device_name": deviceName]
        return try authSession(await request("auth/login", method: "POST", body: jsonEncoder.encode(payload), authenticated: false)).authToken
    }
    public func enrollDevice(accountId: String, device: EnrolledDevice, maxAllowedDevices: Int, wrappedMasterKey: DeviceWrappedMasterKey?) async throws -> DeviceEnrollmentReceipt {
        let payload = ["device_id": device.deviceId, "device_name": device.deviceName, "platform": device.platform.lowercased(), "public_key_x25519": device.publicKeyBase64]
        struct Response: Decodable { let device: DeviceWire }
        let enrolled = try jsonDecoder.decode(Response.self, from: await request("devices/enroll", method: "POST", body: jsonEncoder.encode(payload))).device.model
        let devices = try await listEnrolledDevices(accountId: accountId)
        return DeviceEnrollmentReceipt(accountId: accountId, enrolledDevice: enrolled, activeDevices: devices.filter { !$0.isRevoked }, maxAllowedDevices: maxAllowedDevices, wrappedMasterKey: wrappedMasterKey)
    }
    public func listEnrolledDevices(accountId: String) async throws -> [EnrolledDevice] {
        struct Response: Decodable { let devices: [DeviceWire] }
        return try jsonDecoder.decode(Response.self, from: await request("devices")).devices.map(\.model)
    }
    public func revokeDevice(accountId: String, revokingDeviceId: String, requestedByDeviceId: String, rotatedSpaceKeys: [WrappedSpaceKeyRing]) async throws -> DeviceRevocationReceipt {
        struct Response: Decodable { let device: DeviceWire }
        let device = try jsonDecoder.decode(Response.self, from: await request("devices/\(revokingDeviceId)/revoke", method: "POST", deviceId: requestedByDeviceId)).device.model
        for key in rotatedSpaceKeys { try await publishWrappedSpaceKey(accountId: accountId, deviceId: requestedByDeviceId, wrappedSpaceKey: key) }
        return DeviceRevocationReceipt(accountId: accountId, revokedDevice: device, remainingActiveDevices: try await listEnrolledDevices(accountId: accountId).filter { !$0.isRevoked }, rotatedSpaceKeys: rotatedSpaceKeys)
    }
    public func publishWrappedSpaceKey(accountId: String, deviceId: String, wrappedSpaceKey: WrappedSpaceKeyRing) async throws {
        if let existing = try await fetchLatestWrappedSpaceKey(accountId: accountId, spaceId: wrappedSpaceKey.spaceId, deviceId: deviceId),
           existing.keyGeneration == wrappedSpaceKey.keyGeneration && existing.keyId == wrappedSpaceKey.keyId { return }
        _ = try await request("spaces/\(wrappedSpaceKey.spaceId.uuidString)/keys", method: "POST", body: jsonEncoder.encode(wrappedSpaceKey), deviceId: deviceId)
    }
    public func fetchLatestWrappedSpaceKey(accountId: String, spaceId: UUID, deviceId: String) async throws -> WrappedSpaceKeyRing? {
        struct Response: Decodable { let key: WrappedSpaceKeyRing? }
        return try jsonDecoder.decode(Response.self, from: await request("spaces/\(spaceId.uuidString)/keys", deviceId: deviceId)).key
    }
    public func fetchRecoveryBundle(deviceId: String = "") async throws -> WrappedRecoveryBundle? {
        struct Response: Decodable { let bundle: WrappedRecoveryBundle? }
        return try jsonDecoder.decode(Response.self, from: await request("sync/recovery")).bundle
    }
    public func publishRecoveryBundle(_ bundle: WrappedRecoveryBundle, deviceId: String) async throws -> WrappedRecoveryBundle {
        struct Response: Decodable { let bundle: WrappedRecoveryBundle }
        return try jsonDecoder.decode(Response.self, from: await request("sync/recovery", method: "POST", body: jsonEncoder.encode(bundle), deviceId: deviceId)).bundle
    }
    public struct RemoteSpace: Decodable, Sendable {
        public let id: UUID
        public let current_key_version: Int
        public let wrapped_space_keys_json: [WrappedSpaceKeyRing]?
    }
    public func listRemoteSpaces(deviceId: String) async throws -> [RemoteSpace] {
        struct Response: Decodable { let spaces: [RemoteSpace] }
        return try jsonDecoder.decode(Response.self, from: await request("spaces", deviceId: deviceId)).spaces
    }
    private struct OperationEnvelope: Codable { let operation: EncryptedSyncOperation }
    private struct PushOperation: Encodable {
        let operation_id: UUID; let entity_id: UUID; let entity_type: String; let base_revision: Int64
        let new_revision: Int64; let key_version: Int; let schema_version = 1; let ciphertext_bytes: Int
        let encrypted_envelope: OperationEnvelope
    }
    public func fetchCloudPrivacyRules(spaceId: UUID, deviceId: String) async throws -> [EncryptedCloudPrivacyRule] {
        struct Response: Decodable { let generation: Int; let rules: [EncryptedCloudPrivacyRule] }
        do {
            let result = try jsonDecoder.decode(Response.self, from: await request("spaces/\(spaceId)/privacy", deviceId: deviceId))
            privacyGenerations[spaceId] = result.generation
            return result.rules
        } catch let error as NSError where error.domain == "ArcaSync.HTTP" && error.code == 404 {
            // Older servers can sync ordinary data, but may never acknowledge a privacy deletion.
            return []
        }
    }

    public func replaceCloudPrivacyRule(_ rule: EncryptedCloudPrivacyRule, spaceId: UUID, deviceId: String, expectedCursor: Int64) async throws {
        struct Payload: Encodable { let rule: EncryptedCloudPrivacyRule; let expected_cursor: Int64; let generation: Int }
        struct Response: Decodable { let generation: Int; let collection_id: UUID; let verified: Bool }
        let response = try jsonDecoder.decode(Response.self, from: await request("spaces/\(spaceId)/privacy", method: "POST",
            body: jsonEncoder.encode(Payload(rule: rule, expected_cursor: expectedCursor, generation: privacyGenerations[spaceId] ?? 0)), deviceId: deviceId))
        guard response.verified, response.collection_id == rule.collectionId else { throw SyncServiceError.invalidOperationEnvelope("Remote private copy removal could not be verified.") }
        privacyGenerations[spaceId] = response.generation
    }

    public func pushEncryptedOperations(accountId: String, spaceId: UUID, deviceId: String, operations: [EncryptedSyncOperation]) async throws -> SyncPushReceipt {
        struct Payload: Encodable { let operations: [PushOperation]; let privacy_protocol = 1; let privacy_generation: Int }
        let wire = try operations.map { op -> PushOperation in
            guard op.spaceId == spaceId && op.authorDeviceId == deviceId else { throw SyncServiceError.invalidOperationEnvelope("Operation identity mismatch.") }
            let envelope = OperationEnvelope(operation: op)
            return PushOperation(operation_id: op.operationId, entity_id: op.entityId, entity_type: op.entityType == .collectionSchema ? "schema" : "record",
                                 base_revision: op.baseRevision, new_revision: op.targetRevision, key_version: op.keyGeneration,
                                 ciphertext_bytes: try jsonEncoder.encode(envelope).count, encrypted_envelope: envelope)
        }
        struct Response: Decodable { let acknowledged_operation_ids: [UUID]; let latest_cursor: Int64; let remote_storage_bytes_used: Int64? }
        let value = try jsonDecoder.decode(Response.self, from: await request("spaces/\(spaceId.uuidString)/push", method: "POST", body: jsonEncoder.encode(Payload(operations: wire, privacy_generation: privacyGenerations[spaceId] ?? 0)), deviceId: deviceId))
        return SyncPushReceipt(spaceId: spaceId, acceptedOperationIds: value.acknowledged_operation_ids, deduplicatedOperationIds: [], latestCursor: SyncCursor(sequenceNumber: value.latest_cursor), totalAccountBytesUsed: value.remote_storage_bytes_used ?? 0)
    }
    public func pullEncryptedOperations(accountId: String, spaceId: UUID, deviceId: String, sinceCursor: SyncCursor?, limit: Int) async throws -> SyncPullBatch {
        struct Wire: Decodable { let server_cursor: Int64; let encrypted_envelope_json: OperationEnvelope }
        struct Response: Decodable { let operations: [Wire]; let latest_cursor: Int64; let has_more: Bool? }
        let value = try jsonDecoder.decode(Response.self, from: await request("spaces/\(spaceId.uuidString)/pull", deviceId: deviceId, query: [URLQueryItem(name: "since_cursor", value: String(sinceCursor?.sequenceNumber ?? 0)), URLQueryItem(name: "limit", value: String(max(1, min(500, limit))))]))
        let operations = try value.operations.map { wire -> EncryptedSyncOperation in
            var op = wire.encrypted_envelope_json.operation
            guard op.spaceId == spaceId else { throw SyncServiceError.invalidOperationEnvelope("Remote operation space mismatch.") }
            op.serverSequenceNumber = wire.server_cursor; return op
        }
        return SyncPullBatch(spaceId: spaceId, operations: operations, nextCursor: SyncCursor(sequenceNumber: value.latest_cursor), hasMore: value.has_more ?? false)
    }
    public func uploadEncryptedAttachment(accountId: String, deviceId: String, blob: EncryptedAttachmentBlob) async throws {
        struct Payload: Encodable { let blob: EncryptedAttachmentBlob; let privacy_generation: Int }
        guard blob.collectionId != nil else { throw SyncServiceError.invalidOperationEnvelope("Image collection is missing.") }
        _ = try await request("spaces/\(blob.spaceId.uuidString)/attachments", method: "POST",
            body: jsonEncoder.encode(Payload(blob: blob, privacy_generation: privacyGenerations[blob.spaceId] ?? 0)), deviceId: deviceId)
    }
    public func downloadEncryptedAttachment(accountId: String, spaceId: UUID, attachmentId: UUID, deviceId: String) async throws -> EncryptedAttachmentBlob {
        struct Response: Decodable { let blob: EncryptedAttachmentBlob }
        return try jsonDecoder.decode(Response.self, from: await request("spaces/\(spaceId.uuidString)/attachments/\(attachmentId.uuidString)", deviceId: deviceId)).blob
    }
    /// An explicitly opted-in device may resume a previously disabled Space.
    /// A new Space will be registered when its first wrapped key is published.
    public func enableCloudSync(spaceId: UUID, deviceId: String) async throws {
        let payload = try jsonEncoder.encode(["target_mode": "arca_sync"])
        do {
            _ = try await request("spaces/\(spaceId.uuidString)/migrate-mode", method: "POST", body: payload, deviceId: deviceId)
        } catch let error as NSError where error.domain == "ArcaSync.HTTP" && error.code == 404 {
            return
        }
    }

    public func deleteRemoteSpaceData(accountId: String, spaceId: UUID, requestedByDeviceId: String) async throws -> RemoteDeletionReceipt {
        struct Payload: Encodable { let target_mode = "local_only"; let delete_remote_ciphertext = true }
        struct Receipt: Decodable { let deleted_operation_count: Int; let deleted_attachment_count: Int; let freed_storage_bytes: Int64; let verified_zero_remaining: Bool; let deleted_at: Date }
        struct Response: Decodable { let receipt: Receipt }
        let value = try jsonDecoder.decode(Response.self, from: await request("spaces/\(spaceId.uuidString)/migrate-mode", method: "POST", body: jsonEncoder.encode(Payload()), deviceId: requestedByDeviceId)).receipt
        return RemoteDeletionReceipt(accountId: accountId, deletedSpaceId: spaceId, didDeleteEntireAccount: false, purgedOperationsCount: value.deleted_operation_count, purgedAttachmentsCount: value.deleted_attachment_count, purgedBytesCount: value.freed_storage_bytes, verifiedZeroRemainingRecords: value.verified_zero_remaining, deletedAt: value.deleted_at)
    }
    public func activeDeviceCount(accountId: String) async throws -> Int { try await listEnrolledDevices(accountId: accountId).filter { !$0.isRevoked }.count }
    public func registerSpace(accountId: String, spaceId: UUID, deviceId: String, wrappedSpaceKey: WrappedSpaceKeyRing) async throws { try await publishWrappedSpaceKey(accountId: accountId, deviceId: deviceId, wrappedSpaceKey: wrappedSpaceKey) }
    public func updateSpaceKeyEnvelopes(accountId: String, deviceId: String, envelopes: [WrappedSpaceKeyRing]) async throws { for key in envelopes { try await publishWrappedSpaceKey(accountId: accountId, deviceId: deviceId, wrappedSpaceKey: key) } }
    public func pushOperations(accountId: String, spaceId: UUID, deviceId: String, operations: [EncryptedSyncOperation]) async throws -> SyncPushReceipt { try await pushEncryptedOperations(accountId: accountId, spaceId: spaceId, deviceId: deviceId, operations: operations) }
    public func pullOperations(accountId: String, spaceId: UUID, deviceId: String, sinceCursor: SyncCursor?, limit: Int) async throws -> SyncPullBatch { try await pullEncryptedOperations(accountId: accountId, spaceId: spaceId, deviceId: deviceId, sinceCursor: sinceCursor, limit: limit) }
    public func deleteAllRemoteDataForSpace(accountId: String, spaceId: UUID, requestedByDeviceId: String) async throws -> RemoteDeletionReceipt { try await deleteRemoteSpaceData(accountId: accountId, spaceId: spaceId, requestedByDeviceId: requestedByDeviceId) }
    public func remoteBytesUsed(accountId: String, spaceId: UUID? = nil) async throws -> Int64 { try jsonDecoder.decode(AccountResponse.self, from: await request("auth/me")).user.remote_storage_bytes_used }

    // MARK: - 7. App Feed / Announcement Banners

    public func fetchAppFeed(platform: String, tier: SubscriptionTier) async throws -> [AppAnnouncementBanner] {

        let query = [
            URLQueryItem(name: "platform", value: platform),
            URLQueryItem(name: "tier", value: tier.rawValue)
        ]
        let req = createRequest(path: "api/v1/app-feed", method: "GET", queryItems: query)
        do {
            let (data, response) = try await session.data(for: req)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                if let direct = try? jsonDecoder.decode([AppAnnouncementBanner].self, from: data) {
                    return direct
                }
                struct FeedWrapper: Decodable {
                    let data: [AppAnnouncementBanner]?
                    let banners: [AppAnnouncementBanner]?
                }
                if let wrapper = try? jsonDecoder.decode(FeedWrapper.self, from: data) {
                    return wrapper.data ?? wrapper.banners ?? []
                }
            }
            return defaultAnnouncements(for: platform, tier: tier)
        } catch {
            return defaultAnnouncements(for: platform, tier: tier)
        }
    }

    private func defaultAnnouncements(for platform: String, tier: SubscriptionTier) -> [AppAnnouncementBanner] {
        return [
            AppAnnouncementBanner(
                id: "banner-default-welcome",
                title: "Arca Sync: End-to-End Encrypted Cloud DB",
                body: "Your spaces synchronize securely with zero-knowledge encryption across iOS and Android.",
                ctaLabel: "Learn More",
                ctaUrl: "https://arca.app/sync",
                placement: "home_banner",
                targetPlatform: platform,
                targetTier: tier.rawValue,
                priority: 10
            )
        ]
    }
}
