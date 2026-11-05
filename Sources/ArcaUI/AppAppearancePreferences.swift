import Foundation
import SwiftUI
import ArcaCore

// MARK: - App Accent Theme Options & Persistent Appearance Preferences

/// The six curated app-level accent color options from the Arca redesign.
/// Applies to Home, Spaces, Insights, Onboarding, AI creation, and App Settings.
/// Per-collection colors remain independent (`CollectionSchema.colorHex`).
public enum AppAccentColorOption: String, CaseIterable, Codable, Sendable, Identifiable {
    case forestEmerald = "#1F5D3F"
    case midnightSapphire = "#1E3A8A"
    case terracottaClay = "#7C2D12"
    case royalPlum = "#581C87"
    case obsidianInk = "#18181B"
    case deepPine = "#0F3F2A"

    public static let defaultOption: AppAccentColorOption = .forestEmerald

    public var id: String { rawValue }

    public var hex: String { rawValue }

    public var color: Color {
        ArcaTheme.color(fromHex: rawValue)
    }

    /// Readable foreground accent color when rendered as text or glyphs against dark or light card surfaces.
    public func foregroundTint(for scheme: ColorScheme) -> Color {
        guard scheme == .dark else { return color }
        switch self {
        case .forestEmerald:
            return Color(red: 0.30, green: 0.76, blue: 0.54)
        case .midnightSapphire:
            return Color(red: 0.45, green: 0.64, blue: 0.98)
        case .terracottaClay:
            return Color(red: 0.95, green: 0.56, blue: 0.35)
        case .royalPlum:
            return Color(red: 0.78, green: 0.52, blue: 0.98)
        case .obsidianInk:
            return Color(red: 0.86, green: 0.87, blue: 0.90)
        case .deepPine:
            return Color(red: 0.34, green: 0.74, blue: 0.55)
        }
    }

    public var nameKey: String {
        switch self {
        case .forestEmerald: return "Forest Emerald"
        case .midnightSapphire: return "Midnight Sapphire"
        case .terracottaClay: return "Terracotta Clay"
        case .royalPlum: return "Royal Plum"
        case .obsidianInk: return "Obsidian Ink"
        case .deepPine: return "Deep Pine"
        }
    }

    public var tagKey: String {
        switch self {
        case .forestEmerald: return "Arca Default"
        case .midnightSapphire: return "Classic Blue"
        case .terracottaClay: return "Warm Earth"
        case .royalPlum: return "Regal Violet"
        case .obsidianInk: return "Minimal Monochrome"
        case .deepPine: return "Archival Green"
        }
    }

    public func localizedName(in language: AppLanguage) -> String {
        language.localized(nameKey)
    }

    public func localizedTag(in language: AppLanguage) -> String {
        language.localized(tagKey)
    }

    /// Normalizes a hex string (e.g., `"1f5d3f"` or `" #1F5D3F "`) into canonical `"#RRGGBB"` uppercase form.
    public static func normalizedHex(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .uppercased()
        guard trimmed.count == 6,
              trimmed.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789ABCDEF").contains($0) }) else {
            return nil
        }
        return "#" + trimmed
    }

    /// Resolves a stored hex string to a valid `AppAccentColorOption`, falling back safely to `.forestEmerald`.
    public static func resolve(from rawHex: String?) -> AppAccentColorOption {
        guard let normalized = normalizedHex(rawHex),
              let match = AppAccentColorOption(rawValue: normalized) else {
            return .defaultOption
        }
        return match
    }
}

/// Persistent presentation-only store for app-level accent color and appearance mode.
/// Uses `UserDefaults` and never stores personal record contents or secrets.
public struct AppAppearancePreferencesStore: Sendable {
    public static let accentColorDefaultsKey = "arca.appearance.appAccentHex"
    public static let appearanceModeDefaultsKey = "arca.appearance.mode"

    nonisolated(unsafe) private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadAccentColor() -> AppAccentColorOption {
        let stored = defaults.string(forKey: Self.accentColorDefaultsKey)
        return AppAccentColorOption.resolve(from: stored)
    }

    public func saveAccentColor(_ option: AppAccentColorOption) {
        defaults.set(option.rawValue, forKey: Self.accentColorDefaultsKey)
    }

    public func saveAccentColor(hex: String) -> AppAccentColorOption {
        let resolved = AppAccentColorOption.resolve(from: hex)
        saveAccentColor(resolved)
        return resolved
    }

    public func loadAppearanceMode() -> AppAppearanceMode {
        guard let raw = defaults.string(forKey: Self.appearanceModeDefaultsKey),
              let mode = AppAppearanceMode(rawValue: raw) else {
            return .light
        }
        return mode
    }

    public func saveAppearanceMode(_ mode: AppAppearanceMode) {
        defaults.set(mode.rawValue, forKey: Self.appearanceModeDefaultsKey)
    }

    public func reset() {
        defaults.removeObject(forKey: Self.accentColorDefaultsKey)
        defaults.removeObject(forKey: Self.appearanceModeDefaultsKey)
    }
}

// MARK: - SwiftUI Environment Integration

private struct ArcaAppAccentOptionEnvironmentKey: EnvironmentKey {
    static let defaultValue: AppAccentColorOption = .defaultOption
}

private struct ArcaAppAccentColorEnvironmentKey: EnvironmentKey {
    static let defaultValue: Color = AppAccentColorOption.defaultOption.color
}

public extension EnvironmentValues {
    var arcaAppAccentOption: AppAccentColorOption {
        get { self[ArcaAppAccentOptionEnvironmentKey.self] }
        set { self[ArcaAppAccentOptionEnvironmentKey.self] = newValue }
    }

    var arcaAppAccentColor: Color {
        get { self[ArcaAppAccentColorEnvironmentKey.self] }
        set { self[ArcaAppAccentColorEnvironmentKey.self] = newValue }
    }
}

@available(macOS 14.0, iOS 17.0, *)
public struct ArcaAppAccentEnvironmentModifier: ViewModifier {
    @AppStorage(AppAppearancePreferencesStore.accentColorDefaultsKey)
    private var storedAccentHex: String = AppAccentColorOption.defaultOption.rawValue

    public init() {}

    private var activeOption: AppAccentColorOption {
        AppAccentColorOption.resolve(from: storedAccentHex)
    }

    public func body(content: Content) -> some View {
        let option = activeOption
        content
            .environment(\.arcaAppAccentOption, option)
            .environment(\.arcaAppAccentColor, option.color)
            .tint(option.color)
    }
}

@available(macOS 14.0, iOS 17.0, *)
public extension View {
    /// Injects the persisted app accent option and color into the SwiftUI environment hierarchy.
    func arcaApplyAppAccentEnvironment() -> some View {
        modifier(ArcaAppAccentEnvironmentModifier())
    }
}
