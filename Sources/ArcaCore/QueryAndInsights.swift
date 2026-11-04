import Foundation

// MARK: - Search, Sort & Filter Models

public enum RecordSortCriterion: Equatable, Sendable, Hashable {
    case updatedAtDescending
    case updatedAtAscending
    case createdAtDescending
    case titleAscending
    case titleDescending
    case fieldAscending(UUID)
    case fieldDescending(UUID)
}

public enum RecordFieldFilter: Equatable, Sendable, Hashable, Identifiable {
    case favoritesOnly
    case booleanEquals(fieldId: UUID, Bool)
    case selectContains(fieldId: UUID, optionId: String)
    case numberRange(fieldId: UUID, min: Double?, max: Double?)
    case dateRange(fieldId: UUID, from: CalendarDate?, to: CalendarDate?)
    case minimumRating(fieldId: UUID, Int)
    case hasAttachments

    public var id: String {
        switch self {
        case .favoritesOnly: return "favorites_only"
        case .booleanEquals(let id, let b): return "bool_\(id.uuidString)_\(b)"
        case .selectContains(let id, let opt): return "sel_\(id.uuidString)_\(opt)"
        case .numberRange(let id, let min, let max): return "num_\(id.uuidString)_\(min ?? -1)_\(max ?? -1)"
        case .dateRange(let id, let from, let to): return "date_\(id.uuidString)_\(from?.isoString ?? "")_\(to?.isoString ?? "")"
        case .minimumRating(let id, let r): return "rating_\(id.uuidString)_\(r)"
        case .hasAttachments: return "has_attachments"
        }
    }
}

public struct RecordQuery: Equatable, Sendable {
    public var searchText: String
    public var collectionId: UUID?
    public var filters: [RecordFieldFilter]
    public var sort: RecordSortCriterion

    public init(
        searchText: String = "",
        collectionId: UUID? = nil,
        filters: [RecordFieldFilter] = [],
        sort: RecordSortCriterion = .updatedAtDescending
    ) {
        self.searchText = searchText
        self.collectionId = collectionId
        self.filters = filters
        self.sort = sort
    }
}

// MARK: - Insights Engine

public struct NumericFieldSummary: Identifiable, Sendable, Equatable {
    public var id: UUID { fieldId }
    public let fieldId: UUID
    public let collectionName: String
    public let fieldLabel: String
    public let isCurrency: Bool
    public let currencyCode: String?
    public let count: Int
    public let sum: Double
    public let average: Double
    public let formattedSum: String
    public let formattedAverage: String
}

public struct MonthlySpendingPoint: Identifiable, Sendable, Equatable {
    public var id: String { yearMonth }
    public let yearMonth: String
    public let monthDate: Date
    public let currencyCode: String
    public let totalMinorUnits: Int64
    public var totalAmount: Double { Double(totalMinorUnits) / 100.0 }
}

public struct SelectCategoryDistribution: Identifiable, Sendable, Equatable {
    public var id: String { "\(fieldId.uuidString)-\(optionLabel)" }
    public let fieldId: UUID
    public let fieldLabel: String
    public let optionLabel: String
    public let count: Int
}

public struct WarrantyExpirationAlert: Identifiable, Sendable, Equatable {
    public var id: UUID { recordId }
    public let recordId: UUID
    public let collectionId: UUID
    public let itemTitle: String
    public let expirationDate: CalendarDate
    public let daysRemaining: Int
    public var isExpired: Bool { daysRemaining < 0 }
}

public struct SpaceInsightsReport: Sendable, Equatable {
    public let spaceId: UUID
    public let totalRecords: Int
    public let favoriteRecords: Int
    public let totalAttachments: Int
    public let recordsByCollection: [(collection: CollectionSchema, count: Int)]
    public let numericSummaries: [NumericFieldSummary]
    public let spendingOverTime: [MonthlySpendingPoint]
    public let selectDistributions: [SelectCategoryDistribution]
    public let upcomingExpirations: [WarrantyExpirationAlert]

