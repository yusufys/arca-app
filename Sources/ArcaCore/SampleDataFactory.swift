import Foundation

/// Provides realistic, strictly fictional sample Spaces, Collections, and Records
/// for the prototype and onboarding experience. Never uses real personal or medical data.
public enum SampleDataFactory {

    public struct SeededSpaceBundle: Sendable {
        public let space: SpaceMetadata
        public let collections: [CollectionSchema]
        public let records: [RecordItem]
    }

    public static func createDefaultPersonalSpace(storageMode: SpaceStorageMode = .arcaSync) -> SeededSpaceBundle {
        let spaceId = UUID()
        let space = SpaceMetadata(
            id: spaceId,
            name: "Personal & Home",
            iconName: "house.fill",
            accentHex: "#2B5B84",
            storageMode: storageMode,
            cloudSyncAcceptedAt: storageMode == .arcaSync ? Date() : nil,
            containsSensitiveHealthTemplate: false
        )

        let warrantySchema = StarterTemplateCatalog.warranties.instantiateSchema(for: spaceId)
        let inventorySchema = StarterTemplateCatalog.homeInventory.instantiateSchema(for: spaceId)

        var records: [RecordItem] = []

        // Fictional Warranty Records
        if warrantySchema.fields.count >= 8 {
            let f = warrantySchema.fields
            let r1 = RecordItem(
                spaceId: spaceId,
                collectionId: warrantySchema.id,
                schemaVersionAtWrite: warrantySchema.schemaVersion,
                values: [
                    f[0].id: .shortText("Espresso Machine Pro 300"),
                    f[1].id: .shortText("Lucca Kitchen"),
                    f[2].id: .date(CalendarDate(year: 2025, month: 1, day: 14)),
                    f[3].id: .date(CalendarDate(year: 2027, month: 1, day: 14)),
                    f[4].id: .currency(MoneyValue(minorUnits: 74900, currencyCode: "USD")),
                    f[5].id: .singleSelect("manufacturer"),
                    f[6].id: .boolean(true),
                    f[7].id: .longText("2-year pump and boiler coverage. Authorized repair center on Oak Street. Reference order #LK-88412.")
                ],
                isFavorite: true
            )
            let r2 = RecordItem(
                spaceId: spaceId,
                collectionId: warrantySchema.id,
                schemaVersionAtWrite: warrantySchema.schemaVersion,
                values: [
                    f[0].id: .shortText("Cordless Stick Vacuum V12"),
                    f[1].id: .shortText("AeroClean"),
                    f[2].id: .date(CalendarDate(year: 2024, month: 11, day: 20)),
                    f[3].id: .date(CalendarDate(year: 2026, month: 11, day: 20)),
                    f[4].id: .currency(MoneyValue(minorUnits: 49999, currencyCode: "USD")),
                    f[5].id: .singleSelect("extended"),
                    f[6].id: .boolean(true),
                    f[7].id: .longText("Includes 1 free battery replacement during coverage period.")
                ],
                isFavorite: false
            )
            records.append(contentsOf: [r1, r2])
        }

        // Fictional Home Inventory Records
        if inventorySchema.fields.count >= 7 {
            let f = inventorySchema.fields
            let r3 = RecordItem(
                spaceId: spaceId,
                collectionId: inventorySchema.id,
                schemaVersionAtWrite: inventorySchema.schemaVersion,
                values: [
                    f[0].id: .shortText("27-inch Studio Display Monitor"),
                    f[1].id: .singleSelect("office"),
                    f[2].id: .currency(MoneyValue(minorUnits: 149900, currencyCode: "USD")),
                    f[3].id: .date(CalendarDate(year: 2025, month: 5, day: 10)),
                    f[4].id: .shortText("SN-9940-XQT-22"),
                    f[5].id: .rating(5),
                    f[6].id: .multiSelect(["electronics", "insured"])
                ],
                isFavorite: true
            )
            let r4 = RecordItem(
                spaceId: spaceId,
                collectionId: inventorySchema.id,
                schemaVersionAtWrite: inventorySchema.schemaVersion,
                values: [
                    f[0].id: .shortText("Solid Walnut Dining Table"),
                    f[1].id: .singleSelect("living"),
                    f[2].id: .currency(MoneyValue(minorUnits: 185000, currencyCode: "USD")),
                    f[3].id: .date(CalendarDate(year: 2025, month: 3, day: 2)),
                    f[4].id: .shortText("NW-TABLE-72"),
                    f[5].id: .rating(5),
                    f[6].id: .multiSelect(["furniture"])
                ],
                isFavorite: false
            )
            records.append(contentsOf: [r3, r4])
        }

        return SeededSpaceBundle(
            space: space,
            collections: [warrantySchema, inventorySchema],
            records: records
        )
    }

