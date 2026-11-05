import SwiftUI
import UniformTypeIdentifiers
import Charts
import ArcaCore

// MARK: - Screen 13: Basic Useful Insights (Swift Charts)

@available(macOS 14.0, iOS 17.0, *)
public struct InsightsScreenView: View {
    @Bindable var viewModel: ArcaAppViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppAppearancePreferencesStore.accentColorDefaultsKey)
    private var storedAccentHex: String = AppAccentColorOption.defaultOption.rawValue

    public init(viewModel: ArcaAppViewModel) {
        self.viewModel = viewModel
    }

    private var appAccentOption: AppAccentColorOption {
        AppAccentColorOption.resolve(from: storedAccentHex)
    }

    private var appAccentColor: Color {
        appAccentOption.color
    }

    private var appForegroundTint: Color {
        appAccentOption.foregroundTint(for: colorScheme)
    }

    private var report: SpaceInsightsReport {
        viewModel.currentSpaceInsights
    }

    public var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    // Custom iOS Large Title Header
                    VStack(alignment: .leading, spacing: 3) {
                        Text((viewModel.currentSpace?.name ?? "SPACE").uppercased())
                            .arcaFont(.caption, weight: .bold)
                            .tracking(0.6)
                            .foregroundStyle(appForegroundTint)
                        Text(ArcaStrings.text("insights.title", language: viewModel.language))
                            .arcaFont(.largeTitle, weight: .bold)
                    }

                    // Summary KPIs
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: dynamicTypeSize.isAccessibilitySize ? 1 : 3), spacing: 10) {
                        kpiCard(title: viewModel.language.localized("Records"), value: "\(report.totalRecords)", icon: "doc.text.fill", tint: appForegroundTint)
                        kpiCard(title: viewModel.language.localized("Pinned"), value: "\(report.favoriteRecords)", icon: "pin.fill", tint: ArcaTheme.warmAmber)
                        kpiCard(title: viewModel.language.localized("Files"), value: "\(report.totalAttachments)", icon: "paperclip", tint: ArcaTheme.secondaryEmerald)
                    }

                    // Upcoming Warranty Expirations
                    if !report.upcomingExpirations.isEmpty {
                        ArcaSectionCard(
                            title: ArcaStrings.text("insights.upcomingExpirations", language: viewModel.language),
                            icon: "checkmark.shield.fill",
                            iconTint: ArcaTheme.warmAmber
                        ) {
                            VStack(spacing: 10) {
                                ForEach(report.upcomingExpirations) { item in
                                    let isUrgent = item.isExpired || item.daysRemaining <= 30
                                    let badgeTint = isUrgent ? ArcaTheme.warmAmber : ArcaTheme.secondaryEmerald
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.itemTitle)
                                                .arcaFont(.subheadline, weight: .bold)
                                            Text(viewModel.language.format("Expires %@", item.expirationDate.formatted(locale: viewModel.language.locale)))
                                                .arcaFont(.footnote)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text(item.isExpired ? viewModel.language.localized("Expired") : viewModel.language.format("In %d days", item.daysRemaining))
                                            .arcaFont(.caption, weight: .bold)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(Capsule().fill(badgeTint.opacity(0.14)))
                                            .foregroundStyle(badgeTint)
                                    }
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(ArcaTheme.subtleFieldBackground(for: colorScheme))
                                    )
                                }
                            }
                        }
                    }

                    // Spending Over Time Chart
                    if !report.spendingOverTime.isEmpty {
                        ArcaSectionCard(
                            title: ArcaStrings.text("insights.spendingOverTime", language: viewModel.language),
                            icon: "chart.bar.fill",
                            iconTint: appForegroundTint
                        ) {
                            Chart(report.spendingOverTime) { point in
                                BarMark(
                                    x: .value("Month", point.yearMonth),
                                    y: .value("Amount", point.totalAmount)
                                )
                                .foregroundStyle(appForegroundTint.gradient)
                                .cornerRadius(7)
                            }
                            .frame(height: 185)
                            .padding(.top, 4)
                        }
                    }

                    // Totals & Averages for Numerical / Currency Fields
                    if !report.numericSummaries.isEmpty {
                        ArcaSectionCard(
                            title: ArcaStrings.text("insights.numericTotals", language: viewModel.language),
                            icon: "sum",
                            iconTint: appForegroundTint
                        ) {
                            VStack(spacing: 10) {
                                ForEach(report.numericSummaries) { summary in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(summary.fieldLabel)
                                                .arcaFont(.subheadline, weight: .bold)
                                            Text(summary.collectionName + " • " + viewModel.language.format("count.records", summary.count))
                                                .arcaFont(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(summary.formattedSum)
                                                .arcaFont(.body, weight: .bold)
                                                .foregroundStyle(appForegroundTint)
                                            Text(viewModel.language.format("Avg %@", summary.formattedAverage))
                                                .arcaFont(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(ArcaTheme.subtleFieldBackground(for: colorScheme))
                                    )
                                }
                            }
                        }
                    }

                    // Records Grouped by Select Field
                    if !report.selectDistributions.isEmpty {
                        ArcaSectionCard(
                            title: ArcaStrings.text("insights.categoryBreakdown", language: viewModel.language),
                            icon: "chart.pie.fill",
                            iconTint: ArcaTheme.secondaryEmerald
                        ) {
                            Chart(report.selectDistributions) { dist in
                                BarMark(
                                    x: .value(viewModel.language.localized("Count"), dist.count),
                                    y: .value(viewModel.language.localized("Category"), dist.optionLabel)
                                )
                                .foregroundStyle(ArcaTheme.secondaryEmerald.gradient)
                                .cornerRadius(6)
                            }
                            .frame(height: max(110, CGFloat(report.selectDistributions.count * 34)))
                        }
                    }
                }
                .padding(18)
            }
            .background(ArcaTheme.canvasBackground(for: colorScheme))
            .arcaApplyAppAccentEnvironment()
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
        }
    }

    private func kpiCard(title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(tint.opacity(0.14))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .arcaFont(.title2, weight: .bold)
                Text(title)
                    .arcaFont(.caption, weight: .medium)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(ArcaTheme.cardBackground(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(ArcaTheme.cardBorder(for: colorScheme), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.16 : 0.025), radius: 6, x: 0, y: 2)
    }
}

