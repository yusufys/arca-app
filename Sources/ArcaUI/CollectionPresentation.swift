import Foundation
import SwiftUI
import UniformTypeIdentifiers
import ImageIO
import ArcaCore
import ArcaPersistence

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Per-Collection Presentation Models

public enum CollectionListMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case normal = "normal"
    case compact = "compact"
    case box = "box"

    public var id: String { rawValue }

    public var titleKey: String {
        switch self {
        case .normal: return "Normal"
        case .compact: return "Compact"
        case .box: return "Box"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self))?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        self = CollectionListMode(rawValue: raw) ?? .normal
    }
}

public enum CollectionAddFormMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case popup = "popup"
    case fullScreen = "screen"

    public var id: String { rawValue }

    public var titleKey: String {
        switch self {
        case .popup: return "Popup Card"
        case .fullScreen: return "Complete New Screen"
        }
    }

    public var subtitleKey: String {
        switch self {
        case .popup: return "Slide-up modal card over current screen"
        case .fullScreen: return "Dedicated full-page form with extra room"
        }
    }

    public var iconName: String {
        switch self {
        case .popup: return "rectangle.portrait.on.rectangle.portrait.fill"
        case .fullScreen: return "iphone"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self))?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        switch raw {
        case "screen", "fullscreen", "full_screen":
            self = .fullScreen
        default:
            self = .popup
        }
    }
}

public enum CollectionIconTab: String, CaseIterable, Codable, Sendable, Identifiable {
    case library = "library"
    case emoji = "emoji"
    case upload = "upload"
    case letters = "letters"

    public var id: String { rawValue }

    public var titleKey: String {
        switch self {
        case .library: return "Library"
        case .emoji: return "Emoji"
        case .upload: return "Upload"
        case .letters: return "Letters"
        }
    }
}

public enum CollectionIconPreference: Codable, Sendable, Equatable, Hashable {
    case library(symbol: String)
    case emoji(String)
    case monogram(String)
    case customImage(filename: String)

    public var tab: CollectionIconTab {
        switch self {
        case .library: return .library
        case .emoji: return .emoji
        case .customImage: return .upload
        case .monogram: return .letters
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rawValue = try container.decode(String.self, forKey: .value).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawValue.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .value, in: container, debugDescription: "Empty icon value")
        }
        switch type {
        case "library":
            self = .library(symbol: rawValue)
        case "emoji":
            self = .emoji(String(rawValue.prefix(2)))
        case "letters", "monogram":
            self = .monogram(CollectionPresentationStore.sanitizeMonogram(rawValue, fallbackName: "A"))
        case "upload", "customimage", "custom_image":
            guard CollectionPresentationStore.isSafeIconFilename(rawValue) else {
                throw DecodingError.dataCorruptedError(forKey: .value, in: container, debugDescription: "Unsafe custom image filename")
            }
            self = .customImage(filename: rawValue)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown icon preference type")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .library(let symbol):
            try container.encode("library", forKey: .type)
            try container.encode(symbol, forKey: .value)
        case .emoji(let emoji):
            try container.encode("emoji", forKey: .type)
            try container.encode(emoji, forKey: .value)
        case .monogram(let letters):
            try container.encode("letters", forKey: .type)
            try container.encode(letters, forKey: .value)
        case .customImage(let filename):
            try container.encode("upload", forKey: .type)
            try container.encode(filename, forKey: .value)
        }
    }
}

public struct CollectionPresentationPreferences: Codable, Sendable, Equatable {
    public var listMode: CollectionListMode
    public var addFormMode: CollectionAddFormMode
    public var compactSecondaryFieldId: UUID?
    public var iconPreference: CollectionIconPreference?

    public init(
        listMode: CollectionListMode = .normal,
        addFormMode: CollectionAddFormMode = .popup,
        compactSecondaryFieldId: UUID? = nil,
        iconPreference: CollectionIconPreference? = nil
    ) {
        self.listMode = listMode
        self.addFormMode = addFormMode
        self.compactSecondaryFieldId = compactSecondaryFieldId
        self.iconPreference = iconPreference
    }

    private enum CodingKeys: String, CodingKey {
        case listMode
        case addFormMode
        case compactSecondaryFieldId
        case iconPreference
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.listMode = (try? container.decode(CollectionListMode.self, forKey: .listMode)) ?? .normal
        self.addFormMode = (try? container.decode(CollectionAddFormMode.self, forKey: .addFormMode)) ?? .popup
        if let uuidString = try? container.decodeIfPresent(String.self, forKey: .compactSecondaryFieldId) {
            self.compactSecondaryFieldId = UUID(uuidString: uuidString.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            self.compactSecondaryFieldId = nil
        }
        self.iconPreference = try? container.decodeIfPresent(CollectionIconPreference.self, forKey: .iconPreference)
    }
}

public enum CollectionIconImageError: LocalizedError, Sendable, Equatable {
    case emptyData
    case fileTooLarge
    case invalidImageData
    case encodingFailed
    case writeFailed

