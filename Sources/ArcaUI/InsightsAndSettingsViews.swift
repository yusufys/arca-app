import SwiftUI
import Charts
import ArcaCore

// MARK: - Screen 13: Basic Useful Insights (Swift Charts)

@available(macOS 14.0, iOS 17.0, *)
public struct InsightsScreenView: View {
    @Bindable var viewModel: ArcaAppViewModel
    @Environment(\.colorScheme) private var colorScheme

    public init(viewModel: ArcaAppViewModel) {
        self.viewModel = viewModel
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
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(0.6)
                            .foregroundStyle(ArcaTheme.accent)
                        Text(ArcaStrings.text("insights.title", language: viewModel.language))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                    }

                    // Summary KPIs
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        kpiCard(title: "Records", value: "\(report.totalRecords)", icon: "doc.text.fill", tint: ArcaTheme.accent)
                        kpiCard(title: "Pinned", value: "\(report.favoriteRecords)", icon: "pin.fill", tint: ArcaTheme.warmAmber)
                        kpiCard(title: "Files", value: "\(report.totalAttachments)", icon: "paperclip", tint: ArcaTheme.secondaryEmerald)
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
                                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                            Text("Expires \(item.expirationDate.formatted(locale: viewModel.language.locale))")
                                                .font(.system(size: 12))
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text(item.isExpired ? "Expired" : "In \(item.daysRemaining)d")
                                            .font(.system(size: 11, weight: .bold, design: .rounded))
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
                            iconTint: ArcaTheme.accent
                        ) {
                            Chart(report.spendingOverTime) { point in
                                BarMark(
                                    x: .value("Month", point.yearMonth),
                                    y: .value("Amount", point.totalAmount)
                                )
                                .foregroundStyle(ArcaTheme.accent.gradient)
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
                            iconTint: ArcaTheme.accent
                        ) {
                            VStack(spacing: 10) {
                                ForEach(report.numericSummaries) { summary in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(summary.fieldLabel)
                                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                            Text("\(summary.collectionName) • \(summary.count) record\(summary.count == 1 ? "" : "s")")
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(summary.formattedSum)
                                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                                .foregroundStyle(ArcaTheme.accent)
                                            Text("Avg \(summary.formattedAverage)")
                                                .font(.system(size: 11))
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
                                    x: .value("Count", dist.count),
                                    y: .value("Category", dist.optionLabel)
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
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
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
    @Bindable var viewModel: ArcaAppViewModel
    @Environment(\.colorScheme) private var colorScheme

    public init(viewModel: ArcaAppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    // Header
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ARCA PREFERENCES & STORAGE")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(0.6)
                            .foregroundStyle(ArcaTheme.accent)
                        Text(ArcaStrings.text("settings.title", language: viewModel.language))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                    }

                    // Current Space Storage & Backups
                    if let current = viewModel.currentSpace {
                        ArcaSectionCard(title: "Current Space: \(current.name)", icon: current.iconName) {
                            VStack(spacing: 10) {
                                NavigationLink {
                                    StorageModeMigrationScreenView(viewModel: viewModel, space: current)
                                } label: {
                                    settingsRow(
                                        icon: "externaldrive.badge.checkmark",
                                        tint: ArcaTheme.accent,
                                        title: "Storage Mode & Migration Preview",
                                        subtitle: current.storageMode == .arcaSync ? "Arca Sync (E2EE)" : "On This Device Only"
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
                                        subtitle: "Verified .arcaarchive export & staged restore"
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Sync, Devices & Conflicts
                    ArcaSectionCard(title: ArcaStrings.text("settings.storageAndSync", language: viewModel.language), icon: "icloud.fill") {
                        VStack(spacing: 10) {
                            NavigationLink {
                                SyncStatusAndConflictsScreenView(viewModel: viewModel)
                            } label: {
                                settingsRow(
                                    icon: "arrow.triangle.2.circlepath.icloud.fill",
                                    tint: ArcaTheme.accent,
                                    title: "Sync Status, Outbox & Conflicts",
                                    subtitle: viewModel.isOfflineSimulated ? "Offline (Queuing locally)" : "Connected • \(viewModel.pendingOutboxCount) queued",
                                    badge: viewModel.syncConflicts.isEmpty ? nil : "\(viewModel.syncConflicts.count) conflict"
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
                                    title: "Active Synced Devices",
                                    subtitle: "Enrolled devices & key rotation",
                                    badge: "\(viewModel.enrolledDevices.count)/\(viewModel.maxAllowedDevices)"
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Subscription & Billing
                    ArcaSectionCard(title: ArcaStrings.text("settings.subscription", language: viewModel.language), icon: "sparkles") {
                        NavigationLink {
                            SubscriptionAndBillingScreenView(viewModel: viewModel)
                        } label: {
                            settingsRow(
                                icon: "crown.fill",
                                tint: ArcaTheme.warmAmber,
                                title: "Arca Plan & Quotas",
                                subtitle: "Non-destructive expiry guarantee",
                                badge: viewModel.isProSubscriber ? "Arca Pro" : "Free Plan"
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    // Appearance & Language
                    ArcaSectionCard(title: ArcaStrings.text("settings.appearanceAndLanguage", language: viewModel.language), icon: "paintbrush.fill") {
                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Appearance")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    appearancePill(.light, label: "Light", icon: "sun.max.fill")
                                    appearancePill(.dark, label: "Dark", icon: "moon.fill")
                                    appearancePill(.system, label: "Auto", icon: "circle.lefthalf.filled")
                                }
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Language & RTL Layout")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    ForEach(AppLanguage.allCases) { lang in
                                        let selected = viewModel.language == lang
                                        Button {
                                            viewModel.language = lang
                                        } label: {
                                            Text(lang == .english ? "English" : (lang == .arabic ? "العربية" : "Türkçe"))
                                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                                .foregroundStyle(selected ? .white : .primary)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 9)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                        .fill(selected ? ArcaTheme.accent : ArcaTheme.subtleFieldBackground(for: colorScheme))
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    // Privacy, Encryption & Biometrics
                    ArcaSectionCard(title: ArcaStrings.text("settings.privacyAndSecurity", language: viewModel.language), icon: "lock.shield.fill", iconTint: ArcaTheme.plumSensitive) {
                        VStack(spacing: 12) {
                            Toggle("Biometric App Lock (Face ID)", isOn: $viewModel.biometricLockEnabled)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))

                            Divider().opacity(0.45)

                            NavigationLink {
                                PrivacyAndEncryptionDetailsView(viewModel: viewModel)
                            } label: {
                                settingsRow(
                                    icon: "key.fill",
                                    tint: ArcaTheme.plumSensitive,
                                    title: "End-to-End Encryption & Recovery Key",
                                    subtitle: "Zero-knowledge architecture & server metadata"
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Verification & Edge-State Simulator
                    ArcaSectionCard(
                        title: "Interactive State Simulator",
                        subtitle: "Test offline queuing, sync conflicts, storage quotas, and onboarding flows.",
                        icon: "slider.horizontal.2.square"
                    ) {
                        HStack {
                            Text("Banner State")
                                .font(.system(size: 13, weight: .semibold))
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
                }
                .padding(18)
            }
            .background(ArcaTheme.canvasBackground(for: colorScheme))
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
        }
    }

    private func appearancePill(_ mode: AppAppearanceMode, label: String, icon: String) -> some View {
        let selected = viewModel.appearanceMode == mode
        return Button {
            viewModel.appearanceMode = mode
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(selected ? .white : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? ArcaTheme.accent : ArcaTheme.subtleFieldBackground(for: colorScheme))
            )
        }
        .buttonStyle(.plain)
    }

    private func settingsRow(icon: String, tint: Color, title: String, subtitle: String, badge: String? = nil) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.14))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let badge {
                Text(badge)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(tint.opacity(0.12)))
                    .foregroundStyle(tint)
            }

            Image(systemName: "chevron.forward")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Reusable Subscreen Back Header

@available(macOS 14.0, iOS 17.0, *)
private struct ArcaSubscreenBackHeader: View {
    let title: String
    let subtitle: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 13, weight: .bold))
                    Text("Settings")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(ArcaTheme.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(ArcaTheme.accent.opacity(0.10)))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 12))
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

    @ViewState private var encryptArchive = true
    @ViewState private var passphrase = ""
    @ViewState private var statusMessage: String?
    @ViewState private var isError = false

    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                ArcaSubscreenBackHeader(
                    title: "Portable Backups & Restore",
                    subtitle: "Independent per-Space .arcaarchive packages with SHA-256 verification"
                )

                ArcaSectionCard(
                    title: "Export Space Archive",
                    subtitle: "Exports Space metadata, versioned schemas, records, attachments, and a SHA-256 manifest.",
                    icon: "square.and.arrow.up.fill"
                ) {
                    Toggle("Encrypt with Passphrase (AES-256-GCM)", isOn: $encryptArchive)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))

                    if encryptArchive {
                        ArcaStyledTextField("Backup Passphrase (optional)", text: $passphrase, icon: "lock.fill", isSecure: true)
                    }

                    Button {
                        Task {
                            do {
                                let url = try await viewModel.exportCurrentSpaceArchive(passphrase: encryptArchive && !passphrase.isEmpty ? passphrase : nil)
                                isError = false
                                statusMessage = "Verified backup exported: \(url.lastPathComponent)"
                            } catch {
                                isError = true
                                statusMessage = error.localizedDescription
                            }
                        }
                    } label: {
                        Label("Export Current Space Backup", systemImage: "shippingbox.fill")
                    }
                    .buttonStyle(ArcaPrimaryButtonStyle())
                }

                if let statusMessage {
                    ArcaSectionCard(
                        title: isError ? "Restore Rejected Safely" : "Backup Verified",
                        icon: isError ? "xmark.octagon.fill" : "checkmark.seal.fill",
                        iconTint: isError ? ArcaTheme.dangerRed : ArcaTheme.secondaryEmerald
                    ) {
                        Text(statusMessage)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(isError ? ArcaTheme.dangerRed : ArcaTheme.secondaryEmerald)
                    }
                }

                if !viewModel.exportedArchiveURLs.isEmpty {
                    ArcaSectionCard(
                        title: "Staged Restore into New Space",
                        subtitle: "Every archive is validated in a staging folder before touching live data.",
                        icon: "arrow.down.doc.fill",
                        iconTint: ArcaTheme.secondaryEmerald
                    ) {
                        VStack(spacing: 10) {
                            ForEach(viewModel.exportedArchiveURLs, id: \.self) { url in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(url.lastPathComponent)
                                            .font(.system(size: 13, weight: .bold, design: .rounded))
                                        Text("SHA-256 manifest verified")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    ArcaPillActionButton("Restore", icon: "arrow.uturn.backward", tint: ArcaTheme.secondaryEmerald) {
                                        Task {
                                            do {
                                                let restored = try await viewModel.restoreSpaceArchive(from: url, passphrase: passphrase.isEmpty ? nil : passphrase)
                                                isError = false
                                                statusMessage = "Restored space “\(restored.name)” cleanly without overwriting existing spaces."
                                            } catch {
                                                isError = true
                                                statusMessage = error.localizedDescription
                                            }
                                        }
                                    }
                                }
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 12).fill(ArcaTheme.subtleFieldBackground(for: colorScheme)))
                            }
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

// MARK: - Screen 15: Sync Status, Outbox, and Conflict Resolution

@available(macOS 14.0, iOS 17.0, *)
public struct SyncStatusAndConflictsScreenView: View {
    @Bindable var viewModel: ArcaAppViewModel
    @Environment(\.colorScheme) private var colorScheme

    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                ArcaSubscreenBackHeader(
                    title: "Sync & Conflicts",
                    subtitle: "Idempotent outbox operations & non-destructive conflict preservation"
                )

                ArcaSectionCard(title: "Sync Engine Status", icon: "arrow.triangle.2.circlepath.icloud.fill") {
                    HStack {
                        Text("Network Status")
                            .font(.system(size: 14, weight: .medium))
                        Spacer()
                        Text(viewModel.isOfflineSimulated ? "Offline (Queuing Locally)" : "Connected")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(viewModel.isOfflineSimulated ? ArcaTheme.warmAmber : ArcaTheme.secondaryEmerald)
                    }

                    HStack {
                        Text("Durable Local Outbox")
                            .font(.system(size: 14, weight: .medium))
                        Spacer()
                        Text("\(viewModel.pendingOutboxCount) operation\(viewModel.pendingOutboxCount == 1 ? "" : "s")")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    Toggle("Simulate Offline Network", isOn: $viewModel.isOfflineSimulated)
                        .font(.system(size: 14, weight: .medium))

                    Button {
                        Task { await viewModel.synchronizeCurrentSpaceNow() }
                    } label: {
                        Label("Synchronize Current Space Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(ArcaPrimaryButtonStyle())
                    .disabled(viewModel.isOfflineSimulated)
                }

                ArcaSectionCard(
                    title: "Preserved Edit Conflicts (\(viewModel.syncConflicts.count))",
                    subtitle: "Arca never trusts device wall-clock timestamps to overwrite concurrent edits.",
                    icon: "exclamationmark.arrow.triangle.2.circlepath",
                    iconTint: ArcaTheme.plumSensitive
                ) {
                    if viewModel.syncConflicts.isEmpty {
                        Text("No unresolved conflicts. You can simulate a concurrent edit collision below to test conflict resolution.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.syncConflicts) { conflict in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(conflict.summary)
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                Text("Local rev \(conflict.localRecord.revision) vs. Remote rev \(conflict.remoteRecord.revision)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    Button("Keep Local") {
                                        Task { await viewModel.resolveConflict(conflict.id, keepLocal: true) }
                                    }
                                    .buttonStyle(ArcaPrimaryButtonStyle())

                                    Button("Keep Remote") {
                                        Task { await viewModel.resolveConflict(conflict.id, keepLocal: false) }
                                    }
                                    .buttonStyle(ArcaSecondaryButtonStyle(isFullWidth: true))
                                }
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(ArcaTheme.subtleFieldBackground(for: colorScheme)))
                        }
                    }

                    Button {
                        viewModel.simulateConcurrentConflict()
                    } label: {
                        Label("Simulate Concurrent Edit Conflict", systemImage: "bolt.horizontal.circle")
                    }
                    .buttonStyle(ArcaSecondaryButtonStyle(tint: ArcaTheme.plumSensitive, isFullWidth: true))
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

    @ViewState private var newDeviceName = ""
    @ViewState private var enrollmentError: String?

    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                ArcaSubscreenBackHeader(
                    title: "Active Devices (\(viewModel.enrolledDevices.count)/\(viewModel.maxAllowedDevices))",
                    subtitle: "Free accounts support up to 2 synced devices. Revoking rotates Space Encryption Keys."
                )

                ArcaSectionCard(title: "Enrolled Sync Devices", icon: "laptopcomputer.and.iphone") {
                    VStack(spacing: 10) {
                        ForEach(viewModel.enrolledDevices, id: \.deviceId) { dev in
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(ArcaTheme.accent.opacity(0.14))
                                        .frame(width: 38, height: 38)
                                    Image(systemName: dev.isCurrentDevice ? "iphone.gen3.radiowaves.left.and.right" : "iphone")
                                        .foregroundStyle(ArcaTheme.accent)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(dev.deviceName + (dev.isCurrentDevice ? " (This Device)" : ""))
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                    Text("Enrolled \(dev.enrolledAt.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if !dev.isCurrentDevice {
                                    ArcaPillActionButton("Revoke", icon: "xmark.shield", tint: ArcaTheme.dangerRed) {
                                        Task { await viewModel.revokeDevice(deviceId: dev.deviceId) }
                                    }
                                }
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 12).fill(ArcaTheme.subtleFieldBackground(for: colorScheme)))
                        }
                    }
                }

                ArcaSectionCard(
                    title: "Test Device Limit & Revocation",
                    subtitle: "Try enrolling a 3rd device on the Free plan to verify 2-device limit enforcement.",
                    icon: "plus.circle.fill"
                ) {
                    ArcaStyledTextField("Device Name (e.g., iPad Air, Work iPhone)", text: $newDeviceName, icon: "iphone")

                    if let enrollmentError {
                        Text(enrollmentError)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ArcaTheme.dangerRed)
                    }

                    Button("Enroll Simulated Device") {
                        Task {
                            do {
                                try await viewModel.enrollSimulatedDevice(name: newDeviceName.isEmpty ? "Secondary iPhone" : newDeviceName)
                                newDeviceName = ""
                                enrollmentError = nil
                            } catch {
                                enrollmentError = error.localizedDescription
                            }
                        }
                    }
                    .buttonStyle(ArcaPrimaryButtonStyle())
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

// MARK: - Screen 17: Storage-Mode Migration Preview

@available(macOS 14.0, iOS 17.0, *)
public struct StorageModeMigrationScreenView: View {
    @Bindable var viewModel: ArcaAppViewModel
    public let space: SpaceMetadata
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @ViewState private var targetMode: SpaceStorageMode = .localOnly
    @ViewState private var requestRemoteDeletion = false
    @ViewState private var acceptCloudUpload = false

    public var body: some View {
        let preview = viewModel.computeStorageMigrationPreview(for: space, to: targetMode, deleteRemoteVerified: requestRemoteDeletion)
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                ArcaSubscreenBackHeader(
                    title: "Storage Mode Migration",
                    subtitle: "Space: \(space.name)"
                )

                ArcaSectionCard(title: "Choose Target Storage Mode", icon: "externaldrive.fill") {
                    Picker("Target Storage Mode", selection: $targetMode) {
                        Text("Arca Sync (Cloud DB — Default)").tag(SpaceStorageMode.arcaSync)
                        Text("Local-Only (On This Device)").tag(SpaceStorageMode.localOnly)
                        Text("Personal Cloud Backup (Pro)").tag(SpaceStorageMode.personalCloudBackup)
                    }
                    Text(targetMode == .arcaSync
                         ? "Arca Sync is the default cloud-synced E2EE mode across devices."
                         : targetMode == .localOnly
                         ? "Local-Only keeps all records and attachments strictly on this device."
                         : "Personal Cloud Backup sends direct encrypted archives to iCloud or Google Drive.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                ArcaSectionCard(title: "Migration Impact Preview", icon: "info.circle.fill") {
                    HStack {
                        Text("Records to Upload")
                            .font(.system(size: 13))
                        Spacer()
                        Text("\(preview.recordsToUploadCount)")
                            .font(.system(size: 14, weight: .bold))
                    }
                    HStack {
                        Text("Attachments to Upload")
                            .font(.system(size: 13))
                        Spacer()
                        Text("\(preview.attachmentsToUploadCount)")
                            .font(.system(size: 14, weight: .bold))
                    }
                    Divider().opacity(0.45)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("What Remains Local")
                            .font(.system(size: 12, weight: .bold))
                        Text(preview.whatRemainsLocalExplanation)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Existing Remote Copies")
                            .font(.system(size: 12, weight: .bold))
                        Text(preview.whatHappensToRemoteCopiesExplanation)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                if space.storageMode == .arcaSync && targetMode == .localOnly {
                    ArcaSectionCard(title: "Remote Cloud Copy Handling", icon: "trash.slash.fill", iconTint: ArcaTheme.warmAmber) {
                        Toggle("Request & Verify Deletion of Remote Encrypted Copies", isOn: $requestRemoteDeletion)
                            .font(.system(size: 13, weight: .semibold))
                    }
                }

                if targetMode == .arcaSync && space.storageMode != .arcaSync {
                    ArcaSectionCard(title: "Cloud Upload Consent", icon: "checkmark.shield.fill") {
                        Toggle("I consent to uploading end-to-end encrypted records for this Space", isOn: $acceptCloudUpload)
                            .font(.system(size: 13, weight: .semibold))
                    }
                }

                Button("Apply Storage Mode Change") {
                    Task {
                        await viewModel.applyStorageModeChange(
                            spaceId: space.id,
                            to: targetMode,
                            deleteRemoteCopies: requestRemoteDeletion
                        )
                        dismiss()
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

// MARK: - Screen 18: Subscription Screen & Purchase Restoration

@available(macOS 14.0, iOS 17.0, *)
public struct SubscriptionAndBillingScreenView: View {
    @Bindable var viewModel: ArcaAppViewModel
    @Environment(\.colorScheme) private var colorScheme

    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                ArcaSubscreenBackHeader(
                    title: "Arca Pro & Plan",
                    subtitle: "StoreKit 2 Subscriptions with Zero Local Lock-In"
                )

                ArcaSectionCard(
                    title: viewModel.isProSubscriber ? "Arca Pro Active" : "Arca Free Plan Active",
                    subtitle: "Local-only storage, manual backups, starter templates, and basic insights are always free.",
                    icon: "crown.fill",
                    iconTint: ArcaTheme.warmAmber
                ) {
                    VStack(spacing: 8) {
                        quotaRow("Local Spaces & Records", "Unlimited (Free & Pro)")
                        quotaRow("Synced Active Devices", viewModel.isProSubscriber ? "Up to 10 Devices (Pro)" : "Up to 2 Devices (Free)")
                        quotaRow("Encrypted Cloud Storage", viewModel.isProSubscriber ? "25 GB (Pro)" : "250 MB (Free)")
                        quotaRow("Personal Cloud Backup Adapters", viewModel.isProSubscriber ? "Included (Pro)" : "Pro Upgrade")
                    }
                }

                ArcaSectionCard(title: "Upgrade or Manage Plan", icon: "sparkles") {
                    if !viewModel.isProSubscriber {
                        VStack(spacing: 10) {
                            Button {
                                Task { await viewModel.purchaseProSubscription(annual: true) }
                            } label: {
                                HStack {
                                    Text("Arca Pro Annual • Best Value")
                                    Spacer()
                                    Text("$34.99 / yr")
                                }
                            }
                            .buttonStyle(ArcaPrimaryButtonStyle())

                            Button {
                                Task { await viewModel.purchaseProSubscription(annual: false) }
                            } label: {
                                HStack {
                                    Text("Arca Pro Monthly")
                                    Spacer()
                                    Text("$3.99 / mo")
                                }
                            }
                            .buttonStyle(ArcaSecondaryButtonStyle(isFullWidth: true))
                        }
                    } else {
                        Button("Simulate Subscription Expiry (Verify Zero Data Loss)") {
                            Task { await viewModel.simulateSubscriptionExpiry() }
                        }
                        .buttonStyle(ArcaSecondaryButtonStyle(tint: ArcaTheme.warmAmber, isFullWidth: true))
                    }

                    Button("Restore Purchases (StoreKit 2)") {
                        Task { await viewModel.restorePurchases() }
                    }
                    .buttonStyle(ArcaSecondaryButtonStyle(tint: .secondary, isFullWidth: true))
                }

                ArcaSectionCard(title: "What Happens If Paid Access Expires", icon: "heart.text.square.fill", iconTint: ArcaTheme.secondaryEmerald) {
                    Text("• Your local spaces, records, and attachments are NEVER deleted.\n• Full local reading, creating, editing, and manual portable exports remain available forever.\n• If your account exceeds the 2-device or 250 MB Free sync allowance, background cloud sync pauses gracefully while retaining encrypted remote copies for the 90-day retention window.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
        }
        .background(ArcaTheme.canvasBackground(for: colorScheme))
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }

    private func quotaRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
        }
    }
}

@available(macOS 14.0, iOS 17.0, *)
public struct PrivacyAndEncryptionDetailsView: View {
    @Bindable var viewModel: ArcaAppViewModel
    @Environment(\.colorScheme) private var colorScheme

    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                ArcaSubscreenBackHeader(
                    title: "Encryption & Privacy",
                    subtitle: "Client-side AES-256-GCM + Curve25519 key hierarchy"
                )

                ArcaSectionCard(
                    title: "Emergency E2EE Recovery Key",
                    subtitle: "Account password recovery only restores sign-in access. Decrypting synced records when all old devices are lost requires this Recovery Key.",
                    icon: "key.fill",
                    iconTint: ArcaTheme.warmAmber
                ) {
                    Text(viewModel.recoveryKeyPhrase)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(ArcaTheme.warmAmber.opacity(0.10)))
                }

                ArcaSectionCard(title: "What Arca Servers Never Receive", icon: "eye.slash.fill", iconTint: ArcaTheme.secondaryEmerald) {
                    Text("• Record field values or notes\n• Collection names or custom field labels\n• Attachment filenames or file contents\n• Usable Master Account Keys or Space Data Encryption Keys")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                ArcaSectionCard(title: "Metadata Visible to Sync Service", icon: "server.rack") {
                    Text("• Account identifier and subscription entitlement tier\n• Enrolled device count and device labels\n• Encrypted blob byte sizes and opaque UUIDs\n• Request timestamps and sync cursors")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
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
