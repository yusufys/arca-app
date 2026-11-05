import SwiftUI
import ArcaCore

/// Disambiguates the `@propertyWrapper public struct SwiftUI.State<Value>` from the Swift 6.4 `@attached macro State()`
/// when building with Command Line Tools where `libSwiftUIMacros.dylib` is not bundled.
public typealias ViewState<Value> = SwiftUI.State<Value>

// MARK: - Localization Support (English, Arabic RTL, Turkish)

public enum AppLanguage: String, CaseIterable, Codable, Sendable, Identifiable {
    case english = "en"
    case arabic = "ar"
    case turkish = "tr"

    static var preferred: AppLanguage {
        if let stored = UserDefaults.standard.string(forKey: "arca.language"),
           let language = AppLanguage(rawValue: stored) { return language }
        let match = Bundle.preferredLocalizations(from: AppLanguage.allCases.map(\.rawValue)).first
        return match.flatMap(AppLanguage.init(rawValue:)) ?? .english
    }

    /// Uses Apple's compiled String Catalog in this package, selected by the in-app language.
    public var localizationBundle: Bundle {
        guard let path = Bundle.module.path(forResource: rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .module }
        return bundle
    }

    public func localized(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), bundle: localizationBundle, locale: locale)
    }

    public func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: localized(key), locale: locale, arguments: arguments)
    }
    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .english: return "English"
        case .arabic: return "العربية"
        case .turkish: return "Türkçe"
        }
    }

    public var layoutDirection: LayoutDirection {
        switch self {
        case .arabic: return .rightToLeft
        case .english, .turkish: return .leftToRight
        }
    }

    public var locale: Locale {
        Locale(identifier: rawValue)
    }
}

public enum AppAppearanceMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case light = "light"
    case dark = "dark"
    case system = "system"

    public var id: String { rawValue }

    public var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}

public enum ArcaStrings {
    public static func text(_ key: String, language: AppLanguage) -> String {
        language.localized(key)
    }
}

// MARK: - Arca archive palette (see BRAND.md)

public enum ArcaTheme {
    /// Forest ink, sampled for readable white action labels.
    public static let accent = Color(red: 0.122, green: 0.365, blue: 0.247)
    public static let accentSoft = accent.opacity(0.11)
    public static let secondaryEmerald = Color(red: 0.165, green: 0.482, blue: 0.388)
    public static let warmAmber = Color(red: 0.725, green: 0.431, blue: 0.129)
    public static let plumSensitive = Color(red: 0.525, green: 0.235, blue: 0.376)
    public static let dangerRed = Color(red: 0.765, green: 0.212, blue: 0.212)