    public var errorDescription: String? {
        switch self {
        case .emptyData:
            return "The selected image file is empty."
        case .fileTooLarge:
            return "Choose an image smaller than 15 MB."
        case .invalidImageData:
            return "The selected file could not be read as an image."
        case .encodingFailed:
            return "Could not prepare a compact icon from the selected image."
        case .writeFailed:
            return "Could not save the custom icon on this device."
        }
    }
}

// MARK: - Curated Palette & Grouped Icon Library Catalog

public struct CollectionColorOption: Identifiable, Sendable, Equatable {
    public var id: String { hex.uppercased() }
    public let nameKey: String
    public let hex: String
    public let tagKey: String

    public init(nameKey: String, hex: String, tagKey: String) {
        self.nameKey = nameKey
        self.hex = hex.uppercased()
        self.tagKey = tagKey
    }
}

public struct CollectionLibraryIconItem: Identifiable, Sendable, Equatable {
    public var id: String { symbol }
    public let symbol: String
    public let labelKey: String

    public init(symbol: String, labelKey: String) {
        self.symbol = symbol
        self.labelKey = labelKey
    }
}

public struct CollectionLibrarySubcategory: Identifiable, Sendable, Equatable {
    public var id: String { titleKey }
    public let titleKey: String
    public let icons: [CollectionLibraryIconItem]
}

public struct CollectionLibraryCategory: Identifiable, Sendable, Equatable {
    public var id: String { titleKey }
    public let titleKey: String
    public let subcategories: [CollectionLibrarySubcategory]
}

public enum CollectionDesignCatalog {
    public static let collectionColors: [CollectionColorOption] = [
        CollectionColorOption(nameKey: "Amber Bronze", hex: "#B45309", tagKey: "Warm"),
        CollectionColorOption(nameKey: "Royal Indigo", hex: "#4338CA", tagKey: "Deep"),
        CollectionColorOption(nameKey: "Crimson Rose", hex: "#BE123C", tagKey: "Bold"),
        CollectionColorOption(nameKey: "Ocean Cerulean", hex: "#0369A1", tagKey: "Crisp"),
        CollectionColorOption(nameKey: "Teal Lagoon", hex: "#0F766E", tagKey: "Calm"),
        CollectionColorOption(nameKey: "Violet Amethyst", hex: "#6D28D9", tagKey: "Rich"),
        CollectionColorOption(nameKey: "Copper Terracotta", hex: "#C2410C", tagKey: "Earth"),
        CollectionColorOption(nameKey: "Slate Graphite", hex: "#334155", tagKey: "Neutral"),
        CollectionColorOption(nameKey: "Forest Emerald", hex: "#1F5D3F", tagKey: "Archival")
    ]

    private static let starterColorFallbacks: [String: CollectionColorOption] = [
        "#2B5B84": CollectionColorOption(nameKey: "Classic Navy", hex: "#2B5B84", tagKey: "Classic"),
        "#3A6B5C": CollectionColorOption(nameKey: "Sage Pine", hex: "#3A6B5C", tagKey: "Calm"),
        "#8C5A2B": CollectionColorOption(nameKey: "Walnut Bronze", hex: "#8C5A2B", tagKey: "Warm"),
        "#7A3E58": CollectionColorOption(nameKey: "Plum Rose", hex: "#7A3E58", tagKey: "Sensitive")
    ]

    public static func colorOption(for hex: String) -> CollectionColorOption {
        let normalized = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let match = collectionColors.first(where: { $0.hex.uppercased() == normalized }) {
            return match
        }
        if let starter = starterColorFallbacks[normalized] {
            return starter
        }
        return CollectionColorOption(nameKey: "Custom Color", hex: normalized.isEmpty ? "#1F5D3F" : normalized, tagKey: "Custom")
    }

    public static let emojiOptions: [String] = [
        "🏠", "🛡️", "🚗", "💻", "☕", "🛋️", "🧾", "🩺",
        "🎸", "🍷", "⌚", "📷", "✈️", "🐾", "🪴", "🔑",
        "🧰", "💎", "📦", "🎓", "🏋️", "🚲", "🛥️", "🏕️"
    ]

