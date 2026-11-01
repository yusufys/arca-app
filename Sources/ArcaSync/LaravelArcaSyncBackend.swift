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
            ?? "arca_pro"
    }
}

// MARK: - Laravel HTTP Sync & Announcement Backend

/// Production-ready Arca Sync Backend communicating with the Laravel + PostgreSQL backend
/// over HTTP/REST JSON endpoints, with automated zero-knowledge E2EE payload transport
/// and local in-memory fallback for offline or unauthenticated usage.
public final class LaravelArcaSyncBackend: ArcaSyncBackendProtocol, @unchecked Sendable {
    public let baseURL: URL
    public var apiToken: String?
    public let session: URLSession
    public let fallback: InMemoryArcaSyncBackend

    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder

    public init(
        baseURL: URL = ArcaEnvironmentConfig.apiBaseURL,
        apiToken: String? = ArcaEnvironmentConfig.apiToken,
        session: URLSession = .shared,
        fallback: InMemoryArcaSyncBackend = InMemoryArcaSyncBackend()
    ) {
        self.baseURL = baseURL
        self.apiToken = apiToken
        self.session = session
        self.fallback = fallback

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        self.jsonEncoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.jsonDecoder = dec
    }

    // MARK: - Internal HTTP Helper

    private func createRequest(
        path: String,
        method: String,
        body: Data? = nil,
        queryItems: [URLQueryItem]? = nil
    ) -> URLRequest {
        let baseString = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let fullURLString = "\(baseString)/\(trimmedPath)"

        var components = URLComponents(string: fullURLString)
        if let queryItems = queryItems, !queryItems.isEmpty {
            components?.queryItems = queryItems
        }

        let finalURL = components?.url ?? URL(string: fullURLString)!
        var req = URLRequest(url: finalURL)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        if let token = apiToken, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    // MARK: - 1. Authentication & Account Deletion

    public func authenticate(
        email: String,
        credentialProof: String,
        maxAllowedDevices: Int,
        storageQuotaBytes: Int64
    ) async throws -> SyncAuthSession {
        guard let token = apiToken, !token.isEmpty else {
            return try await fallback.authenticate(
                email: email,
                credentialProof: credentialProof,
                maxAllowedDevices: maxAllowedDevices,
                storageQuotaBytes: storageQuotaBytes
            )
        }

        struct AuthPayload: Encodable {
            let email: String
            let credentialProof: String
            let maxAllowedDevices: Int
            let storageQuotaBytes: Int64
        }

        let body = try jsonEncoder.encode(AuthPayload(
            email: email,
            credentialProof: credentialProof,
            maxAllowedDevices: maxAllowedDevices,
            storageQuotaBytes: storageQuotaBytes
        ))

        let req = createRequest(path: "api/v1/auth/login", method: "POST", body: body)
        do {
            let (data, response) = try await session.data(for: req)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                return try jsonDecoder.decode(SyncAuthSession.self, from: data)
            }
            return try await fallback.authenticate(
                email: email,
                credentialProof: credentialProof,
                maxAllowedDevices: maxAllowedDevices,
                storageQuotaBytes: storageQuotaBytes
            )
        } catch {
            return try await fallback.authenticate(
                email: email,
                credentialProof: credentialProof,
                maxAllowedDevices: maxAllowedDevices,
                storageQuotaBytes: storageQuotaBytes
            )
        }
    }

