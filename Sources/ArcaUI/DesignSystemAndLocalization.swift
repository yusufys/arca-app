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

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .english: return "English"
        case .arabic: return "العربية (Arabic)"
        case .turkish: return "Türkçe (Turkish)"
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
        if let langDict = table[language], let val = langDict[key] {
            return val
        }
        return table[.english]?[key] ?? key
    }

    private static let table: [AppLanguage: [String: String]] = [
        .english: [
            "app.name": "Arca",
            "app.tagline": "Your records. Your way.",
            "app.heroPrompt": "Save something important now. Find it easily when you need it.",
            "tab.home": "Home",
            "tab.insights": "Insights",
            "tab.settings": "Settings",
            "welcome.getStarted": "Get Started",
            "welcome.localFirstTitle": "Organized, Private, Always Yours",
            "welcome.localFirstBody": "Keep car maintenance, warranties, home inventory, medical visits, and custom collections in one calm place—ready offline whenever you need them.",
            "storage.title": "Choose How Arca Stores Your Spaces",
            "storage.mode.arcaSync.title": "Arca Sync (Recommended)",
            "storage.mode.arcaSync.summary": "Records live on your device and synchronize with end-to-end encryption across up to 2 devices for free.",
            "storage.mode.localOnly.title": "On This Device Only",
            "storage.mode.localOnly.summary": "No account needed. Records and attachments stay strictly on this device unless you export a backup.",
            "storage.mode.personalCloud.title": "Personal Cloud Backup (Pro)",
            "storage.mode.personalCloud.summary": "Optional encrypted backups directly to your own iCloud Drive or Google Drive after provider policy verification.",
            "home.spaces": "Spaces",
            "home.collections": "Collections",
            "home.recentRecords": "Recent Records",
            "home.favorites": "Pinned & Favorites",
            "home.searchPlaceholder": "Search records, notes, serial numbers…",
            "home.quickAddRecord": "New Record",
            "home.newCollection": "New Collection",
            "insights.title": "Insights",
            "insights.spendingOverTime": "Spending Over Time",
            "insights.upcomingExpirations": "Upcoming Warranty Expirations",
            "insights.numericTotals": "Totals & Averages",
            "insights.categoryBreakdown": "Records by Category",
            "settings.title": "Settings & Storage",
            "settings.storageAndSync": "Sync, Devices & Cloud",
            "settings.backups": "Portable Backups & Restore",
            "settings.subscription": "Arca Pro & Plan",
            "settings.appearanceAndLanguage": "Appearance & Language",
            "settings.privacyAndSecurity": "Privacy, Encryption & Biometrics"
        ],
        .arabic: [
            "app.name": "أركا (Arca)",
            "app.tagline": "سجلاتك. بطريقتك.",
            "app.heroPrompt": "احفظ ما يهمك الآن، واعثر عليه بسهولة عندما تحتاج إليه.",
            "tab.home": "الرئيسية",
            "tab.insights": "إحصاءات",
            "tab.settings": "الإعدادات",
            "welcome.getStarted": "ابدأ الآن",
            "welcome.localFirstTitle": "منظم، خاص، وملكك دائماً",
            "welcome.localFirstBody": "احتفظ بصيانة السيارة، الضمانات، جرد المنزل، الزيارات الطبية، والمجموعات المخصصة في مكان هادئ يعمل دون اتصال بالإنترنت.",
            "storage.title": "اختر طريقة تخزين مساحاتك",
            "storage.mode.arcaSync.title": "مزامنة أركا (موصى به)",
            "storage.mode.arcaSync.summary": "تبقى السجلات على جهازك وتتم مزامنتها بتشفير تام بين الطرفين على جهازين مجاناً.",
            "storage.mode.localOnly.title": "على هذا الجهاز فقط",
            "storage.mode.localOnly.summary": "لا يتطلب حساباً. تبقى السجلات والمرفقات على جهازك فقط ما لم تقم بتصدير نسخة احتياطية.",
            "storage.mode.personalCloud.title": "نسخ احتياطي سحابي شخصي (Pro)",
            "storage.mode.personalCloud.summary": "نسخ احتياطي مشفر اختياري مباشرة إلى iCloud Drive أو Google Drive.",
            "home.spaces": "المساحات",
            "home.collections": "المجموعات",
            "home.recentRecords": "السجلات الأخيرة",
            "home.favorites": "المثبتة والمفضلة",
            "home.searchPlaceholder": "ابحث في السجلات، الملاحظات، الأرقام التسلسلية…",
            "home.quickAddRecord": "سجل جديد",
            "home.newCollection": "مجموعة جديدة",
            "insights.title": "الإحصاءات",
            "insights.spendingOverTime": "الإنفاق بمرور الوقت",
            "insights.upcomingExpirations": "انتهاء صلاحية الضمانات القريبة",
            "insights.numericTotals": "المجاميع والمتوسطات",
            "insights.categoryBreakdown": "السجلات حسب الفئة",
            "settings.title": "الإعدادات والتخزين",
            "settings.storageAndSync": "المزامنة والأجهزة والسحابة",
            "settings.backups": "النسخ الاحتياطي والاستعادة",
            "settings.subscription": "أركا برو والاشتراك",
            "settings.appearanceAndLanguage": "المظهر واللغة",
            "settings.privacyAndSecurity": "الخصوصية والتشفير والقفل الحيوي"
        ],
        .turkish: [
            "app.name": "Arca",
            "app.tagline": "Kayıtlarınız. Sizin yönteminiz.",
            "app.heroPrompt": "Önemli olanı şimdi kaydedin. İhtiyaç duyduğunuzda kolayca bulun.",
            "tab.home": "Ana Sayfa",
            "tab.insights": "Analizler",
            "tab.settings": "Ayarlar",
            "welcome.getStarted": "Başlayın",
            "welcome.localFirstTitle": "Düzenli, Gizli ve Her Zaman Sizin",
            "welcome.localFirstBody": "Araç bakımı, garantiler, ev envanteri, tıbbi ziyaretler ve özel koleksiyonlarınızı internet bağlantısı gerekmeden güvenle saklayın.",
            "storage.title": "Alanlarınızın Nasıl Saklanacağını Seçin",
            "storage.mode.arcaSync.title": "Arca Senkronizasyon (Önerilen)",
            "storage.mode.arcaSync.summary": "Kayıtlar cihazınızda tutulur ve uçtan uca şifreleme ile ücretsiz olarak 2 cihaza kadar eşitlenir.",
            "storage.mode.localOnly.title": "Yalnızca Bu Cihazda",
            "storage.mode.localOnly.summary": "Hesap gerekmez. Siz dışa aktarmadıkça kayıtlar ve ekler yalnızca bu cihazda kalır.",
            "storage.mode.personalCloud.title": "Kişisel Bulut Yedekleme (Pro)",
            "storage.mode.personalCloud.summary": "iCloud Drive veya Google Drive hesabınıza doğrudan uçtan uca şifreli yedekleme.",
            "home.spaces": "Alanlar",
            "home.collections": "Koleksiyonlar",
            "home.recentRecords": "Son Kayıtlar",
            "home.favorites": "Sabitlenenler ve Favoriler",
            "home.searchPlaceholder": "Kayıtlarda, notlarda, seri numaralarında ara…",
            "home.quickAddRecord": "Yeni Kayıt",
            "home.newCollection": "Yeni Koleksiyon",
            "insights.title": "Analizler",
            "insights.spendingOverTime": "Zaman İçinde Harcamalar",
            "insights.upcomingExpirations": "Yaklaşan Garanti Bitiş Tarihleri",
            "insights.numericTotals": "Toplamlar ve Ortalamalar",
            "insights.categoryBreakdown": "Kategoriye Göre Kayıtlar",
            "settings.title": "Ayarlar ve Depolama",
            "settings.storageAndSync": "Senkronizasyon ve Cihazlar",
            "settings.backups": "Taşınabilir Yedekleme ve Geri Yükleme",
            "settings.subscription": "Arca Pro ve Abonelik",
            "settings.appearanceAndLanguage": "Görünüm ve Dil",
            "settings.privacyAndSecurity": "Gizlilik, Şifreleme ve Biyometrik Kilit"
        ]
    ]
}