    public static let iconCategories: [CollectionLibraryCategory] = [
        CollectionLibraryCategory(
            titleKey: "Home & Living",
            subcategories: [
                CollectionLibrarySubcategory(
                    titleKey: "Appliances",
                    icons: [
                        CollectionLibraryIconItem(symbol: "checkmark.shield.fill", labelKey: "Warranty Shield"),
                        CollectionLibraryIconItem(symbol: "cup.and.saucer.fill", labelKey: "Coffee & Kitchen"),
                        CollectionLibraryIconItem(symbol: "fan.fill", labelKey: "Climate & Air"),
                        CollectionLibraryIconItem(symbol: "snowflake", labelKey: "Cooling & Fridge"),
                        CollectionLibraryIconItem(symbol: "washer.fill", labelKey: "Laundry"),
                        CollectionLibraryIconItem(symbol: "flame.fill", labelKey: "Heating & Range"),
                        CollectionLibraryIconItem(symbol: "fork.knife", labelKey: "Dining & Cookware"),
                        CollectionLibraryIconItem(symbol: "lightbulb.fill", labelKey: "Lighting")
                    ]
                ),
                CollectionLibrarySubcategory(
                    titleKey: "Furniture & Rooms",
                    icons: [
                        CollectionLibraryIconItem(symbol: "sofa.fill", labelKey: "Living Room"),
                        CollectionLibraryIconItem(symbol: "bed.double.fill", labelKey: "Bedroom"),
                        CollectionLibraryIconItem(symbol: "chair.lounge.fill", labelKey: "Furniture"),
                        CollectionLibraryIconItem(symbol: "door.left.hand.closed", labelKey: "Entry & Doors"),
                        CollectionLibraryIconItem(symbol: "leaf.fill", labelKey: "Plants & Garden"),
                        CollectionLibraryIconItem(symbol: "photo.artframe", labelKey: "Art & Decor"),
                        CollectionLibraryIconItem(symbol: "sparkles", labelKey: "Care & Cleaning"),
                        CollectionLibraryIconItem(symbol: "shower.fill", labelKey: "Bath & Plumbing")
                    ]
                ),
                CollectionLibrarySubcategory(
                    titleKey: "Security & Keys",
                    icons: [
                        CollectionLibraryIconItem(symbol: "lock.shield.fill", labelKey: "Security"),
                        CollectionLibraryIconItem(symbol: "key.fill", labelKey: "Keys & Access"),
                        CollectionLibraryIconItem(symbol: "video.fill", labelKey: "Cameras"),
                        CollectionLibraryIconItem(symbol: "bell.beacon.max.fill", labelKey: "Alarms"),
                        CollectionLibraryIconItem(symbol: "flame.circle.fill", labelKey: "Safety"),
                        CollectionLibraryIconItem(symbol: "wrench.and.screwdriver.fill", labelKey: "Tools & Repairs"),
                        CollectionLibraryIconItem(symbol: "building.2.fill", labelKey: "Property"),
                        CollectionLibraryIconItem(symbol: "house.fill", labelKey: "Home")
                    ]
                )
            ]
        ),
        CollectionLibraryCategory(
            titleKey: "Finance & Legal",
            subcategories: [
                CollectionLibrarySubcategory(
                    titleKey: "Warranties & Receipts",
                    icons: [
                        CollectionLibraryIconItem(symbol: "receipt.fill", labelKey: "Receipt"),
                        CollectionLibraryIconItem(symbol: "scroll.fill", labelKey: "Certificate"),
                        CollectionLibraryIconItem(symbol: "tag.fill", labelKey: "Price Tag"),
                        CollectionLibraryIconItem(symbol: "creditcard.fill", labelKey: "Payment Card"),
                        CollectionLibraryIconItem(symbol: "banknote.fill", labelKey: "Cash & Value"),
                        CollectionLibraryIconItem(symbol: "building.columns.fill", labelKey: "Banking"),
                        CollectionLibraryIconItem(symbol: "scalemass.fill", labelKey: "Legal"),
                        CollectionLibraryIconItem(symbol: "doc.text.fill", labelKey: "Document")
                    ]
                ),
                CollectionLibrarySubcategory(
                    titleKey: "Insurance & Tax",
                    icons: [
                        CollectionLibraryIconItem(symbol: "umbrella.fill", labelKey: "Insurance Coverage"),
                        CollectionLibraryIconItem(symbol: "chart.bar.doc.horizontal.fill", labelKey: "Reports & Tax"),
                        CollectionLibraryIconItem(symbol: "briefcase.fill", labelKey: "Work & Business"),
                        CollectionLibraryIconItem(symbol: "signature", labelKey: "Contracts"),
                        CollectionLibraryIconItem(symbol: "person.text.rectangle.fill", labelKey: "Identity & Registration"),
                        CollectionLibraryIconItem(symbol: "folder.fill", labelKey: "Archive Folder"),
                        CollectionLibraryIconItem(symbol: "lock.fill", labelKey: "Vault"),
                        CollectionLibraryIconItem(symbol: "list.clipboard", labelKey: "Clipboard")
                    ]
                )
            ]
        ),
        CollectionLibraryCategory(
            titleKey: "Vehicles & Gear",
            subcategories: [
                CollectionLibrarySubcategory(
                    titleKey: "Cars & Service",
                    icons: [
                        CollectionLibraryIconItem(symbol: "car.fill", labelKey: "Vehicle"),
                        CollectionLibraryIconItem(symbol: "steeringwheel", labelKey: "Driving & Tires"),
                        CollectionLibraryIconItem(symbol: "wrench.adjustable.fill", labelKey: "Maintenance"),
                        CollectionLibraryIconItem(symbol: "fuelpump.fill", labelKey: "Fuel & Mileage"),
                        CollectionLibraryIconItem(symbol: "bolt.car.fill", labelKey: "EV & Battery"),
                        CollectionLibraryIconItem(symbol: "road.lanes", labelKey: "Trips & Highway"),
                        CollectionLibraryIconItem(symbol: "screwdriver.fill", labelKey: "Parts"),
                        CollectionLibraryIconItem(symbol: "truck.box.fill", labelKey: "Transport")
                    ]
                ),
                CollectionLibrarySubcategory(
                    titleKey: "Electronics & Media",
                    icons: [
                        CollectionLibraryIconItem(symbol: "laptopcomputer", labelKey: "Laptop"),
                        CollectionLibraryIconItem(symbol: "desktopcomputer", labelKey: "Display & Studio"),
                        CollectionLibraryIconItem(symbol: "camera.fill", labelKey: "Camera & Gear"),
                        CollectionLibraryIconItem(symbol: "headphones", labelKey: "Audio"),
                        CollectionLibraryIconItem(symbol: "iphone", labelKey: "Phone"),
                        CollectionLibraryIconItem(symbol: "applewatch", labelKey: "Watch"),
                        CollectionLibraryIconItem(symbol: "gamecontroller.fill", labelKey: "Gaming"),
                        CollectionLibraryIconItem(symbol: "printer.fill", labelKey: "Office Gear")
                    ]
                )
            ]
        ),
        CollectionLibraryCategory(
            titleKey: "Health & Personal",
            subcategories: [
                CollectionLibrarySubcategory(
                    titleKey: "Medical & Labs",
                    icons: [
                        CollectionLibraryIconItem(symbol: "stethoscope", labelKey: "Medical Checkup"),
                        CollectionLibraryIconItem(symbol: "pills.fill", labelKey: "Medications"),
                        CollectionLibraryIconItem(symbol: "cross.case.fill", labelKey: "Medical Visits"),
                        CollectionLibraryIconItem(symbol: "cross.vial.fill", labelKey: "Lab Results"),
                        CollectionLibraryIconItem(symbol: "heart.text.square.fill", labelKey: "Health Summary"),
                        CollectionLibraryIconItem(symbol: " heart.fill".trimmingCharacters(in: .whitespaces), labelKey: "Wellness"),
                        CollectionLibraryIconItem(symbol: "eyeglasses", labelKey: "Vision & Optical"),
                        CollectionLibraryIconItem(symbol: "list.clipboard.fill", labelKey: "Records")
                    ]
                ),
                CollectionLibrarySubcategory(
                    titleKey: "Collections & Hobbies",
                    icons: [
                        CollectionLibraryIconItem(symbol: "guitars.fill", labelKey: "Music"),
                        CollectionLibraryIconItem(symbol: "wineglass.fill", labelKey: "Cellar & Tasting"),
                        CollectionLibraryIconItem(symbol: "books.vertical.fill", labelKey: "Books & Library"),
                        CollectionLibraryIconItem(symbol: "paintpalette.fill", labelKey: "Art & Crafts"),
                        CollectionLibraryIconItem(symbol: "tent.fill", labelKey: "Outdoors"),
                        CollectionLibraryIconItem(symbol: "bicycle", labelKey: "Cycling"),
                        CollectionLibraryIconItem(symbol: "trophy.fill", labelKey: "Awards"),
                        CollectionLibraryIconItem(symbol: "airplane", labelKey: "Travel")
                    ]
                )
            ]
        )
    ]

