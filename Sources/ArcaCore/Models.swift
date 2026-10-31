import Foundation

// MARK: - Storage Mode & Privacy Configuration

/// Per-Space storage mode.
/// Arca supports Local-only and Arca Sync first, with optional Personal Cloud Backup adapters
/// gated behind explicit provider policy verification.
public enum SpaceStorageMode: String, Codable, CaseIterable, Sendable, Equatable {
    case arcaSync = "arca_sync"
    case localOnly = "local_only"
    case personalCloudBackup = "personal_cloud_backup"

    public var displayNameKey: String {
        switch self {
        case .arcaSync: return "storage.mode.arcaSync.title"
        case .localOnly: return "storage.mode.localOnly.title"
        case .personalCloudBackup: return "storage.mode.personalCloud.title"
        }
    }

    public var summaryKey: String {
        switch self {
        case .arcaSync: return "storage.mode.arcaSync.summary"
        case .localOnly: return "storage.mode.localOnly.summary"
        case .personalCloudBackup: return "storage.mode.personalCloud.summary"
        }
    }
}

/// Optional personal-cloud provider identifiers (backup-first, separated from sync).
public enum PersonalCloudProvider: String, Codable, CaseIterable, Sendable, Equatable {
    case iCloudDrive = "icloud_drive"
    case googleDrive = "google_drive"

    public var displayName: String {
        switch self {
        case .iCloudDrive: return "iCloud Drive"
        case .googleDrive: return "Google Drive"
        }
    }
}

/// Classification of sensitivity for templates and collections.
/// Note: Arca is a general-purpose personal records app with user-defined schemas.
/// Entering health information does not make the entire app a regulated healthcare app,
/// nor does client-side encryption automatically create an exemption from provider terms.
public enum SensitivityPosture: String, Codable, Sendable, Equatable {
    /// General collection, defaults to user's preferred default mode (Arca Sync if accepted, or Local-only).
    case standard = "standard"
    /// Sensitive template (e.g., Medical Visits), defaults to Local-only with clear explanation before creation.
    case elevatedLocalDefault = "elevated_local_default"
}

// MARK: - Space (Database)

/// A Space represents an independent database for an area of life (e.g., Personal, Vehicles, Home).
/// Each Space is stored in its own independent SQLite file (`Spaces/<id>/space.sqlite`).
public struct SpaceMetadata: Identifiable, Codable, Sendable, Equatable, Hashable {
    public let id: UUID
    public var name: String
    public var iconName: String
    public var accentHex: String
    public var storageMode: SpaceStorageMode
    public var cloudSyncAcceptedAt: Date?
    public var personalCloudProvider: PersonalCloudProvider?
    public var containsSensitiveHealthTemplate: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var revision: Int64

    public init(
        id: UUID = UUID(),
        name: String,
        iconName: String = "folder.fill",
        accentHex: String = "#2B5B84",
        storageMode: SpaceStorageMode = .localOnly,
        cloudSyncAcceptedAt: Date? = nil,
        personalCloudProvider: PersonalCloudProvider? = nil,
        containsSensitiveHealthTemplate: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        revision: Int64 = 1
    ) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.accentHex = accentHex
        self.storageMode = storageMode
        self.cloudSyncAcceptedAt = cloudSyncAcceptedAt
        self.personalCloudProvider = personalCloudProvider
        self.containsSensitiveHealthTemplate = containsSensitiveHealthTemplate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revision = revision
    }
}

// MARK: - Precise Money & Date Types

/// Exact money value represented in integer minor units (e.g. cents) + ISO 4217 currency code.
/// Never uses binary floating-point to store monetary amounts.
public struct MoneyValue: Codable, Sendable, Equatable, Hashable {
    public var minorUnits: Int64
    public var currencyCode: String
    public var fractionDigits: Int

    public init(minorUnits: Int64, currencyCode: String = "USD", fractionDigits: Int = 2) {
        self.minorUnits = minorUnits
        self.currencyCode = currencyCode.uppercased()
        self.fractionDigits = max(0, min(4, fractionDigits))
    }