    public static func createVehiclesSpace(storageMode: SpaceStorageMode = .arcaSync) -> SeededSpaceBundle {
        let spaceId = UUID()
        let space = SpaceMetadata(
            id: spaceId,
            name: "Vehicles",
            iconName: "car.fill",
            accentHex: "#3A6B5C",
            storageMode: storageMode,
            cloudSyncAcceptedAt: storageMode == .arcaSync ? Date() : nil,
            containsSensitiveHealthTemplate: false
        )

        let vehicleSchema = StarterTemplateCatalog.vehicleMaintenance.instantiateSchema(for: spaceId)
        var records: [RecordItem] = []

        if vehicleSchema.fields.count >= 8 {
            let f = vehicleSchema.fields
            let r1 = RecordItem(
                spaceId: spaceId,
                collectionId: vehicleSchema.id,
                schemaVersionAtWrite: vehicleSchema.schemaVersion,
                values: [
                    f[0].id: .shortText("30,000-Mile Synthetic Oil & Filter Service"),
                    f[1].id: .date(CalendarDate(year: 2026, month: 8, day: 12)),
                    f[2].id: .number(30140),
                    f[3].id: .singleSelect("oil"),
                    f[4].id: .currency(MoneyValue(minorUnits: 11850, currencyCode: "USD")),
                    f[5].id: .shortText("Bayside Independent Auto"),
                    f[6].id: .boolean(false),
                    f[7].id: .longText("0W-20 full synthetic, OEM filter, cabin air filter replaced.")
                ],
                isFavorite: true
            )
            let r2 = RecordItem(
                spaceId: spaceId,
                collectionId: vehicleSchema.id,
                schemaVersionAtWrite: vehicleSchema.schemaVersion,
                values: [
                    f[0].id: .shortText("All-Season Tire Set & 4-Wheel Alignment"),
                    f[1].id: .date(CalendarDate(year: 2026, month: 4, day: 3)),
                    f[2].id: .number(26410),
                    f[3].id: .singleSelect("tires"),
                    f[4].id: .currency(MoneyValue(minorUnits: 92400, currencyCode: "USD")),
                    f[5].id: .shortText("Metro Tire & Wheel"),
                    f[6].id: .boolean(true),
                    f[7].id: .longText("60,000-mile treadwear warranty. Rotate every 6,000 miles.")
                ],
                isFavorite: false
            )
            records.append(contentsOf: [r1, r2])
        }

        return SeededSpaceBundle(
            space: space,
            collections: [vehicleSchema],
            records: records
        )
    }

    public static func createSensitiveHealthNotesSpace() -> SeededSpaceBundle {
        let spaceId = UUID()
        let space = SpaceMetadata(
            id: spaceId,
            name: "Health Notes (Local)",
            iconName: "cross.case.fill",
            accentHex: "#7A3E58",
            storageMode: .localOnly,
            cloudSyncAcceptedAt: nil,
            containsSensitiveHealthTemplate: true
        )

        let medicalSchema = StarterTemplateCatalog.medicalVisits.instantiateSchema(for: spaceId)
        var records: [RecordItem] = []

        if medicalSchema.fields.count >= 7 {
            let f = medicalSchema.fields
            let r1 = RecordItem(
                spaceId: spaceId,
                collectionId: medicalSchema.id,
                schemaVersionAtWrite: medicalSchema.schemaVersion,
                values: [
                    f[0].id: .shortText("Annual Preventive Checkup (Fictional Sample)"),
                    f[1].id: .date(CalendarDate(year: 2026, month: 6, day: 18)),
                    f[2].id: .shortText("Harborview Family Practice (Sample)"),
                    f[3].id: .singleSelect("primary"),
                    f[4].id: .currency(MoneyValue(minorUnits: 3500, currencyCode: "USD")),
                    f[5].id: .boolean(false),
                    f[6].id: .longText("Sample fictional entry demonstrating a local-only collection. Routine vitals normal; schedule next annual visit in 12 months.")
                ],
                isFavorite: false
            )
            records.append(r1)
        }

        return SeededSpaceBundle(
            space: space,
            collections: [medicalSchema],
            records: records
        )
    }
}