    public static func locateCategoryAndSubcategory(forSymbol symbol: String) -> (category: String, subcategory: String)? {
        for cat in iconCategories {
            for sub in cat.subcategories {
                if sub.icons.contains(where: { $0.symbol == symbol }) {
                    return (cat.titleKey, sub.titleKey)
                }
            }
        }
        return nil
    }
}

struct CollectionColorPalette {
    private let rgb: SIMD3<Double>

    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let value = (cleaned.count == 6 ? UInt64(cleaned, radix: 16) : nil) ?? 0x1F5D3F
        rgb = SIMD3(Double((value >> 16) & 0xFF), Double((value >> 8) & 0xFF), Double(value & 0xFF)) / 255
    }

    var fill: Color { Self.color(rgb) }

    var onFill: Color {
        Self.luminance(rgb) < 0.179 ? .white : .black
    }

    func ink(for scheme: ColorScheme) -> Color {
        // Check both the neutral surface and the tinted surface used for outlined controls.
        let isDark = scheme == .dark
        let surface = isDark ? SIMD3<Double>(0.10, 0.14, 0.13) : SIMD3<Double>(0.95, 0.93, 0.89)
        let tintedSurface = surface * 0.86 + rgb * 0.14
        let luminance = Self.luminance(tintedSurface)
        let target = SIMD3<Double>(repeating: isDark ? 1 : 0)
        for step in 0...20 {
            let amount = Double(step) / 20
            let mixed = rgb * (1 - amount) + target * amount
            let inkLuminance = Self.luminance(mixed)
            let contrast = (max(inkLuminance, luminance) + 0.05) / (min(inkLuminance, luminance) + 0.05)
            if contrast >= 4.5, isDark ? inkLuminance > luminance : inkLuminance < luminance {
                return Self.color(mixed)
            }
        }
        return isDark ? .white : .black
    }

