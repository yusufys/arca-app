import Foundation

/// Nil on legacy models means an ordinary field. Sensitive choices default to local storage.
public enum SensitiveDataPrivacy: String, Codable, Sendable, Hashable {
    case localOnly = "sensitive_local_only"
    case syncWithConsent = "sensitive_sync_with_consent"
}

/// This policy contains identifiers only: excluded labels, defaults and values never leave the device.
public struct CollectionCloudPrivacyRule: Codable, Sendable, Equatable, Hashable {
    public let collectionId: UUID
    public var changeId: UUID?
    public var localOnly: Bool
    public var excludedFieldIds: Set<UUID>
    public init(collectionId: UUID, localOnly: Bool, excludedFieldIds: Set<UUID>) {
        self.collectionId = collectionId; self.localOnly = localOnly; self.excludedFieldIds = excludedFieldIds
    }
}

public enum CloudPrivacyPolicy {
    public static func isCollectionLocalOnly(_ schema: CollectionSchema) -> Bool {
        schema.privacy == .localOnly || (schema.privacy == nil && schema.sensitivityPosture == .elevatedLocalDefault)
    }

    public static func rule(for schema: CollectionSchema) -> CollectionCloudPrivacyRule {
        CollectionCloudPrivacyRule(collectionId: schema.id, localOnly: isCollectionLocalOnly(schema),
            excludedFieldIds: Set(schema.fields.filter { $0.privacy == .localOnly }.map(\.id)))
    }

    public static func schemaForCloud(_ schema: CollectionSchema) -> CollectionSchema? {
        guard !isCollectionLocalOnly(schema) else { return nil }
        var result = schema
        result.fields.removeAll { $0.privacy == .localOnly }
        return result
    }

    public static func recordForCloud(_ record: RecordItem, schema: CollectionSchema) -> RecordItem? {
        guard !isCollectionLocalOnly(schema), record.collectionId == schema.id, record.spaceId == schema.spaceId else { return nil }
        var result = record
        let permitted = Set(schema.fields.filter { $0.privacy != .localOnly }.map(\.id))
        result.values = record.values.filter { permitted.contains($0.key) }
        return result
    }

    public static func applyingRule(_ rule: CollectionCloudPrivacyRule, to schema: CollectionSchema) -> CollectionSchema {
        guard rule.collectionId == schema.id else { return schema }
        var result = schema
        if rule.localOnly { result.privacy = .localOnly }
        for index in result.fields.indices where rule.excludedFieldIds.contains(result.fields[index].id) { result.fields[index].privacy = .localOnly }
        return result
    }

    /// Remote schemas cannot erase a private definition or grant consent on this device.
    public static func mergingRemoteSchema(_ remote: CollectionSchema, local: CollectionSchema?) -> CollectionSchema {
        guard let local else { return remote }
        if isCollectionLocalOnly(local) { return local }
        var merged = remote
        merged.privacy = local.privacy
        let privateFields = local.fields.filter { $0.privacy == .localOnly }
        let privateIds = Set(privateFields.map(\.id))
        merged.fields.removeAll { privateIds.contains($0.id) }
        merged.fields.append(contentsOf: privateFields)
        // A pending local approval must retain a definition omitted by an earlier sanitized schema.
        for approved in local.fields where approved.privacy == .syncWithConsent {
            if let index = merged.fields.firstIndex(where: { $0.id == approved.id }) {
                merged.fields[index].privacy = approved.privacy
            } else { merged.fields.append(approved) }
        }
        return merged
    }

    public static func preservingLocalValues(in remote: RecordItem, local: RecordItem?, schema: CollectionSchema) -> RecordItem {
        guard let local else { return remote }
        if isCollectionLocalOnly(schema) { return local }
        var merged = remote
        for field in schema.fields where field.privacy == .localOnly {
            merged.values[field.id] = local.values[field.id]
        }
        return merged
    }

    public static func resettingConsent(_ schema: CollectionSchema) -> CollectionSchema {
        var result = schema
        if result.privacy != nil { result.privacy = .localOnly }
        for index in result.fields.indices where result.fields[index].privacy != nil { result.fields[index].privacy = .localOnly }
        return result
    }
}