// MARK: - Screen 19: Settings Hub + Navigation to Screens 14, 15, 16, 17, 18

@available(macOS 14.0, iOS 17.0, *)
public struct SettingsHubScreenView: View {
    @Environment(\.arcaSubscriptionScreen) private var subscriptionScreen
    @Bindable var viewModel: ArcaAppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppAppearancePreferencesStore.accentColorDefaultsKey)
    private var storedAccentHex: String = AppAccentColorOption.defaultOption.rawValue

    @ViewState private var appColorDropdownOpen: Bool = false
    @ViewState private var showingSpaceManager: Bool = false

    public init(viewModel: ArcaAppViewModel) {
        self.viewModel = viewModel
    }

    private var appAccentOption: AppAccentColorOption {
        AppAccentColorOption.resolve(from: storedAccentHex)
    }

    private var appAccentColor: Color {
        appAccentOption.color
    }

    private var appForegroundTint: Color {
        appAccentOption.foregroundTint(for: colorScheme)
    }

    public var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    // Header
                    VStack(alignment: .leading, spacing: 3) {
                        Text(viewModel.language.localized("ARCA PREFERENCES & STORAGE"))
                            .arcaFont(.caption, weight: .bold)
                            .tracking(0.6)
                            .foregroundStyle(appForegroundTint)
                        Text(ArcaStrings.text("settings.title", language: viewModel.language))
                            .arcaFont(.largeTitle, weight: .bold)
                            .accessibilityAddTraits(.isHeader)
                    }

                    // 1. App Theme Color (6-Color Persistent Accent Picker)
                    appThemeColorCard

                    // 2. Spaces Selection & Quick Switcher
                    spacesSelectionCard

                    // 3. Current Space Storage & Backups
                    if let current = viewModel.currentSpace {
                        ArcaSectionCard(title: viewModel.language.format("Current Space: %@", current.name), icon: current.iconName) {
                            VStack(spacing: 10) {
                                NavigationLink {
                                    StorageModeMigrationScreenView(viewModel: viewModel, space: current)
                                } label: {
                                    settingsRow(
                                        icon: "externaldrive.badge.checkmark",
                                        tint: appForegroundTint,
                                        title: viewModel.language.localized("Storage Mode & Migration Preview"),
                                        subtitle: current.storageMode == .arcaSync ? viewModel.language.localized("Arca Sync (E2EE)") : viewModel.language.localized("On This Device Only")
                                    )
                                }
                                .buttonStyle(.plain)

                                Divider().opacity(0.45)

                                NavigationLink {
                                    BackupExportRestoreScreenView(viewModel: viewModel)
                                } label: {
                                    settingsRow(
                                        icon: "shippingbox.and.arrow.backward.fill",
                                        tint: ArcaTheme.secondaryEmerald,
                                        title: ArcaStrings.text("settings.backups", language: viewModel.language),
                                        subtitle: viewModel.language.localized("Verified .arcaarchive export & staged restore")
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // 4. Sync, Devices & Conflicts
                    ArcaSectionCard(title: ArcaStrings.text("settings.storageAndSync", language: viewModel.language), icon: "icloud.fill") {
                        VStack(spacing: 10) {
                            NavigationLink {
                                SyncStatusAndConflictsScreenView(viewModel: viewModel)
                            } label: {
                                settingsRow(
                                    icon: "arrow.triangle.2.circlepath.icloud.fill",
                                    tint: appForegroundTint,
                                    title: viewModel.language.localized("Sync Status, Outbox & Conflicts"),
                                    subtitle: viewModel.cloudAccountConnected ? viewModel.syncStatus : viewModel.language.localized("Sign in to sync your cloud Spaces"),
                                    badge: viewModel.syncConflicts.isEmpty ? nil : viewModel.language.format("count.conflicts", viewModel.syncConflicts.count)
                                )
                            }
                            .buttonStyle(.plain)

                            Divider().opacity(0.45)

                            NavigationLink {
                                ActiveDeviceManagementScreenView(viewModel: viewModel)
                            } label: {
                                settingsRow(
                                    icon: "laptopcomputer.and.iphone",
                                    tint: ArcaTheme.warmAmber,
                                    title: viewModel.language.localized("Active Synced Devices"),
                                    subtitle: viewModel.language.localized("Enrolled devices & key rotation"),
                                    badge: "\(viewModel.enrolledDevices.count)/\(viewModel.maxAllowedDevices)"
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // 5. Subscription & Billing
                    ArcaSectionCard(title: ArcaStrings.text("settings.subscription", language: viewModel.language), icon: "sparkles") {
                        NavigationLink {
                            subscriptionScreen
                        } label: {
                            settingsRow(
                                icon: "crown.fill",
                                tint: ArcaTheme.warmAmber,
                                title: viewModel.language.localized("Arca Plan & Quotas"),
                                subtitle: viewModel.language.localized("Plans, purchases and restore"),
                                badge: viewModel.isProSubscriber ? viewModel.language.localized("Arca Pro") : viewModel.language.localized("Free Plan")
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    // 6. Appearance & Language
                    ArcaSectionCard(title: ArcaStrings.text("settings.appearanceAndLanguage", language: viewModel.language), icon: "paintbrush.fill") {
                        let choicesLayout = dynamicTypeSize.isAccessibilitySize
                            ? AnyLayout(VStackLayout(spacing: 8))
                            : AnyLayout(HStackLayout(spacing: 8))
                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(viewModel.language.localized("Appearance"))
                                    .arcaFont(.footnote, weight: .semibold)
                                    .foregroundStyle(.secondary)
                                choicesLayout {
                                    appearancePill(.light, label: viewModel.language.localized("Light"), icon: "sun.max.fill")
                                    appearancePill(.dark, label: viewModel.language.localized("Dark"), icon: "moon.fill")
                                    appearancePill(.system, label: viewModel.language.localized("Auto"), icon: "circle.lefthalf.filled")
                                }
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text(viewModel.language.localized("Language & RTL Layout"))
                                    .arcaFont(.footnote, weight: .semibold)
                                    .foregroundStyle(.secondary)
                                choicesLayout {
                                    ForEach(AppLanguage.allCases) { lang in
                                        let selected = viewModel.language == lang
                                        Button {
                                            viewModel.language = lang
                                        } label: {
                                            Text(lang == .english ? "English" : (lang == .arabic ? "العربية" : "Türkçe"))
                                                .arcaFont(.footnote, weight: .semibold)
                                                .foregroundStyle(selected ? .white : .primary)
                                                .frame(maxWidth: .infinity, minHeight: 44)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                        .fill(selected ? appAccentColor : ArcaTheme.subtleFieldBackground(for: colorScheme))
                                                )
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityAddTraits(selected ? .isSelected : [])
                                    }
                                }
                            }
                        }
                    }

                    // 7. Privacy, Encryption & Biometrics
                    ArcaSectionCard(title: ArcaStrings.text("settings.privacyAndSecurity", language: viewModel.language), icon: "lock.shield.fill", iconTint: ArcaTheme.plumSensitive) {
                        VStack(spacing: 12) {
                            Toggle(viewModel.language.localized("App Lock (Device Authentication)"), isOn: Binding(
                                get: { viewModel.biometricLockEnabled },
                                set: { value in Task { await viewModel.setAppLockEnabled(value) } }
                            ))
                            .disabled(viewModel.appLock.isAuthenticating)
                            .arcaFont(.subheadline, weight: .semibold)
                            if let error = viewModel.appLock.errorMessage {
                                Text(error).arcaFont(.footnote).foregroundStyle(ArcaTheme.dangerRed)
                            }

                            Divider().opacity(0.45)

                            Link(viewModel.language.localized("Privacy policy"), destination: URL(string: "https://arca-api.on-forge.com/privacy.html")!)
                            Link(viewModel.language.localized("Contact support"), destination: URL(string: "mailto:hi@kawkbi.com")!)
                            NavigationLink {
                                PrivacyAndEncryptionDetailsView(viewModel: viewModel)
                            } label: {
                                settingsRow(
                                    icon: "key.fill",
                                    tint: ArcaTheme.plumSensitive,
                                    title: viewModel.language.localized("End-to-End Encryption & Recovery Key"),
                                    subtitle: viewModel.language.localized("Recovery phrase and sync privacy")
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    #if DEBUG
                    // Verification & Edge-State Simulator
                    ArcaSectionCard(
                        title: "Interactive State Simulator",
                        subtitle: "Test offline queuing, sync conflicts, storage quotas, and onboarding flows.",
                        icon: "slider.horizontal.2.square"
                    ) {
                        HStack {
                            Text("Banner State")
                                .arcaFont(.footnote, weight: .semibold)
                            Spacer()
                            Picker("Simulate Operational State", selection: $viewModel.bannerState) {
                                Text("Normal Online").tag(OperationalBannerState.normal)
                                Text("Offline (2 Queued)").tag(OperationalBannerState.offlineQueued(pendingCount: 2))
                                Text("Sync Edit Conflict").tag(OperationalBannerState.syncConflictsDetected(count: 1))
                                Text("Failed Upload").tag(OperationalBannerState.failedUpload(message: "Network timeout while uploading invoice.pdf."))
                                Text("Storage Quota Full").tag(OperationalBannerState.storageQuotaFull)
                                Text("3rd Device Limit").tag(OperationalBannerState.thirdDeviceLimitBlocked)
                                Text("Camera Denied").tag(OperationalBannerState.permissionDenied(resource: "Camera"))
                                Text("Corrupt Backup Rejected").tag(OperationalBannerState.restoreValidationFailed(reason: "SHA-256 digest mismatch on records.json."))
                            }
                            .labelsHidden()
                        }

                        Button {
                            withAnimation {
                                viewModel.hasCompletedOnboarding = false
                            }
                        } label: {
                            Label("Replay 4-Step Welcome Onboarding", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(ArcaSecondaryButtonStyle(isFullWidth: true))
                    }
                    #endif
                }
                .padding(18)
            }
            .background(ArcaTheme.canvasBackground(for: colorScheme))
            .arcaApplyAppAccentEnvironment()
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .sheet(isPresented: $showingSpaceManager) {
                ManageSpacesSheetView(viewModel: viewModel)
                    .arcaDesktopSheetSize()
            }
        }
    }

    // MARK: - App Theme Color Card (6-Color Picker from Reference)

    private var appThemeColorCard: some View {
        let activeOption = appAccentOption
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.language.localized("App Theme Color"))
                    .arcaFont(.subheadline, weight: .bold)
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
                Text(viewModel.language.localized("Used on Home and Settings. Each Collection uses its own color."))
                    .arcaFont(.caption)
                    .foregroundStyle(ArcaTheme.mutedText(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.84)) {
                    appColorDropdownOpen.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(activeOption.color)
                            .frame(width: 26, height: 26)
                        Circle()
                            .strokeBorder(Color.white.opacity(0.32), lineWidth: 1)
                            .frame(width: 26, height: 26)
                        Circle()
                            .fill(Color.white.opacity(0.65))
                            .frame(width: 8, height: 8)
                    }
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(activeOption.localizedName(in: viewModel.language))
                            .arcaFont(.subheadline, weight: .bold)
                            .foregroundStyle(.primary)
                        Text(activeOption.localizedTag(in: viewModel.language))
                            .arcaFont(.caption)
                            .foregroundStyle(ArcaTheme.mutedText(for: colorScheme))
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    Spacer()

                    ZStack {
                        Circle()
                            .fill(ArcaTheme.cardBackground(for: colorScheme))
                            .frame(width: 28, height: 28)
                        Image(systemName: appColorDropdownOpen ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.primary)
                    }
                    .accessibilityHidden(true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(ArcaTheme.subtleFieldBackground(for: colorScheme))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.language.localized("App Theme Color"))
            .accessibilityValue(activeOption.localizedName(in: viewModel.language))
            .accessibilityIdentifier("settings.appThemeColor.picker")

            if appColorDropdownOpen {
                VStack(spacing: 0) {
                    ForEach(Array(AppAccentColorOption.allCases.enumerated()), id: \.element.id) { index, option in
                        let isSelected = (option == activeOption)
                        Button {
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                                storedAccentHex = option.rawValue
                                appColorDropdownOpen = false
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(option.color)
                                    .frame(width: 20, height: 20)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                                    )
                                    .accessibilityHidden(true)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(option.localizedName(in: viewModel.language))
                                        .arcaFont(.subheadline, weight: .bold)
                                        .foregroundStyle(.primary)
                                    Text(option.localizedTag(in: viewModel.language))
                                        .arcaFont(.caption)
                                        .foregroundStyle(ArcaTheme.mutedText(for: colorScheme))
                                }
                                .fixedSize(horizontal: false, vertical: true)

                                Spacer()

                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.footnote.weight(.black))
                                        .foregroundStyle(option.foregroundTint(for: colorScheme))
                                        .accessibilityHidden(true)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(minHeight: 44)
                            .background(isSelected ? ArcaTheme.subtleFieldBackground(for: colorScheme) : Color.clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option.localizedName(in: viewModel.language) + ", " + option.localizedTag(in: viewModel.language))
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .accessibilityIdentifier("settings.appThemeColor.\(option.rawValue)")

                        if index < AppAccentColorOption.allCases.count - 1 {
                            Divider().opacity(0.45)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(ArcaTheme.dropdownBackground(for: colorScheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(ArcaTheme.dropdownBorder(for: colorScheme), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.08), radius: 12, x: 0, y: 6)
            }
        }
        .padding(16)
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

    // MARK: - Spaces Selection Card (from Reference)

    private var spacesSelectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(viewModel.language.localized("Spaces"))
                            .arcaFont(.subheadline, weight: .bold)
                            .accessibilityAddTraits(.isHeader)
                        switchSpaceButton
                    }
                } else {
                    HStack {
                        Text(viewModel.language.localized("Spaces"))
                            .arcaFont(.subheadline, weight: .bold)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        switchSpaceButton
                    }
                }
            }

            VStack(spacing: 0) {
                ForEach(Array(viewModel.spaces.enumerated()), id: \.element.id) { index, space in
                    let isCurrent = (space.id == viewModel.currentSpace?.id)
                    let collectionCount = (viewModel.collectionsBySpace[space.id] ?? []).filter { !$0.isDeleted }.count

                    Button {
                        Task { await viewModel.selectSpace(space.id) }
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(ArcaTheme.subtleFieldBackground(for: colorScheme))
                                    .frame(width: 34, height: 34)
                                Image(systemName: space.iconName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(isCurrent ? appForegroundTint : .primary)
                            }
                            .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(space.name)
                                    .arcaFont(.subheadline, weight: .bold)
                                    .foregroundStyle(.primary)
                                Text(viewModel.language.format("count.collections", collectionCount))
                                    .arcaFont(.caption)
                                    .foregroundStyle(ArcaTheme.mutedText(for: colorScheme))

                                if isCurrent && dynamicTypeSize.isAccessibilitySize {
                                    currentSpaceLabel
                                }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .layoutPriority(1)

                            Spacer(minLength: 0)

                            if isCurrent && !dynamicTypeSize.isAccessibilitySize {
                                currentSpaceLabel
                            }
                        }
                        .padding(.vertical, 10)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(isCurrent ? .isSelected : [])

                    if index < viewModel.spaces.count - 1 {
                        Divider().opacity(0.45)
                    }
                }
            }
        }
        .padding(16)
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

    private var currentSpaceLabel: some View {
        Text(viewModel.language.localized("Current"))
            .arcaFont(.caption2, weight: .bold)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(appAccentColor))
            .accessibilityHidden(true)
    }

    private var switchSpaceButton: some View {
        Button {
            showingSpaceManager = true
        } label: {
            Text(viewModel.language.localized("Switch Space"))
                .arcaFont(.caption, weight: .bold)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(appAccentColor)
                )
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.switchSpace")
    }

    private func appearancePill(_ mode: AppAppearanceMode, label: String, icon: String) -> some View {
        let selected = viewModel.appearanceMode == mode
        return Button {
            viewModel.appearanceMode = mode
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                Text(label)
                    .arcaFont(.footnote, weight: .semibold)
            }
            .foregroundStyle(selected ? .white : .primary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? appAccentColor : ArcaTheme.subtleFieldBackground(for: colorScheme))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("settings.appearance.\(mode.rawValue)")
    }

    private func settingsRow(icon: String, tint: Color, title: String, subtitle: String, badge: String? = nil) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.14))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .arcaFont(.subheadline, weight: .bold)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .arcaFont(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let badge {
                Text(badge)
                    .arcaFont(.caption, weight: .bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(tint.opacity(0.12)))
                    .foregroundStyle(tint)
            }

            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

// MARK: - Reusable Subscreen Back Header

@available(macOS 14.0, iOS 17.0, *)
private struct ArcaSubscreenBackHeader: View {
    let title: String
    let subtitle: String
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppAppearancePreferencesStore.accentColorDefaultsKey)
    private var storedAccentHex: String = AppAccentColorOption.defaultOption.rawValue
    private var language: AppLanguage { AppLanguage(rawValue: locale.language.languageCode?.identifier ?? "en") ?? .english }
    @Environment(\.dismiss) private var dismiss

    private var appForegroundTint: Color {
        AppAccentColorOption.resolve(from: storedAccentHex).foregroundTint(for: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.backward")
                        .font(.footnote.weight(.bold))
                    Text(language.localized("Settings"))
                        .arcaFont(.subheadline, weight: .semibold)
                }
                .foregroundStyle(appForegroundTint)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(appForegroundTint.opacity(0.12)))
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .arcaFont(.title, weight: .bold)
                Text(subtitle)
                    .arcaFont(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Screen 14: Backup, Export, Import, and Staged Restore

@available(macOS 14.0, iOS 17.0, *)
public struct BackupExportRestoreScreenView: View {
    @Bindable var viewModel: ArcaAppViewModel
    @Environment(\.colorScheme) private var colorScheme

    @ViewState private var passphrase = ""
    @ViewState private var restorePassphrase = ""
    @ViewState private var statusMessage: String?
    @ViewState private var isError = false
    @ViewState private var isBusy = false
    @ViewState private var showExporter = false
    @ViewState private var showImporter = false
    @ViewState private var exportDocument: EncryptedArchiveDocument?
    @ViewState private var exportFilename = "Arca-backup.arcaarchive.enc"

    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                ArcaSubscreenBackHeader(title: viewModel.language.localized("Portable Backups & Restore"), subtitle: viewModel.language.localized("Encrypted backups saved to Files"))
                ArcaSectionCard(title: viewModel.language.localized("Export Space Archive"),
                                subtitle: viewModel.language.localized("Includes this Space's records, schemas and attachments. Keep your password safe; Arca cannot recover it."),
                                icon: "square.and.arrow.up.fill") {
                    ArcaStyledTextField(viewModel.language.localized("Backup Password (required)"), text: $passphrase, icon: "lock.fill", isSecure: true)
                    Button { Task { await prepareExport() } } label: {
                        Label(viewModel.language.localized("Save Encrypted Backup to Files"), systemImage: "shippingbox.fill")
                    }
                    .buttonStyle(ArcaPrimaryButtonStyle())
                    .disabled(isBusy || passphrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ArcaSectionCard(title: viewModel.language.localized("Restore from Files"),
                                subtitle: viewModel.language.localized("Verifies the backup before creating a new Local-Only Space. Existing Spaces stay intact."),
                                icon: "arrow.down.doc.fill") {
                    ArcaStyledTextField(viewModel.language.localized("Backup Password"), text: $restorePassphrase, icon: "lock.fill", isSecure: true)
                    Button { showImporter = true } label: {
                        Label(viewModel.language.localized("Choose Backup from Files"), systemImage: "folder.fill")
                    }
                    .buttonStyle(ArcaSecondaryButtonStyle())
                    .disabled(isBusy)
                }
                if isBusy { ProgressView("Preparing backup…") }
                if let statusMessage {
                    Text(statusMessage).arcaFont(.callout)
                        .foregroundStyle(isError ? ArcaTheme.dangerRed : ArcaTheme.secondaryEmerald)
                }
            }
            .padding(18)
        }
        .background(ArcaTheme.canvasBackground(for: colorScheme))
        .fileExporter(isPresented: $showExporter, document: exportDocument, contentType: .data,
                      defaultFilename: exportFilename) { result in
            exportDocument = nil
            switch result {
            case .success: report("Encrypted backup saved to Files.", error: false); passphrase = ""
            case .failure(let error): report(error.localizedDescription, error: true)
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data, .package, .folder]) { result in
            switch result {
            case .success(let url): Task { await restore(from: url) }
            case .failure(let error): report(error.localizedDescription, error: true)
            }
        }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }

    private func prepareExport() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let url = try await viewModel.exportCurrentSpaceArchive(passphrase: passphrase)
            defer { try? FileManager.default.removeItem(at: url) }
            exportDocument = EncryptedArchiveDocument(data: try Data(contentsOf: url))
            exportFilename = url.lastPathComponent
            showExporter = true
        } catch { report(error.localizedDescription, error: true) }
    }

    private func restore(from url: URL) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let space = try await viewModel.restoreSpaceArchive(from: url, passphrase: restorePassphrase)
            restorePassphrase = ""
            report("Restored “\(space.name)” as a new Local-Only Space.", error: false)
        } catch { report("Restore rejected: " + error.localizedDescription, error: true) }
    }

    private func report(_ message: String, error: Bool) { statusMessage = message; isError = error }
}

/// Only encrypted bytes are handed to the system document picker.
private struct EncryptedArchiveDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

// MARK: - Screen 15: Sync Status, Outbox, and Conflict Resolution

@available(macOS 14.0, iOS 17.0, *)
public struct SyncStatusAndConflictsScreenView: View {
    @Bindable var viewModel: ArcaAppViewModel
    @Environment(\.colorScheme) private var colorScheme

    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                ArcaSubscreenBackHeader(
                    title: viewModel.language.localized("Sync & Conflicts"),
                    subtitle: viewModel.language.localized("Idempotent outbox operations & non-destructive conflict preservation")
                )

                if (!viewModel.cloudAccountConnected || viewModel.needsCloudSignIn) && !viewModel.hasPendingAccountDeletionCleanup && !viewModel.isDeletingCloudAccount {
                    CloudAccountForm(viewModel: viewModel)
                }
                CloudAccountDeletionSection(viewModel: viewModel)
                ArcaSectionCard(title: viewModel.language.localized("Sync status"), icon: "arrow.triangle.2.circlepath.icloud.fill") {
                    Text(viewModel.language.localized(viewModel.syncStatus))
                        .arcaFont(.subheadline, weight: .medium)
                    HStack {
                        Text(viewModel.language.localized("Durable Local Outbox"))
                            .arcaFont(.subheadline, weight: .medium)
                        Spacer()
                        Text(viewModel.language.format("count.operations", viewModel.pendingOutboxCount))
                            .arcaFont(.footnote, weight: .semibold)
                            .foregroundStyle(.secondary)
                    }


                    Button {
                        Task { await viewModel.synchronizeCurrentSpaceNow() }
                    } label: {
                        Label(viewModel.language.localized("Sync my cloud Spaces"), systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(ArcaPrimaryButtonStyle())
                    .disabled(viewModel.isSyncing || !viewModel.cloudAccountConnected)
                }

                ArcaSectionCard(
                    title: viewModel.language.format("Preserved Edit Conflicts (%d)", viewModel.syncConflicts.count),
                    subtitle: viewModel.language.localized("Arca never trusts device wall-clock timestamps to overwrite concurrent edits."),
                    icon: "exclamationmark.arrow.triangle.2.circlepath",
                    iconTint: ArcaTheme.plumSensitive
                ) {
                    if viewModel.syncConflicts.isEmpty {
                        Text(viewModel.language.localized("No unresolved conflicts."))
                            .arcaFont(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.syncConflicts) { conflict in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(conflict.summary)
                                    .arcaFont(.subheadline, weight: .bold)
                                Text(viewModel.language.format("Local rev %d vs. Remote rev %d", conflict.localRecord.revision, conflict.remoteRecord.revision))
                                    .arcaFont(.caption)
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    Button(viewModel.language.localized("Keep Local")) {
                                        Task { await viewModel.resolveConflict(conflict.id, keepLocal: true) }
                                    }
                                    .buttonStyle(ArcaPrimaryButtonStyle())

                                    Button(viewModel.language.localized("Keep Remote")) {
                                        Task { await viewModel.resolveConflict(conflict.id, keepLocal: false) }
                                    }
                                    .buttonStyle(ArcaSecondaryButtonStyle(isFullWidth: true))
                                }
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(ArcaTheme.subtleFieldBackground(for: colorScheme)))
                        }
                    }

                }
            }
            .padding(18)
        }
        .background(ArcaTheme.canvasBackground(for: colorScheme))
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }
}