    private static func color(_ rgb: SIMD3<Double>) -> Color {
        Color(red: rgb.x, green: rgb.y, blue: rgb.z)
    }

    private static func luminance(_ rgb: SIMD3<Double>) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.x) + 0.7152 * linear(rgb.y) + 0.0722 * linear(rgb.z)
    }
}

// MARK: - Persistent Presentation Store

@available(macOS 14.0, iOS 17.0, *)
@MainActor
@Observable
public final class CollectionPresentationStore {
    public static let shared = CollectionPresentationStore()

    public nonisolated static let maxInputImageBytes = 15 * 1024 * 1024
    public nonisolated static let maxStoredIconBytes = 512 * 1024
    public nonisolated static let maxIconPixelDimension = 256

    private let userDefaults: UserDefaults
    private let keyPrefix: String
    public let imageDirectoryURL: URL
    private var cache: [UUID: CollectionPresentationPreferences] = [:]
    private var imageDataCache: [UUID: Data] = [:]
    private var revisionCounter: Int = 0

    public init(
        userDefaults: UserDefaults = .standard,
        keyPrefix: String = "arca.collection.presentation.v1.",
        imageDirectoryURL: URL? = nil
    ) {
        self.userDefaults = userDefaults
        self.keyPrefix = keyPrefix
        let dir = imageDirectoryURL ?? CatalogStore.defaultBaseDirectoryURL().appendingPathComponent("CollectionIcons", isDirectory: true)
        self.imageDirectoryURL = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? Self.excludeIconDirectoryFromBackup(dir)
    }

    private func storageKey(for collectionId: UUID) -> String {
        keyPrefix + collectionId.uuidString.lowercased()
    }

    public func preferences(for collectionId: UUID) -> CollectionPresentationPreferences {
        _ = revisionCounter
        if let cached = cache[collectionId] {
            return cached
        }
        let key = storageKey(for: collectionId)
        guard let data = userDefaults.data(forKey: key) else {
            let defaults = CollectionPresentationPreferences()
            cache[collectionId] = defaults
            return defaults
        }
        guard let decoded = try? JSONDecoder().decode(CollectionPresentationPreferences.self, from: data) else {
            // Gracefully recover from malformed UserDefaults payloads without crashing
            let fallback = CollectionPresentationPreferences()
            cache[collectionId] = fallback
            return fallback
        }
        cache[collectionId] = decoded
        return decoded
    }

    public func updatePreferences(
        for collectionId: UUID,
        mutate: (inout CollectionPresentationPreferences) -> Void
    ) {
        var current = preferences(for: collectionId)
        mutate(&current)
        cache[collectionId] = current
        revisionCounter += 1
        if let encoded = try? JSONEncoder().encode(current) {
            userDefaults.set(encoded, forKey: storageKey(for: collectionId))
        }
    }

    public func listMode(for collectionId: UUID) -> CollectionListMode {
        preferences(for: collectionId).listMode
    }

    public func setListMode(_ mode: CollectionListMode, for collectionId: UUID) {
        updatePreferences(for: collectionId) { $0.listMode = mode }
    }

    public func addFormMode(for collectionId: UUID) -> CollectionAddFormMode {
        preferences(for: collectionId).addFormMode
    }

    public func setAddFormMode(_ mode: CollectionAddFormMode, for collectionId: UUID) {
        updatePreferences(for: collectionId) { $0.addFormMode = mode }
    }

