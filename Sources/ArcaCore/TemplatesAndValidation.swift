import Foundation

// MARK: - Starter Templates

public enum StarterTemplateID: String, CaseIterable, Codable, Sendable, Identifiable {
    case vehicleMaintenance = "vehicle_maintenance"
    case homeInventory = "home_inventory"
    case warranties = "warranties"
    case medicalVisits = "medical_visits"

    public var id: String { rawValue }
}

public struct StarterTemplate: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let subtitle: String
    public let iconName: String
    public let colorHex: String
    public let sensitivityPosture: SensitivityPosture
    public let sensitivityDisclosure: String?
    public let recommendedStorageMode: SpaceStorageMode
    public let fields: [FieldDefinition]

    public init(id: String, name: String, subtitle: String, iconName: String, colorHex: String,
                sensitivityPosture: SensitivityPosture = .standard, sensitivityDisclosure: String? = nil,
                recommendedStorageMode: SpaceStorageMode = .arcaSync, fields: [FieldDefinition]) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.iconName = iconName
        self.colorHex = colorHex
        self.sensitivityPosture = sensitivityPosture
        self.sensitivityDisclosure = sensitivityDisclosure
        self.recommendedStorageMode = recommendedStorageMode
        self.fields = fields
    }

    public func instantiateSchema(for spaceId: UUID) -> CollectionSchema {
        let clonedFields = fields.enumerated().map { index, field in
            FieldDefinition(
                id: UUID(),
                label: field.label,
                type: field.type,
                isRequired: field.isRequired,
                sortOrder: index,
                options: field.options,
                defaultValue: field.defaultValue,
                validation: field.validation,
                isPrimaryTitle: field.isPrimaryTitle,
                privacy: field.privacy == nil ? nil : .localOnly
            )
        }
        return CollectionSchema(
            id: UUID(),
            spaceId: spaceId,
            name: name,
            iconName: iconName,
            colorHex: colorHex,
            schemaVersion: 1,
            sensitivityPosture: sensitivityPosture,
            privacy: sensitivityPosture == .elevatedLocalDefault ? .localOnly : nil,
            fields: clonedFields
        )
    }
}

public enum StarterTemplateCatalog {
    public static let all: [StarterTemplate] = [
        vehicleMaintenance,
        homeInventory,
        warranties,
        medicalVisits
    ]

    /// Legacy demo fixtures for verification. The live iOS gallery reads its catalog from the backend.
    public static let visibleDemos = all.filter { $0.id != StarterTemplateID.medicalVisits.rawValue }

    public static func template(for id: StarterTemplateID) -> StarterTemplate {
        switch id {
        case .vehicleMaintenance: return vehicleMaintenance
        case .homeInventory: return homeInventory
        case .warranties: return warranties
        case .medicalVisits: return medicalVisits
        }
    }

    public static let vehicleMaintenance = StarterTemplate(
        id: StarterTemplateID.vehicleMaintenance.rawValue,
        name: "Vehicle Maintenance",
        subtitle: "Service history, mileage, parts replaced, and shop receipts.",
        iconName: "car.fill",
        colorHex: "#2B5B84",
        sensitivityPosture: .standard,
        sensitivityDisclosure: nil,
        recommendedStorageMode: .arcaSync,
        fields: [
            FieldDefinition(label: "Service Summary", type: .shortText, isRequired: true, sortOrder: 0, isPrimaryTitle: true),
            FieldDefinition(label: "Service Date", type: .date, isRequired: true, sortOrder: 1),
            FieldDefinition(label: "Odometer (mi/km)", type: .number, isRequired: false, sortOrder: 2, validation: FieldValidationRules(minNumber: 0)),
            FieldDefinition(label: "Category", type: .singleSelect, isRequired: true, sortOrder: 3, options: [
                SelectOption(id: "oil", label: "Oil & Fluids"),
                SelectOption(id: "tires", label: "Tires & Brakes"),
                SelectOption(id: "inspection", label: "Inspection"),
                SelectOption(id: "repair", label: "Repair"),
                SelectOption(id: "battery", label: "Battery & Electrical")
            ]),
            FieldDefinition(label: "Total Cost", type: .currency, isRequired: false, sortOrder: 4, validation: FieldValidationRules(defaultCurrencyCode: "USD")),
            FieldDefinition(label: "Shop or Technician", type: .shortText, isRequired: false, sortOrder: 5),
            FieldDefinition(label: "Under Warranty", type: .boolean, isRequired: false, sortOrder: 6, defaultValue: .boolean(false)),
            FieldDefinition(label: "Notes", type: .longText, isRequired: false, sortOrder: 7),
            FieldDefinition(label: "Invoices & Photos", type: .attachment, isRequired: false, sortOrder: 8)
        ]
    )