// MARK: - Screen 16: Active Device Management (2-Device Free Limit Enforcement)

@available(macOS 14.0, iOS 17.0, *)
public struct ActiveDeviceManagementScreenView: View {
    @Bindable var viewModel: ArcaAppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppAppearancePreferencesStore.accentColorDefaultsKey)
    private var storedAccentHex: String = AppAccentColorOption.defaultOption.rawValue

    private var appForegroundTint: Color {
        AppAccentColorOption.resolve(from: storedAccentHex).foregroundTint(for: colorScheme)
    }

    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                ArcaSubscreenBackHeader(
                    title: viewModel.language.format("Active Devices (%d/%d)", viewModel.enrolledDevices.count, viewModel.maxAllowedDevices),
                    subtitle: viewModel.language.localized("Free accounts support up to 2 synced devices. Revoking rotates Space Encryption Keys.")
                )

                ArcaSectionCard(title: viewModel.language.localized("Enrolled Sync Devices"), icon: "laptopcomputer.and.iphone") {
                    VStack(spacing: 10) {
                        ForEach(viewModel.enrolledDevices, id: \.deviceId) { dev in
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(appForegroundTint.opacity(0.14))
                                        .frame(width: 38, height: 38)
                                    Image(systemName: dev.isCurrentDevice ? "iphone.gen3.radiowaves.left.and.right" : "iphone")
                                        .foregroundStyle(appForegroundTint)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(dev.isCurrentDevice ? viewModel.language.format("%@ (This Device)", dev.deviceName) : dev.deviceName)
                                        .arcaFont(.subheadline, weight: .bold)
                                    Text(viewModel.language.format("Enrolled %@", dev.enrolledAt.formatted(.dateTime.day().month().year().locale(viewModel.language.locale))))
                                        .arcaFont(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if !dev.isCurrentDevice {
                                    ArcaPillActionButton(viewModel.language.localized("Revoke"), icon: "xmark.shield", tint: ArcaTheme.dangerRed) {
                                        Task { await viewModel.revokeDevice(deviceId: dev.deviceId) }
                                    }
                                }
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 12).fill(ArcaTheme.subtleFieldBackground(for: colorScheme)))
                        }
                    }
                }

                Text(viewModel.language.localized("To add a device, sign in there with your account password and recovery key."))
                    .foregroundStyle(.secondary)

            }
            .padding(18)
        }
        .background(ArcaTheme.canvasBackground(for: colorScheme))
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }
}