    public func setCompactSecondaryField(_ fieldId: UUID?, for collectionId: UUID) {
        updatePreferences(for: collectionId) { $0.compactSecondaryFieldId = fieldId }
    }

    public func setIcon(_ iconPreference: CollectionIconPreference?, for collectionId: UUID) {
        if case .customImage = iconPreference {
            // Keep existing custom image file
        } else {
            removeStoredCustomImageFile(for: collectionId)
        }
        updatePreferences(for: collectionId) { $0.iconPreference = iconPreference }
    }

    /// Returns candidate fields that can be displayed beside the primary title in Compact mode.
    public nonisolated static func secondaryFieldCandidates(for schema: CollectionSchema) -> [FieldDefinition] {
        let primaryId = schema.primaryTitleField?.id
        let nonPrimary = schema.activeFields.filter { $0.id != primaryId }
        return nonPrimary.isEmpty ? schema.activeFields : nonPrimary
    }

    /// Resolves the active compact secondary field for `schema`, automatically falling back if the
    /// previously selected field was archived, purged, or never configured.
    public func resolvedSecondaryField(for schema: CollectionSchema) -> FieldDefinition? {
        let candidates = Self.secondaryFieldCandidates(for: schema)
        guard !candidates.isEmpty else { return nil }
        if let preferredId = preferences(for: schema.id).compactSecondaryFieldId,
           let matched = candidates.first(where: { $0.id == preferredId && !$0.isArchived }) {
            return matched
        }
        return candidates.first
    }

    public func compactSecondaryDisplayText(
        for record: RecordItem,
        schema: CollectionSchema,
        locale: Locale = .current
    ) -> String? {
        guard let field = resolvedSecondaryField(for: schema) else { return nil }
        let val = record.values[field.id] ?? .null
        guard !val.isNullOrEmpty else { return nil }
        let summary = val.plainTextSummary(for: field, locale: locale)
        return summary.isEmpty ? nil : summary
    }

    // MARK: - Monogram & Initials Helpers