    public static func compute(
        spaceId: UUID,
        collections: [CollectionSchema],
        records: [RecordItem],
        referenceDate: CalendarDate = CalendarDate(date: Date()),
        locale: Locale = .current
    ) -> SpaceInsightsReport {
        let activeCollections = collections.filter { !$0.isDeleted }
        let activeRecords = records.filter { !$0.isDeleted && $0.spaceId == spaceId }

        let favorites = activeRecords.filter { $0.isFavorite }.count
        let attachmentsCount = activeRecords.reduce(0) { $0 + $1.allAttachments.count }

        let byCollection: [(CollectionSchema, Int)] = activeCollections.map { col in
            let c = activeRecords.filter { $0.collectionId == col.id }.count
            return (col, c)
        }

        var numericSummaries: [NumericFieldSummary] = []
        var monthlyTotals: [String: (date: Date, currency: String, minorUnits: Int64)] = [:]
        var selectDistributions: [SelectCategoryDistribution] = []
        var expirations: [WarrantyExpirationAlert] = []

        let refDateObj = referenceDate.toDate()
        let cal = Calendar(identifier: .gregorian)

        for col in activeCollections {
            let colRecords = activeRecords.filter { $0.collectionId == col.id }
            let dateFields = col.activeFields.filter { $0.type == .date }

            for field in col.activeFields {
                switch field.type {
                case .number:
                    var values: [Double] = []
                    for r in colRecords {
                        if case .number(let n) = r.values[field.id] {
                            values.append(n)
                        }
                    }
                    if !values.isEmpty {
                        let sum = values.reduce(0, +)
                        let avg = sum / Double(values.count)
                        let fmt = NumberFormatter()
                        fmt.locale = locale
                        fmt.numberStyle = .decimal
                        fmt.maximumFractionDigits = 2
                        numericSummaries.append(NumericFieldSummary(
                            fieldId: field.id,
                            collectionName: col.name,
                            fieldLabel: field.label,
                            isCurrency: false,
                            currencyCode: nil,
                            count: values.count,
                            sum: sum,
                            average: avg,
                            formattedSum: fmt.string(from: NSNumber(value: sum)) ?? String(format: "%.1f", sum),
                            formattedAverage: fmt.string(from: NSNumber(value: avg)) ?? String(format: "%.1f", avg)
                        ))
                    }

                case .currency:
                    var minorValues: [Int64] = []
                    var code = field.validation.defaultCurrencyCode
                    for r in colRecords {
                        if case .currency(let money) = r.values[field.id] {
                            minorValues.append(money.minorUnits)
                            code = money.currencyCode
                            // Associate with primary date field in the record for spending over time
                            let recordDate: CalendarDate = {
                                for df in dateFields {
                                    if case .date(let cd) = r.values[df.id] { return cd }
                                }
                                return CalendarDate(date: r.createdAt)
                            }()
                            let ym = String(format: "%04d-%02d", recordDate.year, recordDate.month)
                            let monthStart = CalendarDate(year: recordDate.year, month: recordDate.month, day: 1).toDate()
                            let existing = monthlyTotals[ym]?.minorUnits ?? 0
                            monthlyTotals[ym] = (monthStart, code, existing + money.minorUnits)
                        }
                    }
                    if !minorValues.isEmpty {
                        let sumMinor = minorValues.reduce(0, +)
                        let avgMinor = sumMinor / Int64(minorValues.count)
                        let sumMoney = MoneyValue(minorUnits: sumMinor, currencyCode: code)
                        let avgMoney = MoneyValue(minorUnits: avgMinor, currencyCode: code)
                        numericSummaries.append(NumericFieldSummary(
                            fieldId: field.id,
                            collectionName: col.name,
                            fieldLabel: field.label,
                            isCurrency: true,
                            currencyCode: code,
                            count: minorValues.count,
                            sum: sumMoney.doubleApproximationForChartsOnly,
                            average: avgMoney.doubleApproximationForChartsOnly,
                            formattedSum: sumMoney.formatted(locale: locale),
                            formattedAverage: avgMoney.formatted(locale: locale)
                        ))
                    }

                case .singleSelect:
                    var counts: [String: Int] = [:]
                    for r in colRecords {
                        if case .singleSelect(let optId) = r.values[field.id] {
                            let label = field.options.first(where: { $0.id == optId || $0.label == optId })?.label ?? optId
                            counts[label, default: 0] += 1
                        }
                    }
                    for (label, count) in counts.sorted(by: { $0.value > $1.value }) {
                        selectDistributions.append(SelectCategoryDistribution(
                            fieldId: field.id,
                            fieldLabel: "\(col.name) • \(field.label)",
                            optionLabel: label,
                            count: count
                        ))
                    }

                case .date:
                    let lowerLabel = field.label.lowercased()
                    if lowerLabel.contains("expir") || lowerLabel.contains("warranty") || col.name.lowercased().contains("warrant") {
                        for r in colRecords {
                            if case .date(let expDate) = r.values[field.id] {
                                let expDateObj = expDate.toDate()
                                let days = cal.dateComponents([.day], from: refDateObj, to: expDateObj).day ?? 0
                                if days <= 180 && days >= -90 {
                                    expirations.append(WarrantyExpirationAlert(
                                        recordId: r.id,
                                        collectionId: col.id,
                                        itemTitle: r.title(using: col),
                                        expirationDate: expDate,
                                        daysRemaining: days
                                    ))
                                }
                            }
                        }
                    }

                default:
                    break
                }
            }
        }

        let sortedSpending = monthlyTotals.keys.sorted().compactMap { key -> MonthlySpendingPoint? in
            guard let item = monthlyTotals[key] else { return nil }
            return MonthlySpendingPoint(
                yearMonth: key,
                monthDate: item.date,
                currencyCode: item.currency,
                totalMinorUnits: item.minorUnits
            )
        }

        let sortedExpirations = expirations.sorted { $0.daysRemaining < $1.daysRemaining }

        return SpaceInsightsReport(
            spaceId: spaceId,
            totalRecords: activeRecords.count,
            favoriteRecords: favorites,
            totalAttachments: attachmentsCount,
            recordsByCollection: byCollection,
            numericSummaries: numericSummaries,
            spendingOverTime: sortedSpending,
            selectDistributions: selectDistributions,
            upcomingExpirations: sortedExpirations
        )
    }