    public static let homeInventory = StarterTemplate(
        id: StarterTemplateID.homeInventory.rawValue,
        name: "Home Inventory",
        subtitle: "Valuables, serial numbers, rooms, and replacement values for peace of mind.",
        iconName: "house.fill",
        colorHex: "#3A6B5C",
        sensitivityPosture: .standard,
        sensitivityDisclosure: nil,
        recommendedStorageMode: .arcaSync,
        fields: [
            FieldDefinition(label: "Item Name", type: .shortText, isRequired: true, sortOrder: 0, isPrimaryTitle: true),
            FieldDefinition(label: "Room / Location", type: .singleSelect, isRequired: true, sortOrder: 1, options: [
                SelectOption(id: "living", label: "Living Room"),
                SelectOption(id: "kitchen", label: "Kitchen"),
                SelectOption(id: "office", label: "Home Office"),
                SelectOption(id: "bedroom", label: "Bedroom"),
                SelectOption(id: "garage", label: "Garage & Storage")
            ]),
            FieldDefinition(label: "Purchase Price", type: .currency, isRequired: false, sortOrder: 2, validation: FieldValidationRules(defaultCurrencyCode: "USD")),
            FieldDefinition(label: "Purchase Date", type: .date, isRequired: false, sortOrder: 3),
            FieldDefinition(label: "Serial / Model Number", type: .shortText, isRequired: false, sortOrder: 4),
            FieldDefinition(label: "Condition Rating", type: .rating, isRequired: false, sortOrder: 5, validation: FieldValidationRules(maxRating: 5)),
            FieldDefinition(label: "Tags", type: .multiSelect, isRequired: false, sortOrder: 6, options: [
                SelectOption(id: "electronics", label: "Electronics"),
                SelectOption(id: "appliance", label: "Appliance"),
                SelectOption(id: "furniture", label: "Furniture"),
                SelectOption(id: "insured", label: "Scheduled on Policy")
            ]),
            FieldDefinition(label: "Receipts & Photos", type: .attachment, isRequired: false, sortOrder: 7)
        ]
    )

    public static let warranties = StarterTemplate(
        id: StarterTemplateID.warranties.rawValue,
        name: "Warranties",
        subtitle: "Track coverage expiration dates, proof of purchase, and support contacts.",
        iconName: "checkmark.shield.fill",
        colorHex: "#8C5A2B",
        sensitivityPosture: .standard,
        sensitivityDisclosure: nil,
        recommendedStorageMode: .arcaSync,
        fields: [
            FieldDefinition(label: "Product Name", type: .shortText, isRequired: true, sortOrder: 0, isPrimaryTitle: true),
            FieldDefinition(label: "Brand / Manufacturer", type: .shortText, isRequired: false, sortOrder: 1),
            FieldDefinition(label: "Purchase Date", type: .date, isRequired: false, sortOrder: 2),
            FieldDefinition(label: "Expiration Date", type: .date, isRequired: true, sortOrder: 3),
            FieldDefinition(label: "Product Cost", type: .currency, isRequired: false, sortOrder: 4, validation: FieldValidationRules(defaultCurrencyCode: "USD")),
            FieldDefinition(label: "Coverage Type", type: .singleSelect, isRequired: false, sortOrder: 5, options: [
                SelectOption(id: "manufacturer", label: "Manufacturer Limited"),
                SelectOption(id: "extended", label: "Extended Plan"),
                SelectOption(id: "credit_card", label: "Credit Card Protection"),
                SelectOption(id: "lifetime", label: "Lifetime Limited")
            ]),
            FieldDefinition(label: "Active Coverage", type: .boolean, isRequired: false, sortOrder: 6, defaultValue: .boolean(true)),
            FieldDefinition(label: "Claim Instructions", type: .longText, isRequired: false, sortOrder: 7),
            FieldDefinition(label: "Receipt & Warranty Card", type: .attachment, isRequired: false, sortOrder: 8)
        ]
    )