    public nonisolated static func computeInitials(for name: String) -> String {
        let words = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return "A" }
        if words.count == 1 {
            return String(words[0].prefix(2)).uppercased()
        }
        let first = String(words[0].prefix(1))
        let second = String(words[1].prefix(1))
        return (first + second).uppercased()
    }

    public nonisolated static func sanitizeMonogram(_ raw: String, fallbackName: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return computeInitials(for: fallbackName)
        }
        return String(trimmed.uppercased().prefix(3))
    }

    // MARK: - Safe App-Private Bounded Custom Image Storage

    public nonisolated static func isSafeIconFilename(_ filename: String) -> Bool {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("/"),
              !trimmed.contains("\\"),
              !trimmed.contains(".."),
              trimmed.hasSuffix(".png") || trimmed.hasSuffix(".jpg") else {
            return false
        }
        return true
    }

    public nonisolated static func prepareBoundedIconPNGData(
        from rawData: Data,
        maxDimension: Int = CollectionPresentationStore.maxIconPixelDimension,
        maxOutputBytes: Int = CollectionPresentationStore.maxStoredIconBytes
    ) throws -> Data {
        guard !rawData.isEmpty else {
            throw CollectionIconImageError.emptyData
        }
        guard rawData.count <= maxInputImageBytes else {
            throw CollectionIconImageError.fileTooLarge
        }
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(rawData as CFData, sourceOptions as CFDictionary) else {
            throw CollectionIconImageError.invalidImageData
        }
        guard let dimensions = Self.pixelDimensions(of: source) else {
            throw CollectionIconImageError.invalidImageData
        }
        guard dimensions.width <= 16_384, dimensions.height <= 16_384,
              dimensions.width * dimensions.height <= 64_000_000 else {
            throw CollectionIconImageError.fileTooLarge
        }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(32, min(512, maxDimension))
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
            throw CollectionIconImageError.invalidImageData
        }

        let pngData = NSMutableData()
        if let destination = CGImageDestinationCreateWithData(pngData, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, cgImage, nil)
            if CGImageDestinationFinalize(destination), pngData.length > 0, pngData.length <= maxOutputBytes {
                return pngData as Data
            }
        }

        // Fallback to compressed JPEG if PNG exceeds maxOutputBytes
        let jpegData = NSMutableData()
        let jpegProps: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.82]
        guard let jpegDest = CGImageDestinationCreateWithData(jpegData, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CollectionIconImageError.encodingFailed
        }
        CGImageDestinationAddImage(jpegDest, cgImage, jpegProps as CFDictionary)
        guard CGImageDestinationFinalize(jpegDest), jpegData.length > 0, jpegData.length <= maxOutputBytes else {
            throw CollectionIconImageError.encodingFailed
        }
        return jpegData as Data
    }

    @discardableResult
    public func saveCustomIconImageData(_ rawData: Data, for collectionId: UUID) throws -> String {
        let boundedData = try Self.prepareBoundedIconPNGData(from: rawData)
        let filename = "\(collectionId.uuidString.lowercased()).png"
        let fileURL = imageDirectoryURL.appendingPathComponent(filename, isDirectory: false)
        do {
            try FileManager.default.createDirectory(at: imageDirectoryURL, withIntermediateDirectories: true)
            try Self.excludeIconDirectoryFromBackup(imageDirectoryURL)
            #if os(iOS)
            try boundedData.write(to: fileURL, options: [.atomic, .completeFileProtection])
            #else
            try boundedData.write(to: fileURL, options: [.atomic])
            #endif
        } catch {
            throw CollectionIconImageError.writeFailed
        }
        imageDataCache[collectionId] = boundedData
        updatePreferences(for: collectionId) {
            $0.iconPreference = .customImage(filename: filename)
        }
        return filename
    }

    public func saveCustomIconImage(fromFileURL url: URL, for collectionId: UUID) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try Self.readImageFile(at: url, maxBytes: Self.maxInputImageBytes)
        _ = try saveCustomIconImageData(data, for: collectionId)
    }

    public func customImageData(for collectionId: UUID) -> Data? {
        _ = revisionCounter
        guard case .customImage(let filename) = preferences(for: collectionId).iconPreference,
              filename == "\(collectionId.uuidString.lowercased()).png" else {
            return nil
        }
        if let cached = imageDataCache[collectionId] {
            return cached
        }
        let fileURL = imageDirectoryURL.appendingPathComponent(filename, isDirectory: false)
        guard let data = try? Self.readImageFile(at: fileURL, maxBytes: Self.maxStoredIconBytes),
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let dimensions = Self.pixelDimensions(of: source),
              dimensions.width <= Self.maxIconPixelDimension,
              dimensions.height <= Self.maxIconPixelDimension else {
            return nil
        }
        imageDataCache[collectionId] = data
        return data
    }

    private nonisolated static func pixelDimensions(of source: CGImageSource) -> (width: Int, height: Int)? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return nil }
        return (width, height)
    }

    private static func readImageFile(at url: URL, maxBytes: Int) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw CollectionIconImageError.invalidImageData
        }
        guard (values.fileSize ?? 0) <= maxBytes else { throw CollectionIconImageError.fileTooLarge }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        guard let data = try file.read(upToCount: maxBytes + 1), !data.isEmpty else {
            throw CollectionIconImageError.emptyData
        }
        guard data.count <= maxBytes else { throw CollectionIconImageError.fileTooLarge }
        return data
    }

    private static func excludeIconDirectoryFromBackup(_ url: URL) throws {
        var directory = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
    }

    private func removeStoredCustomImageFile(for collectionId: UUID) {
        imageDataCache.removeValue(forKey: collectionId)
        let filename = "\(collectionId.uuidString.lowercased()).png"
        let fileURL = imageDirectoryURL.appendingPathComponent(filename, isDirectory: false)
        try? FileManager.default.removeItem(at: fileURL)
    }
}

// MARK: - Shared Public CollectionBadgeView

@available(macOS 14.0, iOS 17.0, *)
@MainActor
public struct CollectionBadgeView: View {
    public let schema: CollectionSchema
    public var size: CGFloat
    public var presentationStore: CollectionPresentationStore

    public init(
        schema: CollectionSchema,
        size: CGFloat = 44,
        presentationStore: CollectionPresentationStore? = nil
    ) {
        self.schema = schema
        self.size = size
        self.presentationStore = presentationStore ?? .shared
    }