    public init?(decimalString: String, currencyCode: String = "USD", fractionDigits: Int = 2) {
        let cleaned = decimalString.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty else { return nil }
        let parts = cleaned.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }
        let isNegative = cleaned.hasPrefix("-")
        let wholeString = parts[0].replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "+", with: "")
        let wholeUnits = Int64(wholeString.isEmpty ? "0" : wholeString) ?? -1
        guard wholeUnits >= 0 else { return nil }

        var multiplier: Int64 = 1
        for _ in 0..<fractionDigits { multiplier *= 10 }

        var fracUnits: Int64 = 0
        if parts.count == 2 {
            var fracStr = String(parts[1])
            if fracStr.count > fractionDigits {
                fracStr = String(fracStr.prefix(fractionDigits))
            } else {
                while fracStr.count < fractionDigits {
                    fracStr.append("0")
                }
            }
            guard let parsedFrac = Int64(fracStr.isEmpty ? "0" : fracStr), parsedFrac >= 0 else { return nil }
            fracUnits = parsedFrac
        }

        let combined = wholeUnits * multiplier + fracUnits
        self.minorUnits = isNegative ? -combined : combined
        self.currencyCode = currencyCode.uppercased()
        self.fractionDigits = fractionDigits
    }

    public var decimalValue: Decimal {
        var multiplier = Decimal(1)
        for _ in 0..<fractionDigits { multiplier *= 10 }
        return Decimal(minorUnits) / multiplier
    }

    public var doubleApproximationForChartsOnly: Double {
        let divisor = pow(10.0, Double(fractionDigits))
        return Double(minorUnits) / divisor
    }

    public func formatted(locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.locale = locale
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        return formatter.string(from: decimalValue as NSDecimalNumber) ?? "\(currencyCode) \(decimalValue)"
    }
}

/// Timezone-independent calendar date (`YYYY-MM-DD`) so date-only fields (e.g., warranty expiration,
/// visit date) never shift across time zones.
public struct CalendarDate: Codable, Sendable, Equatable, Hashable, Comparable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = max(1, min(12, month))
        self.day = max(1, min(31, day))
    }

    public init(date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = comps.year ?? 2026
        self.month = comps.month ?? 1
        self.day = comps.day ?? 1
    }

    public init?(isoDateString: String) {
        let parts = isoDateString.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]),
              let m = Int(parts[1]),
              let d = Int(parts[2]),
              (1...12).contains(m),
              (1...31).contains(d) else {
            return nil
        }
        self.year = y
        self.month = m
        self.day = d
    }

    public var isoString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public func toDate(in timeZone: TimeZone = .current) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 12
        return cal.date(from: comps) ?? Date()
    }

    public func formatted(locale: Locale = .current, style: DateFormatter.Style = .medium) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = style
        formatter.timeStyle = .none
        return formatter.string(from: toDate())
    }

    public static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }
}

// MARK: - Dynamic Field & Schema Definitions

/// All 11 required initial field types.
public enum FieldType: String, Codable, CaseIterable, Sendable, Equatable {
    case shortText = "short_text"
    case longText = "long_text"
    case number = "number"
    case currency = "currency"
    case date = "date"
    case dateTime = "date_time"
    case boolean = "boolean"
    case singleSelect = "single_select"
    case multiSelect = "multi_select"
    case rating = "rating"
    case attachment = "attachment"

    public var iconName: String {
        switch self {
        case .shortText: return "textformat"
        case .longText: return "text.alignleft"
        case .number: return "number"
        case .currency: return "dollarsign.circle"
        case .date: return "calendar"
        case .dateTime: return "clock.badge"
        case .boolean: return "checkmark.square"
        case .singleSelect: return "list.bullet.circle"
        case .multiSelect: return "checklist"
        case .rating: return "star.fill"
        case .attachment: return "paperclip"
        }
    }

    public var displayNameKey: String {
        "field.type.\(rawValue)"
    }
}

/// Option item for `singleSelect` and `multiSelect` fields.
/// Uses a stable `id` so renaming an option label does not break stored values.
public struct SelectOption: Identifiable, Codable, Sendable, Equatable, Hashable {
    public let id: String
    public var label: String
    public var colorHex: String?

    public init(id: String = UUID().uuidString, label: String, colorHex: String? = nil) {
        self.id = id
        self.label = label
        self.colorHex = colorHex
    }
}

/// Validation and configuration rules for a field.
public struct FieldValidationRules: Codable, Sendable, Equatable, Hashable {
    public var minNumber: Double?
    public var maxNumber: Double?
    public var maxRating: Int
    public var defaultCurrencyCode: String
    public var maxTextLength: Int?

    public init(
        minNumber: Double? = nil,
        maxNumber: Double? = nil,
        maxRating: Int = 5,
        defaultCurrencyCode: String = "USD",
        maxTextLength: Int? = nil
    ) {
        self.minNumber = minNumber
        self.maxNumber = maxNumber
        self.maxRating = max(1, min(10, maxRating))
        self.defaultCurrencyCode = defaultCurrencyCode
        self.maxTextLength = maxTextLength
    }
}

/// Definition of a single field within a Collection schema.
/// `id` is immutable; `label` is display-only and can be renamed freely without mutating record payloads.
public struct FieldDefinition: Identifiable, Codable, Sendable, Equatable, Hashable {
    public let id: UUID
    public var label: String
    public var type: FieldType
    public var isRequired: Bool
    public var sortOrder: Int
    public var options: [SelectOption]
    public var defaultValue: FieldValue?
    public var validation: FieldValidationRules
    public var isPrimaryTitle: Bool
    public var isArchived: Bool
    public var archivedAt: Date?