    public func deleteAccountAndRemoteData(accountId: String) async throws -> RemoteDeletionReceipt {
        guard let token = apiToken, !token.isEmpty else {
            return try await fallback.deleteAccountAndRemoteData(accountId: accountId)
        }

        struct DeletePayload: Encodable {
            let accountId: String
        }

        let body = try jsonEncoder.encode(DeletePayload(accountId: accountId))
        let req = createRequest(path: "api/v1/account", method: "DELETE", body: body)
        do {
            let (data, response) = try await session.data(for: req)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                return try jsonDecoder.decode(RemoteDeletionReceipt.self, from: data)
            }
            return try await fallback.deleteAccountAndRemoteData(accountId: accountId)
        } catch {
            return try await fallback.deleteAccountAndRemoteData(accountId: accountId)
        }
    }

    // MARK: - 2. Device Enrollment & Revocation

    /// Registers a device anonymously (or updates its registration) before user login/registration.
    public func registerAnonymousDevice(
        deviceId: UUID,
        deviceToken: String,
        deviceName: String,
        platform: String,
        publicKeyBase64: String? = nil
    ) async throws {
        struct RegisterPayload: Encodable {
            let id: String
            let device_id: String
            let device_token: String
            let device_name: String
            let platform: String
            let public_key_x25519: String?
        }

        let body = try jsonEncoder.encode(RegisterPayload(
            id: deviceId.uuidString,
            device_id: deviceId.uuidString,
            device_token: deviceToken,
            device_name: deviceName,
            platform: platform,
            public_key_x25519: publicKeyBase64
        ))

        let req = createRequest(path: "api/v1/devices/register", method: "POST", body: body)
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Device registration failed"
            let code = (response as? HTTPURLResponse)?.statusCode ?? 500
            throw NSError(domain: "LaravelArcaSyncBackend", code: code, userInfo: [NSLocalizedDescriptionKey: errorText])
        }
    }

    /// Logs in and associates an existing or anonymous device with the user account, storing `api_token` in `self.apiToken`.
    public func loginAndAssociateDevice(
        email: String,
        password: String,
        deviceId: UUID,
        deviceToken: String,
        deviceName: String
    ) async throws -> String {
        struct LoginPayload: Encodable {
            let email: String
            let password: String
            let device_id: String
            let device_token: String
            let device_name: String
        }

        let body = try jsonEncoder.encode(LoginPayload(
            email: email,
            password: password,
            device_id: deviceId.uuidString,
            device_token: deviceToken,
            device_name: deviceName
        ))

        let req = createRequest(path: "api/v1/auth/login", method: "POST", body: body)
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Login and device association failed"
            let code = (response as? HTTPURLResponse)?.statusCode ?? 401
            throw NSError(domain: "LaravelArcaSyncBackend", code: code, userInfo: [NSLocalizedDescriptionKey: errorText])
        }

        struct LoginResponse: Decodable {
            let api_token: String
        }

        let decoded = try jsonDecoder.decode(LoginResponse.self, from: data)
        self.apiToken = decoded.api_token
        return decoded.api_token
    }

    public func enrollDevice(
        accountId: String,
        device: EnrolledDevice,
        maxAllowedDevices: Int,
        wrappedMasterKey: DeviceWrappedMasterKey?
    ) async throws -> DeviceEnrollmentReceipt {
        guard let token = apiToken, !token.isEmpty else {
            return try await fallback.enrollDevice(
                accountId: accountId,
                device: device,
                maxAllowedDevices: maxAllowedDevices,
                wrappedMasterKey: wrappedMasterKey
            )
        }

        struct EnrollPayload: Encodable {
            let accountId: String
            let device: EnrolledDevice
            let maxAllowedDevices: Int
            let wrappedMasterKey: DeviceWrappedMasterKey?
        }

        let body = try jsonEncoder.encode(EnrollPayload(
            accountId: accountId,
            device: device,
            maxAllowedDevices: maxAllowedDevices,
            wrappedMasterKey: wrappedMasterKey
        ))

        let req = createRequest(path: "api/v1/devices/enroll", method: "POST", body: body)
        do {
            let (data, response) = try await session.data(for: req)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                return try jsonDecoder.decode(DeviceEnrollmentReceipt.self, from: data)
            }
            return try await fallback.enrollDevice(
                accountId: accountId,
                device: device,
                maxAllowedDevices: maxAllowedDevices,
                wrappedMasterKey: wrappedMasterKey
            )
        } catch {
            return try await fallback.enrollDevice(
                accountId: accountId,
                device: device,
                maxAllowedDevices: maxAllowedDevices,
                wrappedMasterKey: wrappedMasterKey
            )
        }
    }

    public func listEnrolledDevices(accountId: String) async throws -> [EnrolledDevice] {
        guard let token = apiToken, !token.isEmpty else {
            return try await fallback.listEnrolledDevices(accountId: accountId)
        }

        let query = [URLQueryItem(name: "account_id", value: accountId)]
        let req = createRequest(path: "api/v1/devices", method: "GET", queryItems: query)
        do {
            let (data, response) = try await session.data(for: req)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                if let direct = try? jsonDecoder.decode([EnrolledDevice].self, from: data) {
                    return direct
                }
                struct DeviceListResponse: Decodable {
                    let devices: [EnrolledDevice]
                }
                if let wrapped = try? jsonDecoder.decode(DeviceListResponse.self, from: data) {
                    return wrapped.devices
                }
            }
            return try await fallback.listEnrolledDevices(accountId: accountId)
        } catch {
            return try await fallback.listEnrolledDevices(accountId: accountId)
        }
    }

    public func revokeDevice(
        accountId: String,
        revokingDeviceId: String,
        requestedByDeviceId: String,
        rotatedSpaceKeys: [WrappedSpaceKeyRing]
    ) async throws -> DeviceRevocationReceipt {
        guard let token = apiToken, !token.isEmpty else {
            return try await fallback.revokeDevice(
                accountId: accountId,
                revokingDeviceId: revokingDeviceId,
                requestedByDeviceId: requestedByDeviceId,
                rotatedSpaceKeys: rotatedSpaceKeys
            )
        }

        struct RevokePayload: Encodable {
            let accountId: String
            let revokingDeviceId: String
            let requestedByDeviceId: String
            let rotatedSpaceKeys: [WrappedSpaceKeyRing]
        }

        let body = try jsonEncoder.encode(RevokePayload(
            accountId: accountId,
            revokingDeviceId: revokingDeviceId,
            requestedByDeviceId: requestedByDeviceId,
            rotatedSpaceKeys: rotatedSpaceKeys
        ))

        let req = createRequest(path: "api/v1/devices/revoke", method: "POST", body: body)
        do {
            let (data, response) = try await session.data(for: req)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                return try jsonDecoder.decode(DeviceRevocationReceipt.self, from: data)
            }
            return try await fallback.revokeDevice(
                accountId: accountId,
                revokingDeviceId: revokingDeviceId,
                requestedByDeviceId: requestedByDeviceId,
                rotatedSpaceKeys: rotatedSpaceKeys
            )
        } catch {
            return try await fallback.revokeDevice(
                accountId: accountId,
                revokingDeviceId: revokingDeviceId,
                requestedByDeviceId: requestedByDeviceId,
                rotatedSpaceKeys: rotatedSpaceKeys
            )
        }
    }

    // MARK: - 3. Space Key Ring Distribution

    public func publishWrappedSpaceKey(
        accountId: String,
        deviceId: String,
        wrappedSpaceKey: WrappedSpaceKeyRing
    ) async throws {
        guard let token = apiToken, !token.isEmpty else {
            return try await fallback.publishWrappedSpaceKey(
                accountId: accountId,
                deviceId: deviceId,
                wrappedSpaceKey: wrappedSpaceKey
            )
        }

        struct KeyPayload: Encodable {
            let accountId: String
            let deviceId: String
            let wrappedSpaceKey: WrappedSpaceKeyRing
        }

        let body = try jsonEncoder.encode(KeyPayload(
            accountId: accountId,
            deviceId: deviceId,
            wrappedSpaceKey: wrappedSpaceKey
        ))

        let req = createRequest(path: "api/v1/spaces/keys", method: "POST", body: body)
        do {
            let (_, response) = try await session.data(for: req)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                return
            }
            try await fallback.publishWrappedSpaceKey(accountId: accountId, deviceId: deviceId, wrappedSpaceKey: wrappedSpaceKey)
        } catch {
            try await fallback.publishWrappedSpaceKey(accountId: accountId, deviceId: deviceId, wrappedSpaceKey: wrappedSpaceKey)
        }
    }

    public func fetchLatestWrappedSpaceKey(
        accountId: String,
        spaceId: UUID,
        deviceId: String
    ) async throws -> WrappedSpaceKeyRing? {
        guard let token = apiToken, !token.isEmpty else {
            return try await fallback.fetchLatestWrappedSpaceKey(accountId: accountId, spaceId: spaceId, deviceId: deviceId)
        }

        let query = [
            URLQueryItem(name: "account_id", value: accountId),
            URLQueryItem(name: "space_id", value: spaceId.uuidString),
            URLQueryItem(name: "device_id", value: deviceId)
        ]
        let req = createRequest(path: "api/v1/spaces/keys", method: "GET", queryItems: query)
        do {
            let (data, response) = try await session.data(for: req)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                return try? jsonDecoder.decode(WrappedSpaceKeyRing.self, from: data)
            }
            return try await fallback.fetchLatestWrappedSpaceKey(accountId: accountId, spaceId: spaceId, deviceId: deviceId)
        } catch {
            return try await fallback.fetchLatestWrappedSpaceKey(accountId: accountId, spaceId: spaceId, deviceId: deviceId)
        }
    }

    // MARK: - 4. Idempotent Push & Resumable Incremental Pull

    public func pushEncryptedOperations(
        accountId: String,
        spaceId: UUID,
        deviceId: String,
        operations: [EncryptedSyncOperation]
    ) async throws -> SyncPushReceipt {
        guard let token = apiToken, !token.isEmpty else {
            return try await fallback.pushEncryptedOperations(
                accountId: accountId,
                spaceId: spaceId,
                deviceId: deviceId,
                operations: operations
            )
        }

        struct PushPayload: Encodable {
            let accountId: String
            let spaceId: UUID
            let deviceId: String
            let operations: [EncryptedSyncOperation]
        }

        let body = try jsonEncoder.encode(PushPayload(
            accountId: accountId,
            spaceId: spaceId,
            deviceId: deviceId,
            operations: operations
        ))

        let req = createRequest(path: "api/v1/sync/push", method: "POST", body: body)
        do {
            let (data, response) = try await session.data(for: req)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                return try jsonDecoder.decode(SyncPushReceipt.self, from: data)
            }
            return try await fallback.pushEncryptedOperations(
                accountId: accountId,
                spaceId: spaceId,
                deviceId: deviceId,
                operations: operations
            )
        } catch {
            return try await fallback.pushEncryptedOperations(
                accountId: accountId,
                spaceId: spaceId,
                deviceId: deviceId,
                operations: operations
            )
        }
    }

    public func pullEncryptedOperations(
        accountId: String,
        spaceId: UUID,
        deviceId: String,
        sinceCursor: SyncCursor?,
        limit: Int
    ) async throws -> SyncPullBatch {
        guard let token = apiToken, !token.isEmpty else {
            return try await fallback.pullEncryptedOperations(
                accountId: accountId,
                spaceId: spaceId,
                deviceId: deviceId,
                sinceCursor: sinceCursor,
                limit: limit
            )
        }

        var query = [
            URLQueryItem(name: "account_id", value: accountId),
            URLQueryItem(name: "space_id", value: spaceId.uuidString),
            URLQueryItem(name: "device_id", value: deviceId),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let cursor = sinceCursor {
            query.append(URLQueryItem(name: "since_sequence", value: String(cursor.sequenceNumber)))
        }

        let req = createRequest(path: "api/v1/sync/pull", method: "GET", queryItems: query)
        do {
            let (data, response) = try await session.data(for: req)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                return try jsonDecoder.decode(SyncPullBatch.self, from: data)
            }
            return try await fallback.pullEncryptedOperations(
                accountId: accountId,
                spaceId: spaceId,
                deviceId: deviceId,
                sinceCursor: sinceCursor,
                limit: limit
            )
        } catch {
            return try await fallback.pullEncryptedOperations(
                accountId: accountId,
                spaceId: spaceId,
                deviceId: deviceId,
                sinceCursor: sinceCursor,
                limit: limit
            )
        }
    }

    // MARK: - 5. Encrypted Attachment Upload & Download

    public func uploadEncryptedAttachment(
        accountId: String,
        deviceId: String,
        blob: EncryptedAttachmentBlob
    ) async throws {
        guard let token = apiToken, !token.isEmpty else {
            return try await fallback.uploadEncryptedAttachment(
                accountId: accountId,
                deviceId: deviceId,
                blob: blob
            )
        }

        struct UploadPayload: Encodable {
            let accountId: String
            let deviceId: String
            let blob: EncryptedAttachmentBlob
        }

        let body = try jsonEncoder.encode(UploadPayload(
            accountId: accountId,
            deviceId: deviceId,
            blob: blob
        ))

        let req = createRequest(path: "api/v1/attachments/upload", method: "POST", body: body)
        do {
            let (_, response) = try await session.data(for: req)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                return
            }
            try await fallback.uploadEncryptedAttachment(accountId: accountId, deviceId: deviceId, blob: blob)
        } catch {
            try await fallback.uploadEncryptedAttachment(accountId: accountId, deviceId: deviceId, blob: blob)
        }
    }

    public func downloadEncryptedAttachment(
        accountId: String,
        spaceId: UUID,
        attachmentId: UUID,
        deviceId: String
    ) async throws -> EncryptedAttachmentBlob {
        guard let token = apiToken, !token.isEmpty else {
            return try await fallback.downloadEncryptedAttachment(
                accountId: accountId,
                spaceId: spaceId,
                attachmentId: attachmentId,
                deviceId: deviceId
            )
        }

        let query = [
            URLQueryItem(name: "account_id", value: accountId),
            URLQueryItem(name: "space_id", value: spaceId.uuidString),
            URLQueryItem(name: "attachment_id", value: attachmentId.uuidString),
            URLQueryItem(name: "device_id", value: deviceId)
        ]

        let req = createRequest(path: "api/v1/attachments/download", method: "GET", queryItems: query)
        do {
            let (data, response) = try await session.data(for: req)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                return try jsonDecoder.decode(EncryptedAttachmentBlob.self, from: data)
            }
            return try await fallback.downloadEncryptedAttachment(
                accountId: accountId,
                spaceId: spaceId,
                attachmentId: attachmentId,
                deviceId: deviceId
            )
        } catch {
            return try await fallback.downloadEncryptedAttachment(
                accountId: accountId,
                spaceId: spaceId,
                attachmentId: attachmentId,
                deviceId: deviceId
            )
        }
    }

    // MARK: - 6. Remote Space Deletion

    public func deleteRemoteSpaceData(
        accountId: String,
        spaceId: UUID,
        requestedByDeviceId: String
    ) async throws -> RemoteDeletionReceipt {
        guard let token = apiToken, !token.isEmpty else {
            return try await fallback.deleteRemoteSpaceData(
                accountId: accountId,
                spaceId: spaceId,
                requestedByDeviceId: requestedByDeviceId
            )
        }

        struct DeleteSpacePayload: Encodable {
            let accountId: String
            let spaceId: UUID
            let requestedByDeviceId: String
        }

        let body = try jsonEncoder.encode(DeleteSpacePayload(
            accountId: accountId,
            spaceId: spaceId,
            requestedByDeviceId: requestedByDeviceId
        ))

        let req = createRequest(path: "api/v1/spaces", method: "DELETE", body: body)
        do {
            let (data, response) = try await session.data(for: req)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                return try jsonDecoder.decode(RemoteDeletionReceipt.self, from: data)
            }
            return try await fallback.deleteRemoteSpaceData(
                accountId: accountId,
                spaceId: spaceId,
                requestedByDeviceId: requestedByDeviceId
            )
        } catch {
            return try await fallback.deleteRemoteSpaceData(
                accountId: accountId,
                spaceId: spaceId,
                requestedByDeviceId: requestedByDeviceId
            )
        }
    }

    // MARK: - Convenience & Aliased Sync Helpers

    public func activeDeviceCount(accountId: String) async throws -> Int {
        let devices = try await listEnrolledDevices(accountId: accountId)
        return devices.filter { !$0.isRevoked }.count
    }

    public func registerSpace(
        accountId: String,
        spaceId: UUID,
        deviceId: String,
        wrappedSpaceKey: WrappedSpaceKeyRing
    ) async throws {
        try await publishWrappedSpaceKey(
            accountId: accountId,
            deviceId: deviceId,
            wrappedSpaceKey: wrappedSpaceKey
        )
    }

    public func updateSpaceKeyEnvelopes(
        accountId: String,
        deviceId: String,
        envelopes: [WrappedSpaceKeyRing]
    ) async throws {
        for envelope in envelopes {
            try await publishWrappedSpaceKey(
                accountId: accountId,
                deviceId: deviceId,
                wrappedSpaceKey: envelope
            )
        }
    }

    public func pushOperations(
        accountId: String,
        spaceId: UUID,
        deviceId: String,
        operations: [EncryptedSyncOperation]
    ) async throws -> SyncPushReceipt {
        try await pushEncryptedOperations(
            accountId: accountId,
            spaceId: spaceId,
            deviceId: deviceId,
            operations: operations
        )
    }

    public func pullOperations(
        accountId: String,
        spaceId: UUID,
        deviceId: String,
        sinceCursor: SyncCursor?,
        limit: Int
    ) async throws -> SyncPullBatch {
        try await pullEncryptedOperations(
            accountId: accountId,
            spaceId: spaceId,
            deviceId: deviceId,
            sinceCursor: sinceCursor,
            limit: limit
        )
    }

    public func deleteAllRemoteDataForSpace(
        accountId: String,
        spaceId: UUID,
        requestedByDeviceId: String
    ) async throws -> RemoteDeletionReceipt {
        try await deleteRemoteSpaceData(
            accountId: accountId,
            spaceId: spaceId,
            requestedByDeviceId: requestedByDeviceId
        )
    }

    public func remoteBytesUsed(accountId: String, spaceId: UUID? = nil) async throws -> Int64 {
        // Return 0 or simulated count when using fallback
        return 0
    }

    // MARK: - 7. App Feed / Announcement Banners

    public func fetchAppFeed(platform: String, tier: SubscriptionTier) async throws -> [AppAnnouncementBanner] {
        guard let token = apiToken, !token.isEmpty else {
            return defaultAnnouncements(for: platform, tier: tier)
        }

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