    public static func == (lhs: SpaceInsightsReport, rhs: SpaceInsightsReport) -> Bool {
        lhs.spaceId == rhs.spaceId &&
        lhs.totalRecords == rhs.totalRecords &&
        lhs.favoriteRecords == rhs.favoriteRecords &&
        lhs.totalAttachments == rhs.totalAttachments &&
        lhs.numericSummaries == rhs.numericSummaries &&
        lhs.spendingOverTime == rhs.spendingOverTime &&
        lhs.selectDistributions == rhs.selectDistributions &&
        lhs.upcomingExpirations == rhs.upcomingExpirations
    }
}

// MARK: - Optional Later Capabilities (Local QR Deep Links, Public Snapshot, ChatGPT Schema Import)

public enum OptionalCapabilityEngine {

    /// Generates a local-only deep link URI identifying a record (`arca://space/<spaceId>/record/<recordId>`).
    /// Explicitly does NOT embed or transfer record contents to another device.
    public static func localRecordDeepLink(spaceId: UUID, collectionId: UUID, recordId: UUID) -> URL {
        URL(string: "arca://local/space/\(spaceId.uuidString)/collection/\(collectionId.uuidString)/record/\(recordId.uuidString)")!
    }

    /// Parses a local `arca://` record deep link back into `(spaceId, collectionId, recordId)`.
    public static func parseLocalRecordDeepLink(_ url: URL) -> (spaceId: UUID, collectionId: UUID, recordId: UUID)? {
        guard url.scheme == "arca", url.host == "local" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 6,
              parts[0] == "space", let sId = UUID(uuidString: parts[1]),
              parts[2] == "collection", let cId = UUID(uuidString: parts[3]),
              parts[4] == "record", let rId = UUID(uuidString: parts[5]) else {
            return nil
        }
        return (sId, cId, rId)
    }

    /// Prompt users can copy into ChatGPT or another assistant to generate a validated Arca collection schema JSON.
    public static func chatGPTSchemaPrompt(forTopic topic: String) -> String {
        """
        Generate a JSON collection schema for the Arca personal records app for the topic: "\(topic)".
        Respond ONLY with valid JSON matching this structure:
        {
          "name": "Collection Name",
          "iconName": "folder.fill",
          "colorHex": "#2B5B84",
          "fields": [
            {
              "label": "Primary Title",
              "type": "short_text",
              "isRequired": true,
              "isPrimaryTitle": true,
              "options": []
            }
          ]
        }
        Allowed field types: short_text, long_text, number, currency, date, date_time, boolean, single_select, multi_select, rating, attachment.
        """
    }

    public struct ImportedSchemaDTO: Codable, Sendable {
        public struct FieldDTO: Codable, Sendable {
            public var label: String
            public var type: FieldType
            public var isRequired: Bool?
            public var isPrimaryTitle: Bool?
            public var options: [String]?
            public var privacy: SensitiveDataPrivacy?
        }
        public var name: String
        public var iconName: String?
        public var colorHex: String?
        public var fields: [FieldDTO]
        public var privacy: SensitiveDataPrivacy?
    }