    public static let medicalVisits = StarterTemplate(
        id: StarterTemplateID.medicalVisits.rawValue,
        name: "Medical Visits",
        subtitle: "Clinician notes, questions asked, follow-ups, and out-of-pocket costs.",
        iconName: "cross.case.fill",
        colorHex: "#7A3E58",
        sensitivityPosture: .elevatedLocalDefault,
        sensitivityDisclosure: "Medical Visits is marked as sensitive and defaults to Local-Only storage so your health notes stay strictly on this device unless you explicitly choose end-to-end encrypted Arca Sync. Custom collections with other names may also contain sensitive data—you can set any Space to Local-Only at any time.",
        recommendedStorageMode: .localOnly,
        fields: [
            FieldDefinition(label: "Visit Reason / Summary", type: .shortText, isRequired: true, sortOrder: 0, isPrimaryTitle: true),
            FieldDefinition(label: "Visit Date", type: .date, isRequired: true, sortOrder: 1),
            FieldDefinition(label: "Clinician / Facility", type: .shortText, isRequired: false, sortOrder: 2),
            FieldDefinition(label: "Specialty", type: .singleSelect, isRequired: false, sortOrder: 3, options: [
                SelectOption(id: "primary", label: "Primary Care"),
                SelectOption(id: "dental", label: "Dental"),
                SelectOption(id: "vision", label: "Vision"),
                SelectOption(id: "specialist", label: "Specialist"),
                SelectOption(id: "lab", label: "Lab / Imaging")
            ]),
            FieldDefinition(label: "Out-of-Pocket Cost", type: .currency, isRequired: false, sortOrder: 4, validation: FieldValidationRules(defaultCurrencyCode: "USD")),
            FieldDefinition(label: "Follow-up Needed", type: .boolean, isRequired: false, sortOrder: 5, defaultValue: .boolean(false)),
            FieldDefinition(label: "Key Takeaways & Instructions", type: .longText, isRequired: false, sortOrder: 6),
            FieldDefinition(label: "Visit Documents", type: .attachment, isRequired: false, sortOrder: 7)
        ]
    )
}

// MARK: - Validation & Schema Evolution Engine

public struct RecordValidationError: LocalizedError, Sendable, Equatable, Identifiable {
    public var id: String { "\(fieldId.uuidString)-\(reason)" }
    public let fieldId: UUID
    public let fieldLabel: String
    public let reason: String

    public init(fieldId: UUID, fieldLabel: String, reason: String) {
        self.fieldId = fieldId
        self.fieldLabel = fieldLabel
        self.reason = reason
    }

    public var errorDescription: String? {
        "\(fieldLabel): \(reason)"
    }
}

public struct FieldConversionPreview: Sendable, Equatable {
    public let fieldId: UUID
    public let fieldLabel: String
    public let fromType: FieldType
    public let toType: FieldType
    public let totalRecordsExamined: Int
    public let convertibleCount: Int
    public let failureCount: Int
    public let failedRecordIds: [UUID]
    public let sampleFailureDescriptions: [String]

    public var isSafeToApplyWithoutLoss: Bool {
        failureCount == 0
    }
}

public enum SchemaEngine {