    public var body: some View {
        let tint = CollectionColorPalette(hex: schema.colorHex).fill
        let cornerRadius = max(10, size * 0.30)
        let pref = presentationStore.preferences(for: schema.id).iconPreference

        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(tint)
                .frame(width: size, height: size)
                .shadow(color: tint.opacity(0.24), radius: 5, x: 0, y: 2)

            badgeContent(for: pref, cornerRadius: cornerRadius)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func badgeContent(for preference: CollectionIconPreference?, cornerRadius: CGFloat) -> some View {
        switch preference {
        case .customImage:
            if let data = presentationStore.customImageData(for: schema.id),
               let image = Self.makeSwiftUIImage(from: data) {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                    )
            } else {
                fallbackSymbolImage(symbol: schema.iconName)
            }

        case .monogram(let letters):
            let clean = CollectionPresentationStore.sanitizeMonogram(letters, fallbackName: schema.name)
            Text(verbatim: clean)
                .font(.system(size: size * 0.38, weight: .black, design: .rounded))
                .foregroundStyle(CollectionColorPalette(hex: schema.colorHex).onFill)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 4)

        case .emoji(let emoji):
            Text(verbatim: emoji)
                .font(.system(size: size * 0.48))
                .lineLimit(1)

        case .library(let symbol):
            let activeSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? schema.iconName : symbol
            fallbackSymbolImage(symbol: activeSymbol)

        case nil:
            fallbackSymbolImage(symbol: schema.iconName)
        }
    }

    private func fallbackSymbolImage(symbol: String) -> some View {
        Image(systemName: Self.validSymbol(symbol) ?? Self.validSymbol(schema.iconName) ?? "list.clipboard")
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(CollectionColorPalette(hex: schema.colorHex).onFill)
    }

    private static func validSymbol(_ symbol: String) -> String? {
        guard !symbol.isEmpty else { return nil }
        #if canImport(UIKit)
        return UIImage(systemName: symbol) == nil ? nil : symbol
        #elseif canImport(AppKit)
        return NSImage(systemSymbolName: symbol, accessibilityDescription: nil) == nil ? nil : symbol
        #else
        return symbol
        #endif
    }

    private static func makeSwiftUIImage(from data: Data) -> Image? {
        #if canImport(UIKit)
        guard let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
        #elseif canImport(AppKit)
        guard let nsImage = NSImage(data: data) else { return nil }
        return Image(nsImage: nsImage)
        #else
        return nil
        #endif
    }
}

// MARK: - Shared Public CollectionAddRecordPresenter

@available(macOS 14.0, iOS 17.0, *)
@MainActor
public struct CollectionAddRecordPresenter: ViewModifier {
    @Bindable var viewModel: ArcaAppViewModel
    @Binding var schema: CollectionSchema?
    private let presentationStore: CollectionPresentationStore

    public init(
        viewModel: ArcaAppViewModel,
        schema: Binding<CollectionSchema?>,
        presentationStore: CollectionPresentationStore? = nil
    ) {
        self.viewModel = viewModel
        self._schema = schema
        self.presentationStore = presentationStore ?? .shared
    }

    private var activeAddMode: CollectionAddFormMode {
        guard let current = schema else { return .popup }
        return presentationStore.addFormMode(for: current.id)
    }

    private var popupBinding: Binding<CollectionSchema?> {
        Binding(
            get: {
                guard let current = schema else { return nil }
                #if os(iOS)
                return activeAddMode == .popup ? (viewModel.schema(for: current.id) ?? current) : nil
                #else
                return viewModel.schema(for: current.id) ?? current
                #endif
            },
            set: { newValue in
                if newValue == nil {
                    schema = nil
                } else {
                    schema = newValue
                }
            }
        )
    }

    #if os(iOS)
    private var fullScreenBinding: Binding<CollectionSchema?> {
        Binding(
            get: {
                guard let current = schema else { return nil }
                return activeAddMode == .fullScreen ? (viewModel.schema(for: current.id) ?? current) : nil
            },
            set: { newValue in
                if newValue == nil {
                    schema = nil
                } else {
                    schema = newValue
                }
            }
        )
    }
    #endif

    public func body(content: Content) -> some View {
        #if os(iOS)
        content
            .sheet(item: popupBinding) { col in
                presentedForm(for: col)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(28)
            }
            .fullScreenCover(item: fullScreenBinding) { col in
                presentedForm(for: col)
            }
        #else
        content
            .sheet(item: popupBinding) { col in
                let isFullScreenStyle = presentationStore.addFormMode(for: col.id) == .fullScreen
                presentedForm(for: col)
                    .frame(
                        minWidth: isFullScreenStyle ? 410 : 370,
                        idealWidth: isFullScreenStyle ? 460 : 400,
                        minHeight: isFullScreenStyle ? 660 : 580,
                        idealHeight: isFullScreenStyle ? 740 : 680
                    )
            }
        #endif
    }

    @ViewBuilder
    private func presentedForm(for col: CollectionSchema) -> some View {
        let liveSchema = viewModel.schema(for: col.id) ?? col
        AddEditRecordSheetView(viewModel: viewModel, schema: liveSchema, existingRecord: nil)
            .environment(\.layoutDirection, viewModel.language.layoutDirection)
            .environment(\.locale, viewModel.language.locale)
            #if os(iOS)
            .background(KeyboardDismissal())
            .scrollDismissesKeyboard(.interactively)
            #endif
    }
}

@available(macOS 14.0, iOS 17.0, *)
public extension View {
    func collectionAddRecordPresenter(
        viewModel: ArcaAppViewModel,
        schema: Binding<CollectionSchema?>
    ) -> some View {
        modifier(CollectionAddRecordPresenter(viewModel: viewModel, schema: schema))
    }
}