    /// Validates and imports a JSON schema produced by an external prompt without trusting arbitrary identifiers.
    public static func parseAndValidateImportedSchemaJSON(_ jsonString: String, for spaceId: UUID) throws -> CollectionSchema {
        guard let data = jsonString.data(using: .utf8) else {
            throw ImportedSchemaError.invalidUTF8
        }
        let dto = try JSONDecoder().decode(ImportedSchemaDTO.self, from: data)
        let trimmedName = dto.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw ImportedSchemaError.emptyCollectionName
        }
        guard !dto.fields.isEmpty else {
            throw ImportedSchemaError.noFieldsProvided
        }

        let mappedFields: [FieldDefinition] = try dto.fields.enumerated().map { index, f in
            let label = f.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty else {
                throw ImportedSchemaError.emptyFieldLabel(index: index)
            }
            let opts = (f.options ?? []).map { SelectOption(label: $0) }
            return FieldDefinition(
                id: UUID(),
                label: label,
                type: f.type,
                isRequired: f.isRequired ?? (index == 0),
                sortOrder: index,
                options: opts,
                isPrimaryTitle: f.isPrimaryTitle ?? (index == 0),
                privacy: f.privacy == nil ? nil : .localOnly
            )
        }

        return CollectionSchema(
            id: UUID(),
            spaceId: spaceId,
            name: trimmedName,
            iconName: dto.iconName ?? "list.clipboard",
            colorHex: dto.colorHex ?? "#2B5B84",
            schemaVersion: 1,
            sensitivityPosture: .standard,
            privacy: dto.privacy == nil ? nil : .localOnly,
            fields: mappedFields
        )
    }
}

public enum ImportedSchemaError: LocalizedError, Sendable {
    case invalidUTF8
    case emptyCollectionName
    case noFieldsProvided
    case emptyFieldLabel(index: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidUTF8: return "The pasted text is not valid UTF-8 JSON."
        case .emptyCollectionName: return "The imported schema must have a non-empty collection name."
        case .noFieldsProvided: return "The imported schema must contain at least one field."
        case .emptyFieldLabel(let idx): return "Field #\(idx + 1) has an empty label."
        }
    }
}

/// Represents an explicit, revocable public snapshot of selected fields from a single record.
/// Completely separated from private sync; never created via an ambiguous single toggle.
public struct PublicRecordSnapshot: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let sourceRecordId: UUID
    public let title: String
    public let selectedFieldPairs: [(label: String, formattedValue: String)]
    public let createdAt: Date
    public var isRevoked: Bool
    public var revokedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, sourceRecordId, title, labels, values, createdAt, isRevoked, revokedAt
    }

    public init(
        id: UUID = UUID(),
        sourceRecordId: UUID,
        title: String,
        selectedFieldPairs: [(label: String, formattedValue: String)],
        createdAt: Date = Date(),
        isRevoked: Bool = false,
        revokedAt: Date? = nil
    ) {
        self.id = id
        self.sourceRecordId = sourceRecordId
        self.title = title
        self.selectedFieldPairs = selectedFieldPairs
        self.createdAt = createdAt
        self.isRevoked = isRevoked
        self.revokedAt = revokedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        sourceRecordId = try c.decode(UUID.self, forKey: .sourceRecordId)
        title = try c.decode(String.self, forKey: .title)
        let labels = try c.decode([String].self, forKey: .labels)
        let values = try c.decode([String].self, forKey: .values)
        selectedFieldPairs = Array(zip(labels, values))
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        isRevoked = try c.decode(Bool.self, forKey: .isRevoked)
        revokedAt = try c.decodeIfPresent(Date.self, forKey: .revokedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(sourceRecordId, forKey: .sourceRecordId)
        try c.encode(title, forKey: .title)
        try c.encode(selectedFieldPairs.map(\.label), forKey: .labels)
        try c.encode(selectedFieldPairs.map(\.formattedValue), forKey: .values)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(isRevoked, forKey: .isRevoked)
        try c.encodeIfPresent(revokedAt, forKey: .revokedAt)
    }

    public static func == (lhs: PublicRecordSnapshot, rhs: PublicRecordSnapshot) -> Bool {
        lhs.id == rhs.id &&
        lhs.sourceRecordId == rhs.sourceRecordId &&
        lhs.title == rhs.title &&
        lhs.isRevoked == rhs.isRevoked &&
        lhs.selectedFieldPairs.map(\.label) == rhs.selectedFieldPairs.map(\.label) &&
        lhs.selectedFieldPairs.map(\.formattedValue) == rhs.selectedFieldPairs.map(\.formattedValue)
    }
}