// MARK: - Design Tokens (Warm Stone Canvas + Crisp Elevated Cards + Deep Slate Teal Accent)

public enum ArcaTheme {
    /// Restrained deep slate teal/blue primary accent (`#1F5673`)
    public static let accent = Color(red: 0.122, green: 0.337, blue: 0.451)
    public static let accentSoft = Color(red: 0.122, green: 0.337, blue: 0.451).opacity(0.11)
    public static let secondaryEmerald = Color(red: 0.165, green: 0.482, blue: 0.388)
    public static let warmAmber = Color(red: 0.725, green: 0.431, blue: 0.129)
    public static let plumSensitive = Color(red: 0.525, green: 0.235, blue: 0.376)
    public static let dangerRed = Color(red: 0.765, green: 0.212, blue: 0.212)

    public static func canvasBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.067, green: 0.075, blue: 0.090) // #111317
            : Color(red: 0.961, green: 0.957, blue: 0.941) // #F5F4F0 warm alabaster stone
    }

    public static func cardBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.114, green: 0.125, blue: 0.149) // #1D2026
            : Color.white
    }

    public static func subtleFieldBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.153, green: 0.169, blue: 0.196) // #272B32
            : Color(red: 0.945, green: 0.941, blue: 0.922) // #F1F0EB
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
            .font(.system(size: 15, weight: .semibold, design: .rounded))
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
            .font(.system(size: 14, weight: .semibold, design: .rounded))
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
                        .font(.system(size: 12, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
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
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(iconTint)
                    }
                    Text(title.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 4)
            }

            VStack(alignment: .leading, spacing: 12) {
                if let subtitle {
                    Text(subtitle)
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
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
            }
            if isSecure {
                SecureField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
            } else {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
            }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
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
    public let placeholder: String
    @Environment(\.colorScheme) private var colorScheme

    public init(text: Binding<String>, placeholder: String) {
        self._text = text
        self.placeholder = placeholder
    }

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 15))

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
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

    public var body: some View {
        VStack(spacing: 6) {
            Capsule()
                .fill(Color.secondary.opacity(0.28))
                .frame(width: 38, height: 5)
                .padding(.top, 8)

            HStack {
                if let leadingLabel, let leadingAction {
                    Button(action: leadingAction) {
                        Text(leadingLabel)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.secondary.opacity(0.10)))
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer().frame(width: 64)
                }

                Spacer()

                VStack(spacing: 1) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if let trailingLabel, let trailingAction {
                    Button(action: trailingAction) {
                        Text(trailingLabel)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(trailingDisabled ? Color.secondary.opacity(0.35) : ArcaTheme.accent)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(trailingDisabled)
                } else {
                    Spacer().frame(width: 64)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.5)
        }
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
                    ? "\(count) change\(count == 1 ? "" : "s") saved safely on this device and queued for sync."
                    : "You can read, create, and edit records without internet access.",
                tint: ArcaTheme.warmAmber,
                actionLabel: nil
            )
        case .syncConflictsDetected(let count):
            bannerCard(
                icon: "exclamationmark.arrow.triangle.2.circlepath",
                title: "\(count) Sync Edit Conflict\(count == 1 ? "" : "s") Preserved",
                subtitle: "Both versions were kept safely so nothing was lost. Tap Review to choose which edits to keep.",
                tint: ArcaTheme.plumSensitive,
                actionLabel: "Review"
            )
        case .failedUpload(let message):
            bannerCard(
                icon: "icloud.slash",
                title: "Attachment Upload Paused",
                subtitle: "\(message) Your local record and file remain safe on this device.",
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
        case .permissionDenied(let resource):
            bannerCard(
                icon: "lock.shield",
                title: "\(resource) Access Not Granted",
                subtitle: "You can enable permission in System Settings or continue attaching files from the Files picker.",
                tint: .secondary,
                actionLabel: "Dismiss"
            )
        case .restoreValidationFailed(let reason):
            bannerCard(
                icon: "xmark.shield.fill",
                title: "Backup Restore Rejected Safely",
                subtitle: "\(reason) Your live spaces were not modified.",
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
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            if let actionLabel, let onAction {
                Button(action: onAction) {
                    Text(actionLabel)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
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