// MARK: - Screen 17: Storage-Mode Migration Preview

@available(macOS 14.0, iOS 17.0, *)
public struct StorageModeMigrationScreenView: View {
    @Bindable var viewModel: ArcaAppViewModel
    public let space: SpaceMetadata
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @ViewState private var targetMode: SpaceStorageMode = .localOnly
    @ViewState private var migrationError: String?
    @ViewState private var requestRemoteDeletion = false
    @ViewState private var acceptCloudUpload = false

    private var remoteCopyExplanation: String {
        if targetMode == .localOnly && space.storageMode != .localOnly {
            return "Future uploads stop. Existing remote copies remain unless you request and verify their deletion. Offline devices may retain earlier copies."
        }
        if targetMode == .arcaSync && space.storageMode != .arcaSync {
            return "Records are encrypted on this device before they are uploaded for sync."
        }
        return "Existing remote copies are unchanged until you apply a storage change or request deletion."
    }

    public var body: some View {
        let preview = viewModel.computeStorageMigrationPreview(for: space, to: targetMode, deleteRemoteVerified: requestRemoteDeletion)
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                ArcaSubscreenBackHeader(
                    title: viewModel.language.localized("Storage Mode Migration"),
                    subtitle: viewModel.language.format("Space: %@", space.name)
                )

                ArcaSectionCard(title: viewModel.language.localized("Choose Target Storage Mode"), icon: "externaldrive.fill") {
                    Picker(viewModel.language.localized("Target Storage Mode"), selection: $targetMode) {
                        Text(viewModel.language.localized("Arca Sync (Cloud DB — Default)")).tag(SpaceStorageMode.arcaSync)
                        Text(viewModel.language.localized("Local-Only (On This Device)")).tag(SpaceStorageMode.localOnly)
                    }
                    Text(viewModel.language.localized(targetMode == .arcaSync
                         ? "Arca Sync is the default cloud-synced E2EE mode across devices."
                         : targetMode == .localOnly
                         ? "Local-Only keeps all records and attachments strictly on this device."
                         : "Personal Cloud Backup sends direct encrypted archives to iCloud or Google Drive."))
                        .arcaFont(.caption)
                        .foregroundStyle(.secondary)
                }

                ArcaSectionCard(title: viewModel.language.localized("Migration Impact Preview"), icon: "info.circle.fill") {
                    HStack {
                        Text(viewModel.language.localized("Records to Upload"))
                            .arcaFont(.footnote)
                        Spacer()
                        Text("\(preview.recordsToUploadCount)")
                            .arcaFont(.subheadline, weight: .bold)
                    }
                    HStack {
                        Text(viewModel.language.localized("Attachments to Upload"))
                            .arcaFont(.footnote)
                        Spacer()
                        Text("\(preview.attachmentsToUploadCount)")
                            .arcaFont(.subheadline, weight: .bold)
                    }
                    Divider().opacity(0.45)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.language.localized("What Remains Local"))
                            .arcaFont(.footnote, weight: .bold)
                        Text(viewModel.language.localized("All records and attachments remain on this device. Reading, searching and editing continue to work locally."))
                            .arcaFont(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.language.localized("Existing Remote Copies"))
                            .arcaFont(.footnote, weight: .bold)
                        Text(viewModel.language.localized(remoteCopyExplanation))
                            .arcaFont(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if space.storageMode == .arcaSync && targetMode == .localOnly {
                    ArcaSectionCard(title: viewModel.language.localized("Remote Cloud Copy Handling"), icon: "trash.slash.fill", iconTint: ArcaTheme.warmAmber) {
                        Toggle(viewModel.language.localized("Request & Verify Deletion of Remote Encrypted Copies"), isOn: $requestRemoteDeletion)
                            .arcaFont(.footnote, weight: .semibold)
                    }
                }

                if targetMode == .arcaSync && space.storageMode != .arcaSync {
                    ArcaSectionCard(title: viewModel.language.localized("Cloud Upload Consent"), icon: "checkmark.shield.fill") {
                        Toggle(viewModel.language.localized("I consent to uploading end-to-end encrypted records for this Space"), isOn: $acceptCloudUpload)
                            .arcaFont(.footnote, weight: .semibold)
                    }
                }

                if let migrationError { Text(migrationError).foregroundStyle(ArcaTheme.dangerRed) }
                Button(viewModel.language.localized("Apply Storage Mode Change")) {
                    Task {
                        do {
                            try await viewModel.applyStorageModeChange(spaceId: space.id, to: targetMode,
                                                                       deleteRemoteCopies: requestRemoteDeletion)
                            dismiss()
                        } catch {
                            migrationError = error.localizedDescription
                        }
                    }
                }
                .buttonStyle(ArcaPrimaryButtonStyle())
                .disabled(targetMode == .arcaSync && space.storageMode != .arcaSync && !acceptCloudUpload)
            }
            .padding(18)
        }
        .background(ArcaTheme.canvasBackground(for: colorScheme))
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .onAppear {
            targetMode = space.storageMode
        }
    }
}