    public static func canvasBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.055, green: 0.102, blue: 0.078) // #0E1A14
            : Color(red: 0.976, green: 0.961, blue: 0.914) // #F9F5E9
    }

    public static func cardBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.090, green: 0.157, blue: 0.122) // #17281F
            : Color(red: 1, green: 0.992, blue: 0.961) // #FFFDF5
    }

    public static func subtleFieldBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.137, green: 0.208, blue: 0.165) // #23352A
            : Color(red: 0.941, green: 0.922, blue: 0.863) // #F0EBDC
    }

    public static func cardBorder(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.06)
    }

    public static func color(fromHex hex: String) -> Color {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let intVal = UInt64(cleaned, radix: 16) else {
            return accent
        }
        let r = Double((intVal >> 16) & 0xFF) / 255.0
        let g = Double((intVal >> 8) & 0xFF) / 255.0
        let b = Double(intVal & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}

// MARK: - Custom iOS-Native Button Styles & Card Surfaces (Identical on macOS & iOS)

@available(macOS 14.0, iOS 17.0, *)
public struct ArcaPrimaryButtonStyle: ButtonStyle {
    public var tint: Color
    public var isFullWidth: Bool
    @Environment(\.isEnabled) private var isEnabled

    public init(tint: Color = ArcaTheme.accent, isFullWidth: Bool = true) {
        self.tint = tint
        self.isFullWidth = isFullWidth
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        isEnabled
                            ? LinearGradient(
                                colors: [tint.opacity(0.95), tint],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                              )
                            : LinearGradient(
                                colors: [Color.secondary.opacity(0.35), Color.secondary.opacity(0.35)],
                                startPoint: .top,
                                endPoint: .bottom
                              )
                    )
            )
            .shadow(color: isEnabled ? tint.opacity(0.22) : .clear, radius: 8, x: 0, y: 4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

@available(macOS 14.0, iOS 17.0, *)
public struct ArcaSecondaryButtonStyle: ButtonStyle {
    public var tint: Color
    public var isFullWidth: Bool

    public init(tint: Color = ArcaTheme.accent, isFullWidth: Bool = false) {
        self.tint = tint
        self.isFullWidth = isFullWidth
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.18 : 0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(tint.opacity(0.24), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

@available(macOS 14.0, iOS 17.0, *)
public struct ArcaPillActionButton: View {
    @Environment(\.locale) private var locale
    private var language: AppLanguage { AppLanguage(rawValue: locale.language.languageCode?.identifier ?? "en") ?? .english }

    public let title: String
    public let icon: String?
    public var tint: Color = ArcaTheme.accent
    public let action: () -> Void

    public init(_ title: String, icon: String? = nil, tint: Color = ArcaTheme.accent, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.tint = tint
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.footnote.weight(.bold))
                }
                Text(language.localized(title))
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(tint.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }
}

/// Elevated iOS-style grouped section card that looks identical on iPhone and macOS.
@available(macOS 14.0, iOS 17.0, *)
public struct ArcaSectionCard<Content: View>: View {
    @Environment(\.locale) private var locale
    private var language: AppLanguage { AppLanguage(rawValue: locale.language.languageCode?.identifier ?? "en") ?? .english }

    public let title: String?
    public let subtitle: String?
    public let icon: String?
    public let iconTint: Color
    @ViewBuilder public let content: () -> Content
    @Environment(\.colorScheme) private var colorScheme

    public init(
        title: String? = nil,
        subtitle: String? = nil,
        icon: String? = nil,
        iconTint: Color = ArcaTheme.accent,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.iconTint = iconTint
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                HStack(spacing: 6) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(iconTint)
                    }
                    Text(verbatim: title.uppercased(with: locale))
                        .accessibilityAddTraits(.isHeader)
                        .font(.caption.weight(.bold))
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 4)
            }

            VStack(alignment: .leading, spacing: 12) {
                if let subtitle {
                    Text(verbatim: subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(ArcaTheme.cardBackground(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(ArcaTheme.cardBorder(for: colorScheme), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.035), radius: 10, x: 0, y: 4)
        }
    }
}

/// Clean iOS-style text input field without ugly macOS NSTextField square focus borders.
@available(macOS 14.0, iOS 17.0, *)
public struct ArcaStyledTextField: View {
    @Environment(\.locale) private var locale
    private var language: AppLanguage { AppLanguage(rawValue: locale.language.languageCode?.identifier ?? "en") ?? .english }

    public let placeholder: String
    @Binding public var text: String
    public var icon: String?
    public var isSecure: Bool
    @Environment(\.colorScheme) private var colorScheme

    public init(_ placeholder: String, text: Binding<String>, icon: String? = nil, isSecure: Bool = false) {
        self.placeholder = placeholder
        self._text = text
        self.icon = icon
        self.isSecure = isSecure
    }

    public var body: some View {
        HStack(spacing: 10) {
            if let icon {
                Image(systemName: icon)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
            }
            if isSecure {
                SecureField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .accessibilityLabel(placeholder)
            } else {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .accessibilityLabel(placeholder)
            }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel(language.format("Clear %@", placeholder))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(ArcaTheme.subtleFieldBackground(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(ArcaTheme.cardBorder(for: colorScheme), lineWidth: 1)
        )
    }
}

/// Clean iOS-style search bar embedded directly in the screen content so it looks like a native mobile search bar on both Mac and iPhone.
@available(macOS 14.0, iOS 17.0, *)
public struct ArcaSearchBar: View {
    @Binding public var text: String
    @Environment(\.locale) private var locale
    private var language: AppLanguage { AppLanguage(rawValue: locale.language.languageCode?.identifier ?? "en") ?? .english }

    public let placeholder: String
    @Environment(\.colorScheme) private var colorScheme

    public init(text: Binding<String>, placeholder: String) {
        self._text = text
        self.placeholder = placeholder
    }

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.body)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(ArcaTheme.cardBackground(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(ArcaTheme.cardBorder(for: colorScheme), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.16 : 0.025), radius: 6, x: 0, y: 2)
    }
}

/// Modal Sheet Header Bar for consistent iOS sheet appearance across platforms.
@available(macOS 14.0, iOS 17.0, *)
public struct ArcaSheetHeaderBar: View {
    @Environment(\.locale) private var locale
    private var language: AppLanguage { AppLanguage(rawValue: locale.language.languageCode?.identifier ?? "en") ?? .english }
    public let title: String
    public var subtitle: String? = nil
    public var leadingLabel: String? = "Close"
    public var leadingAction: (() -> Void)?
    public var trailingLabel: String? = nil
    public var trailingDisabled: Bool = false
    public var trailingAction: (() -> Void)?

    public init(
        title: String,
        subtitle: String? = nil,
        leadingLabel: String? = "Close",
        leadingAction: (() -> Void)? = nil,
        trailingLabel: String? = nil,
        trailingDisabled: Bool = false,
        trailingAction: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.leadingLabel = leadingLabel
        self.leadingAction = leadingAction
        self.trailingLabel = trailingLabel
        self.trailingDisabled = trailingDisabled
        self.trailingAction = trailingAction
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public var body: some View {
        VStack(spacing: 6) {
            Capsule().fill(Color.secondary.opacity(0.28))
                .frame(width: 38, height: 5).padding(.top, 8)
                .accessibilityHidden(true)
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 8) {
                        titleBlock
                        HStack { leadingControl; Spacer(); trailingControl }
                    }
                } else {
                    HStack { leadingControl; Spacer(); titleBlock; Spacer(); trailingControl }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
    }

    private var titleBlock: some View {
        VStack(spacing: 1) {
            Text(verbatim: title).font(.body.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(verbatim: subtitle).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var leadingControl: some View {
        if let leadingLabel, let leadingAction {
            Button(action: leadingAction) {
                Text(language.localized(leadingLabel))
                    .font(.body.weight(.medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(Color.secondary.opacity(0.10)))
                    .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain)
        } else { Color.clear.frame(width: 64, height: 1).accessibilityHidden(true) }
    }

    @ViewBuilder private var trailingControl: some View {
        if let trailingLabel, let trailingAction {
            Button(action: trailingAction) {
                Text(language.localized(trailingLabel))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Capsule().fill(trailingDisabled ? Color.secondary.opacity(0.35) : ArcaTheme.accent))
                    .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(trailingDisabled)
        } else { Color.clear.frame(width: 64, height: 1).accessibilityHidden(true) }
    }
}

// MARK: - Reusable State Banners (Offline, Conflict, Storage Full, Failed Upload, Permission Denied)

public enum OperationalBannerState: Equatable, Hashable, Sendable, Identifiable {
    case normal
    case offlineQueued(pendingCount: Int)
    case syncConflictsDetected(count: Int)
    case failedUpload(message: String)
    case storageQuotaFull
    case thirdDeviceLimitBlocked
    case permissionDenied(resource: String)
    case restoreValidationFailed(reason: String)

    public var id: String {
        switch self {
        case .normal: return "normal"
        case .offlineQueued(let c): return "offline_\(c)"
        case .syncConflictsDetected(let c): return "conflict_\(c)"
        case .failedUpload(let m): return "failed_\(m)"
        case .storageQuotaFull: return "storage_full"
        case .thirdDeviceLimitBlocked: return "third_device"
        case .permissionDenied(let r): return "perm_\(r)"
        case .restoreValidationFailed(let r): return "restore_fail_\(r)"
        }
    }
}

@available(macOS 14.0, iOS 17.0, *)
public struct OperationalStateBannerView: View {
    @Environment(\.locale) private var locale
    private var language: AppLanguage { AppLanguage(rawValue: locale.language.languageCode?.identifier ?? "en") ?? .english }
    public let state: OperationalBannerState
    public var onAction: (() -> Void)?

    public init(state: OperationalBannerState, onAction: (() -> Void)? = nil) {
        self.state = state
        self.onAction = onAction
    }

    public var body: some View {
        switch state {
        case .normal:
            EmptyView()
        case .offlineQueued(let count):
            bannerCard(
                icon: "wifi.slash",
                title: "Working Offline • Local Storage Active",
                subtitle: count > 0
                    ? language.format("count.pendingChanges", count)
                    : "You can read, create, and edit records without internet access.",
                tint: ArcaTheme.warmAmber,
                actionLabel: nil
            )
        case .syncConflictsDetected(let count):
            bannerCard(
                icon: "exclamationmark.arrow.triangle.2.circlepath",
                title: language.format("count.conflicts", count),
                subtitle: "Both versions were kept safely so nothing was lost. Tap Review to choose which edits to keep.",
                tint: ArcaTheme.plumSensitive,
                actionLabel: "Review"
            )
        case .failedUpload:
            bannerCard(
                icon: "icloud.slash",
                title: "Attachment Upload Paused",
                subtitle: "Your local record and file remain safe on this device. Retry when connected.",
                tint: ArcaTheme.dangerRed,
                actionLabel: "Retry"
            )
        case .storageQuotaFull:
            bannerCard(
                icon: "externaldrive.badge.exclamationmark",
                title: "Cloud Sync Storage Allowance Reached",
                subtitle: "New records continue saving locally on this device. Free up cloud space or upgrade to Arca Pro to resume sync.",
                tint: ArcaTheme.warmAmber,
                actionLabel: "Manage"
            )
        case .thirdDeviceLimitBlocked:
            bannerCard(
                icon: "iphone.slash",
                title: "Free Plan 2-Device Sync Limit Reached",
                subtitle: "Local records remain accessible. Revoke an older device or upgrade to Arca Pro to sync this device.",
                tint: ArcaTheme.warmAmber,
                actionLabel: "Devices"
            )
        case .permissionDenied:
            bannerCard(
                icon: "lock.shield",
                title: "Permission Required",
                subtitle: "You can enable permission in System Settings or continue attaching files from the Files picker.",
                tint: .secondary,
                actionLabel: "Dismiss"
            )
        case .restoreValidationFailed:
            bannerCard(
                icon: "xmark.shield.fill",
                title: "Backup Restore Rejected Safely",
                subtitle: "The backup could not be verified. Your current spaces were not changed.",
                tint: ArcaTheme.dangerRed,
                actionLabel: "Dismiss"
            )
        }
    }

    private func bannerCard(
        icon: String,
        title: String,
        subtitle: String,
        tint: Color,
        actionLabel: String?
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.16))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tint)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(language.localized(title))
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.primary)
                Text(language.localized(subtitle))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            if let actionLabel, let onAction {
                Button(action: onAction) {
                    Text(language.localized(actionLabel))
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(tint))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(tint.opacity(0.28), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}