    public init(
        id: UUID = UUID(),
        label: String,
        type: FieldType,
        isRequired: Bool = false,
        sortOrder: Int = 0,
        options: [SelectOption] = [],
        defaultValue: FieldValue? = nil,
        validation: FieldValidationRules = FieldValidationRules(),
        isPrimaryTitle: Bool = false,
        isArchived: Bool = false,
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.label = label
        self.type = type
        self.isRequired = isRequired
        self.sortOrder = sortOrder
        self.options = options
        self.defaultValue = defaultValue
        self.validation = validation
        self.isPrimaryTitle = isPrimaryTitle
        self.isArchived = isArchived
        self.archivedAt = archivedAt
    }
}

/// Policy explaining how removed fields are retained and recovered.
public enum FieldRetentionPolicy: String, Codable, Sendable, Equatable {
    /// Default safe policy: soft-archive the field definition and retain existing values in records
    /// so the user can restore the field without data loss, or permanently purge later.
    case archiveAndRetainValues = "archive_and_retain"
    /// Explicit destructive action requested by user after warning confirmation.
    case permanentlyPurgeValues = "permanently_purge"
}

/// Versioned runtime schema for a user-created or template-created Collection.
public struct CollectionSchema: Identifiable, Codable, Sendable, Equatable, Hashable {
    public let id: UUID
    public let spaceId: UUID
    public var name: String
    public var iconName: String
    public var colorHex: String
    public var schemaVersion: Int
    public var sensitivityPosture: SensitivityPosture
    public var fields: [FieldDefinition]
    public var createdAt: Date
    public var updatedAt: Date
    public var revision: Int64
    public var isDeleted: Bool

    public init(
        id: UUID = UUID(),
        spaceId: UUID,
        name: String,
        iconName: String = "list.clipboard",
        colorHex: String = "#2B5B84",
        schemaVersion: Int = 1,
        sensitivityPosture: SensitivityPosture = .standard,
        fields: [FieldDefinition] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        revision: Int64 = 1,
        isDeleted: Bool = false
    ) {
        self.id = id
        self.spaceId = spaceId
        self.name = name
        self.iconName = iconName
        self.colorHex = colorHex
        self.schemaVersion = schemaVersion
        self.sensitivityPosture = sensitivityPosture
        self.fields = fields.sorted(by: { $0.sortOrder < $1.sortOrder })
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revision = revision
        self.isDeleted = isDeleted
    }

    public var activeFields: [FieldDefinition] {
        fields.filter { !$0.isArchived }.sorted { $0.sortOrder < $1.sortOrder }
    }

    public var archivedFields: [FieldDefinition] {
        fields.filter { $0.isArchived }.sorted { $0.sortOrder < $1.sortOrder }
    }

    public var primaryTitleField: FieldDefinition? {
        activeFields.first(where: { $0.isPrimaryTitle }) ?? activeFields.first(where: { $0.type == .shortText }) ?? activeFields.first
    }
}

// MARK: - Attachment Reference

/// Metadata for a photo or file attached to a record.
/// Content is stored on disk inside the Space's attachment directory and verified by SHA-256 digest.
public struct AttachmentReference: Identifiable, Codable, Sendable, Equatable, Hashable {
    public let id: UUID
    public var filename: String
    public var mimeType: String
    public var byteSize: Int64
    public var sha256Hex: String
    public var localRelativePath: String
    public var uploadState: AttachmentSyncState
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        filename: String,
        mimeType: String,
        byteSize: Int64,
        sha256Hex: String,
        localRelativePath: String,
        uploadState: AttachmentSyncState = .localOnly,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.byteSize = byteSize
        self.sha256Hex = sha256Hex
        self.localRelativePath = localRelativePath
        self.uploadState = uploadState
        self.createdAt = createdAt
    }
}

public enum AttachmentSyncState: String, Codable, Sendable, Equatable, Hashable {
    case localOnly = "local_only"
    case pendingUpload = "pending_upload"
    case uploading = "uploading"
    case uploadedVerified = "uploaded_verified"
    case uploadFailed = "upload_failed"
}

// MARK: - Typed Field Value with Explicit Null Handling

/// Strongly typed runtime value stored for a `FieldDefinition`.
public enum FieldValue: Codable, Sendable, Equatable, Hashable {
    case null
    case shortText(String)
    case longText(String)
    case number(Double)
    case currency(MoneyValue)
    case date(CalendarDate)
    case dateTime(Date)
    case boolean(Bool)
    case singleSelect(String)
    case multiSelect([String])
    case rating(Int)
    case attachments([AttachmentReference])