private struct SubscriptionScreenKey: EnvironmentKey {
    static let defaultValue = AnyView(SubscriptionUnavailableView())
}

public extension EnvironmentValues {
    var arcaSubscriptionScreen: AnyView {
        get { self[SubscriptionScreenKey.self] }
        set { self[SubscriptionScreenKey.self] = newValue }
    }
}

@available(macOS 14.0, iOS 17.0, *)
public struct PrivacyAndEncryptionDetailsView: View {
    @Bindable var viewModel: ArcaAppViewModel
    @Environment(\.colorScheme) private var colorScheme

    @Environment(\.scenePhase) private var scenePhase
    @ViewState private var showingRecoveryPhrase = false

    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                ArcaSubscreenBackHeader(
                    title: viewModel.language.localized("Encryption & Privacy"),
                    subtitle: viewModel.language.localized("Client-side AES-256-GCM + Curve25519 key hierarchy")
                )

                ArcaSectionCard(
                    title: viewModel.language.localized("Emergency E2EE Recovery Key"),
                    subtitle: viewModel.language.localized("Account password recovery only restores sign-in access. Decrypting synced records when all old devices are lost requires this Recovery Key."),
                    icon: "key.fill",
                    iconTint: ArcaTheme.warmAmber
                ) {
                    Button(showingRecoveryPhrase ? viewModel.language.localized("Hide recovery phrase") : viewModel.language.localized("Show recovery phrase")) {
                        showingRecoveryPhrase.toggle()
                    }
                    if showingRecoveryPhrase {
                        Text(viewModel.recoveryKeyPhrase)
                            .font(.system(.body, design: .monospaced))
                            .privacySensitive()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                ArcaSectionCard(title: viewModel.language.localized("Private sync content"), icon: "eye.slash.fill", iconTint: ArcaTheme.secondaryEmerald) {
                    Text(viewModel.language.localized("Record values, collection schemas and field labels are encrypted on this device before syncing. Forge receives encrypted changes and wrapped recovery keys. File attachments imported into Local-Only Spaces stay on this device unless you export them."))
                        .arcaFont(.body)
                        .foregroundStyle(.secondary)
                }

                ArcaSectionCard(title: viewModel.language.localized("Metadata Visible to Sync Service"), icon: "server.rack") {
                    Text(viewModel.language.localized("• Account identifier and subscription entitlement tier\n• Enrolled device count and device labels\n• Encrypted blob byte sizes and opaque UUIDs\n• Request timestamps and sync cursors"))
                        .arcaFont(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
        }
        .background(ArcaTheme.canvasBackground(for: colorScheme))
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { showingRecoveryPhrase = false }
        }
        .onDisappear { showingRecoveryPhrase = false }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }
}

private struct SubscriptionUnavailableView: View {
    @Environment(\.locale) private var locale
    var body: some View {
        let language = AppLanguage(rawValue: locale.language.languageCode?.identifier ?? "en") ?? .english
        Text(language.localized("Purchases are available in the Arca iOS app."))
    }
}