    /// Validates a candidate record's values against the active `CollectionSchema`.
    public static func validate(
        values: [UUID: FieldValue],
        against schema: CollectionSchema,
        locale: Locale = Locale(identifier: "en")
    ) -> [RecordValidationError] {
        let code = locale.language.languageCode?.identifier ?? "en"
        let bundle = Bundle.module.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .module
        var errors: [RecordValidationError] = []
        for field in schema.activeFields {
            let value = values[field.id] ?? .null
            if field.isRequired && value.isNullOrEmpty {
                errors.append(RecordValidationError(
                    fieldId: field.id,
                    fieldLabel: field.label,
                    reason: String(localized: "This field is required.", bundle: bundle, locale: locale)
                ))
                continue
            }
            guard !value.isNullOrEmpty else { continue }

            switch (field.type, value) {
            case (.shortText, .shortText(let text)), (.longText, .longText(let text)):
                if let maxLen = field.validation.maxTextLength, text.count > maxLen {
                    errors.append(RecordValidationError(
                        fieldId: field.id,
                        fieldLabel: field.label,
                        reason: String(format: String(localized: "Use no more than %d characters.", bundle: bundle, locale: locale), locale: locale, maxLen)
                    ))
                }
            case (.number, .number(let num)):
                if let min = field.validation.minNumber, num < min {
                    errors.append(RecordValidationError(
                        fieldId: field.id,
                        fieldLabel: field.label,
                        reason: String(format: String(localized: "Must be at least %@.", bundle: bundle, locale: locale), min.formatted(.number.locale(locale)))
                    ))
                }
                if let max = field.validation.maxNumber, num > max {
                    errors.append(RecordValidationError(
                        fieldId: field.id,
                        fieldLabel: field.label,
                        reason: String(format: String(localized: "Must be at most %@.", bundle: bundle, locale: locale), max.formatted(.number.locale(locale)))
                    ))
                }
            case (.rating, .rating(let stars)):
                if stars < 0 || stars > field.validation.maxRating {
                    errors.append(RecordValidationError(
                        fieldId: field.id,
                        fieldLabel: field.label,
                        reason: String(format: String(localized: "Rating must be between 0 and %d.", bundle: bundle, locale: locale), locale: locale, field.validation.maxRating)
                    ))
                }
            case (.image, .attachments(let images)):
                if images.count > 1 || images.contains(where: { !$0.mimeType.hasPrefix("image/") || $0.byteSize <= 0 || $0.byteSize > 5 * 1024 * 1024 }) {
                    errors.append(RecordValidationError(fieldId: field.id, fieldLabel: field.label,
                        reason: String(localized: "Choose one image up to 5 MB for this field.", bundle: bundle, locale: locale)))
                }
            case (.currency, .currency),
                 (.date, .date),
                 (.dateTime, .dateTime),
                 (.boolean, .boolean),
                 (.singleSelect, .singleSelect),
                 (.multiSelect, .multiSelect),
                 (.attachment, .attachments):
                break
            default:
                errors.append(RecordValidationError(
                    fieldId: field.id,
                    fieldLabel: field.label,
                    reason: String(localized: "Value does not match the field type.", bundle: bundle, locale: locale)
                ))
            }
        }
        return errors
    }

