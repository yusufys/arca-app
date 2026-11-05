import SwiftUI
import CoreText

/// App-owned text uses Apple's semantic text styles. Only Arabic substitutes a
/// bundled typeface; SwiftUI continues to scale it with Dynamic Type.
enum ArcaTypography {
    static let arabicFaces = [
        "Regular": "IBMPlexSansArabic",
        "Medium": "IBMPlexSansArabic-Medm",
        "SemiBold": "IBMPlexSansArabic-SmBld",
        "Bold": "IBMPlexSansArabic-Bold"
    ]

    // Swift initializes this once, safely across callers. Register in the process,
    // because Swift Package resources live in their own bundle, not the app bundle.
    static let registeredArabicFaces: Set<String> = {
        Set(arabicFaces.compactMap { fileSuffix, postScriptName in
            guard let url = Bundle.module.url(forResource: "IBMPlexSansArabic-\(fileSuffix)", withExtension: "ttf") else { return nil }
            var error: Unmanaged<CFError>?
            let registered = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            let alreadyRegistered = error.map { CFErrorGetCode($0.takeRetainedValue()) } == CTFontManagerError.alreadyRegistered.rawValue
            return registered || alreadyRegistered ? postScriptName : nil
        })
    }()

    static func arabicFace(locale: Locale, style: Font.TextStyle, weight: Font.Weight?, boldText: Bool) -> String? {
        guard locale.language.languageCode?.identifier == "ar" else { return nil }
        let effectiveWeight = weight ?? (style == .headline ? .semibold : .regular)
        let face: String
        switch effectiveWeight {
        case .black, .heavy, .bold: face = "Bold"
        case .semibold: face = boldText ? "Bold" : "SemiBold"
        case .medium: face = boldText ? "SemiBold" : "Medium"
        default: face = boldText ? "SemiBold" : "Regular"
        }
        guard let name = arabicFaces[face] else { return nil }
        return registeredArabicFaces.contains(name) ? name : nil
    }

    static func baseSize(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 34
        case .title: return 28
        case .title2: return 22
        case .title3: return 20
        case .headline, .body: return 17
        case .callout: return 16
        case .subheadline: return 15
        case .footnote: return 13
        case .caption: return 12
        case .caption2: return 11
        @unknown default: return 17
        }
    }

    static func font(style: Font.TextStyle, weight: Font.Weight?, locale: Locale, boldText: Bool) -> Font {
        if let name = arabicFace(locale: locale, style: style, weight: weight, boldText: boldText) {
            return .custom(name, size: baseSize(for: style), relativeTo: style)
        }
        let native = Font.system(style)
        return weight.map { native.weight($0) } ?? native
    }
}

private struct ArcaFontModifier: ViewModifier {
    @Environment(\.locale) private var locale
    @Environment(\.legibilityWeight) private var legibilityWeight
    var style: Font.TextStyle
    var weight: Font.Weight?
    var defaultOnly = false

    func body(content: Content) -> some View {
        content.font(defaultOnly && locale.language.languageCode?.identifier != "ar" ? nil :
            ArcaTypography.font(style: style, weight: weight, locale: locale, boldText: legibilityWeight == .bold))
    }
}

public extension View {
    /// Use for semantic app text. Keep SF Symbols, emoji, and technical monospaced
    /// content in their native fonts. Locale changes update without restarting.
    func arcaFont(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> some View {
        modifier(ArcaFontModifier(style: style, weight: weight))
    }

    /// Supplies the Arabic body font to text without an explicit style, while
    /// retaining the platform's default font environment in English and Turkish.
    func arcaDefaultTypography() -> some View {
        modifier(ArcaFontModifier(style: .body, weight: nil, defaultOnly: true))
    }
}