    public var isNullOrEmpty: Bool {
        switch self {
        case .null:
            return true
        case .shortText(let s), .longText(let s), .singleSelect(let s):
            return s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .multiSelect(let arr):
            return arr.isEmpty
        case .attachments(let atts):
            return atts.isEmpty
        case .number, .currency, .date, .dateTime, .boolean, .rating:
            return false
        }
    }

    public func plainTextSummary(for field: FieldDefinition? = nil, locale: Locale = .current) -> String {
        switch self {
        case .null:
            return ""
        case .shortText(let s), .longText(let s):
            return s
        case .number(let n):
            let formatter = NumberFormatter()
            formatter.locale = locale
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 4
            return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
        case .currency(let money):
            return money.formatted(locale: locale)
        case .date(let calDate):
            return calDate.formatted(locale: locale)
        case .dateTime(let dt):
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: dt)
        case .boolean(let b):
            return b ? "Yes" : "No"
        case .singleSelect(let optionId):
            if let match = field?.options.first(where: { $0.id == optionId || $0.label == optionId }) {
                return match.label
            }
            return optionId
        case .multiSelect(let optionIds):
            let labels = optionIds.map { id in
                field?.options.first(where: { $0.id == id || $0.label == id })?.label ?? id
            }
            return labels.joined(separator: ", ")
        case .rating(let stars):
            return String(repeating: "★", count: max(0, stars))
        case .attachments(let refs):
            return "\(refs.count) attachment\(refs.count == 1 ? "" : "s")"
        }
    }
}

// MARK: - Record Entry

/// A single user record inside a Collection.
public struct RecordItem: Identifiable, Codable, Sendable, Equatable, Hashable {
    public let id: UUID
    public let spaceId: UUID
    public let collectionId: UUID
    public var schemaVersionAtWrite: Int
    /// Keyed by `FieldDefinition.id` (UUID string) so renaming a field never alters stored keys.
    public var values: [UUID: FieldValue]
    public var isFavorite: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var revision: Int64
    public var lastModifiedByDeviceId: String
    public var isDeleted: Bool

    public init(
        id: UUID = UUID(),
        spaceId: UUID,
        collectionId: UUID,
        schemaVersionAtWrite: Int = 1,
        values: [UUID: FieldValue] = [:],
        isFavorite: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        revision: Int64 = 1,
        lastModifiedByDeviceId: String = "local-device",
        isDeleted: Bool = false
    ) {
        self.id = id
        self.spaceId = spaceId
        self.collectionId = collectionId
        self.schemaVersionAtWrite = schemaVersionAtWrite
        self.values = values
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revision = revision
        self.lastModifiedByDeviceId = lastModifiedByDeviceId
        self.isDeleted = isDeleted
    }

    public func title(using schema: CollectionSchema) -> String {
        if let titleField = schema.primaryTitleField,
           let val = values[titleField.id],
           !val.isNullOrEmpty {
            return val.plainTextSummary(for: titleField)
        }
        for field in schema.activeFields {
            if let val = values[field.id], !val.isNullOrEmpty {
                return val.plainTextSummary(for: field)
            }
        }
        return "Untitled Record"
    }

    public func subtitle(using schema: CollectionSchema, locale: Locale = .current) -> String {
        let primaryId = schema.primaryTitleField?.id
        var parts: [String] = []
        for field in schema.activeFields where field.id != primaryId {
            if let val = values[field.id], !val.isNullOrEmpty {
                let text = val.plainTextSummary(for: field, locale: locale)
                if !text.isEmpty {
                    parts.append("\(field.label): \(text)")
                }
            }
            if parts.count >= 2 { break }
        }
        return parts.joined(separator: " • ")
    }

    public var allAttachments: [AttachmentReference] {
        var result: [AttachmentReference] = []
        for (_, val) in values {
            if case .attachments(let refs) = val {
                result.append(contentsOf: refs)
            }
        }
        return result
    }

    /// Creates a duplicate copy of this record with a new stable UUID and reset revision.
    public func duplicated(byDeviceId deviceId: String = "local-device", titleSuffix: String = " (Copy)") -> RecordItem {
        var clonedValues = values
        for (key, value) in clonedValues {
            if case .shortText(let text) = value {
                clonedValues[key] = .shortText(text + titleSuffix)
                break
            }
        }
        return RecordItem(
            id: UUID(),
            spaceId: spaceId,
            collectionId: collectionId,
            schemaVersionAtWrite: schemaVersionAtWrite,
            values: clonedValues,
            isFavorite: isFavorite,
            createdAt: Date(),
            updatedAt: Date(),
            revision: 1,
            lastModifiedByDeviceId: deviceId,
            isDeleted: false
        )
    }
}