    /// Renames a field while preserving its stable UUID, bumping `schemaVersion`, and leaving all record payloads intact.
    public static func renameField(
        in schema: CollectionSchema,
        fieldId: UUID,
        newLabel: String
    ) -> CollectionSchema {
        var updated = schema
        guard let idx = updated.fields.firstIndex(where: { $0.id == fieldId }) else { return schema }
        let trimmed = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return schema }
        updated.fields[idx].label = trimmed
        updated.schemaVersion += 1
        updated.revision += 1
        updated.updatedAt = Date()
        return updated
    }

    /// Reorders active fields deterministically and increments `schemaVersion`.
    public static func reorderFields(
        in schema: CollectionSchema,
        orderedFieldIds: [UUID]
    ) -> CollectionSchema {
        var updated = schema
        var nextOrder = 0
        for id in orderedFieldIds {
            if let idx = updated.fields.firstIndex(where: { $0.id == id }) {
                updated.fields[idx].sortOrder = nextOrder
                nextOrder += 1
            }
        }
        for idx in updated.fields.indices where !orderedFieldIds.contains(updated.fields[idx].id) {
            updated.fields[idx].sortOrder = nextOrder
            nextOrder += 1
        }
        updated.fields.sort { $0.sortOrder < $1.sortOrder }
        updated.schemaVersion += 1
        updated.revision += 1
        updated.updatedAt = Date()
        return updated
    }

    /// Removes or archives a field according to the explicit retention policy.
    /// By default (`archiveAndRetainValues`), the field is marked archived so existing record values remain recoverable.
    public static func removeField(
        in schema: CollectionSchema,
        fieldId: UUID,
        policy: FieldRetentionPolicy,
        records: [RecordItem]
    ) -> (schema: CollectionSchema, records: [RecordItem]) {
        var updatedSchema = schema
        var updatedRecords = records

        switch policy {
        case .archiveAndRetainValues:
            if let idx = updatedSchema.fields.firstIndex(where: { $0.id == fieldId }) {
                updatedSchema.fields[idx].isArchived = true
                updatedSchema.fields[idx].archivedAt = Date()
                updatedSchema.schemaVersion += 1
                updatedSchema.revision += 1
                updatedSchema.updatedAt = Date()
            }
        case .permanentlyPurgeValues:
            updatedSchema.fields.removeAll { $0.id == fieldId }
            updatedSchema.schemaVersion += 1
            updatedSchema.revision += 1
            updatedSchema.updatedAt = Date()
            for i in updatedRecords.indices {
                if updatedRecords[i].values.removeValue(forKey: fieldId) != nil {
                    updatedRecords[i].revision += 1
                    updatedRecords[i].updatedAt = Date()
                }
            }
        }
        return (updatedSchema, updatedRecords)
    }

    /// Restores a previously archived field, immediately exposing all preserved historical record values.
    public static func restoreArchivedField(
        in schema: CollectionSchema,
        fieldId: UUID
    ) -> CollectionSchema {
        var updated = schema
        guard let idx = updated.fields.firstIndex(where: { $0.id == fieldId }) else { return schema }
        updated.fields[idx].isArchived = false
        updated.fields[idx].archivedAt = nil
        updated.schemaVersion += 1
        updated.revision += 1
        updated.updatedAt = Date()
        return updated
    }

    /// Previews converting a field from its current type to `targetType` across existing records without mutating data.
    public static func previewFieldTypeConversion(
        field: FieldDefinition,
        targetType: FieldType,
        records: [RecordItem]
    ) -> FieldConversionPreview {
        var convertible = 0
        var failures = 0
        var failedIds: [UUID] = []
        var sampleReasons: [String] = []

        for record in records where !record.isDeleted {
            let currentVal = record.values[field.id] ?? .null
            if currentVal.isNullOrEmpty {
                convertible += 1
                continue
            }
            if convertValue(currentVal, from: field.type, to: targetType, validation: field.validation) != nil {
                convertible += 1
            } else {
                failures += 1
                failedIds.append(record.id)
                if sampleReasons.count < 5 {
                    sampleReasons.append("Record \(record.id.uuidString.prefix(8)): incompatible \(field.type.rawValue) value for \(targetType.rawValue)")
                }
            }
        }

        return FieldConversionPreview(
            fieldId: field.id,
            fieldLabel: field.label,
            fromType: field.type,
            toType: targetType,
            totalRecordsExamined: convertible + failures,
            convertibleCount: convertible,
            failureCount: failures,
            failedRecordIds: failedIds,
            sampleFailureDescriptions: sampleReasons
        )
    }

    /// Applies a field type conversion ONLY if all non-null values convert cleanly, never silently discarding data.
    public static func applyFieldTypeConversion(
        in schema: CollectionSchema,
        fieldId: UUID,
        targetType: FieldType,
        records: [RecordItem]
    ) throws -> (schema: CollectionSchema, records: [RecordItem]) {
        guard let fieldIdx = schema.fields.firstIndex(where: { $0.id == fieldId }) else {
            throw SchemaMigrationError.fieldNotFound
        }
        let field = schema.fields[fieldIdx]
        let preview = previewFieldTypeConversion(field: field, targetType: targetType, records: records)
        guard preview.isSafeToApplyWithoutLoss else {
            throw SchemaMigrationError.conversionWouldLoseData(preview)
        }

        var updatedSchema = schema
        updatedSchema.fields[fieldIdx].type = targetType
        updatedSchema.schemaVersion += 1
        updatedSchema.revision += 1
        updatedSchema.updatedAt = Date()

        var updatedRecords = records
        for i in updatedRecords.indices where !updatedRecords[i].isDeleted {
            let currentVal = updatedRecords[i].values[fieldId] ?? .null
            if currentVal.isNullOrEmpty { continue }
            if let converted = convertValue(currentVal, from: field.type, to: targetType, validation: field.validation) {
                updatedRecords[i].values[fieldId] = converted
                updatedRecords[i].schemaVersionAtWrite = updatedSchema.schemaVersion
                updatedRecords[i].revision += 1
                updatedRecords[i].updatedAt = Date()
            }
        }
        return (updatedSchema, updatedRecords)
    }

    /// Attempts deterministic, lossless conversion between two `FieldType` representations.
    public static func convertValue(
        _ value: FieldValue,
        from sourceType: FieldType,
        to targetType: FieldType,
        validation: FieldValidationRules = FieldValidationRules()
    ) -> FieldValue? {
        if sourceType == targetType { return value }
        if value.isNullOrEmpty { return .null }

        switch (value, targetType) {
        case (.shortText(let s), .longText):
            return .longText(s)
        case (.longText(let s), .shortText):
            return .shortText(s)
        case (.shortText(let s), .number), (.longText(let s), .number):
            guard let n = Double(s.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
            return .number(n)
        case (.number(let n), .shortText):
            return .shortText(String(n))
        case (.number(let n), .longText):
            return .longText(String(n))
        case (.shortText(let s), .currency):
            guard let money = MoneyValue(decimalString: s, currencyCode: validation.defaultCurrencyCode) else { return nil }
            return .currency(money)
        case (.number(let n), .currency):
            let minor = Int64((n * 100.0).rounded())
            return .currency(MoneyValue(minorUnits: minor, currencyCode: validation.defaultCurrencyCode, fractionDigits: 2))
        case (.currency(let money), .shortText):
            return .shortText(money.formatted())
        case (.currency(let money), .number):
            return .number(money.doubleApproximationForChartsOnly)
        case (.shortText(let s), .date):
            guard let cal = CalendarDate(isoDateString: s) else { return nil }
            return .date(cal)
        case (.date(let cal), .shortText):
            return .shortText(cal.isoString)
        case (.date(let cal), .dateTime):
            return .dateTime(cal.toDate(in: TimeZone(secondsFromGMT: 0) ?? .current))
        case (.dateTime(let dt), .date):
            return .date(CalendarDate(date: dt))
        case (.rating(let stars), .number):
            return .number(Double(stars))
        case (.number(let n), .rating):
            let rounded = Int(n.rounded())
            guard Double(rounded) == n && rounded >= 0 && rounded <= validation.maxRating else { return nil }
            return .rating(rounded)
        case (.singleSelect(let opt), .multiSelect):
            return .multiSelect([opt])
        case (. singleSelect(let opt), .shortText):
            return .shortText(opt)
        default:
            return nil
        }
    }
}

public enum SchemaMigrationError: LocalizedError, Sendable, Equatable {
    case fieldNotFound
    case conversionWouldLoseData(FieldConversionPreview)

    public var errorDescription: String? {
        switch self {
        case .fieldNotFound:
            return "The selected field could not be found in this collection."
        case .conversionWouldLoseData(let preview):
            return "Changing '\(preview.fieldLabel)' from \(preview.fromType.rawValue) to \(preview.toType.rawValue) would fail for \(preview.failureCount) of \(preview.totalRecordsExamined) records."
        }
    }
}
