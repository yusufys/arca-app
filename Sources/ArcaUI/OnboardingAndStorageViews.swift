import SwiftUI
import ArcaCore

// MARK: - Screens 1, 2, 3, 4: Welcome, Storage Choice, Cloud Account Setup, Starter Templates

@available(macOS 14.0, iOS 17.0, *)
public struct OnboardingContainerView: View {
    @Bindable var viewModel: ArcaAppViewModel

    @ViewState private var currentStep: Int = 1
    @ViewState private var selectedMode: SpaceStorageMode = .arcaSync
    @ViewState private var acceptedCloudTerms: Bool = false
    @ViewState private var selectedTemplates: Set<StarterTemplateID> = [.vehicleMaintenance, .homeInventory, .warranties]
    @Environment(\.colorScheme) private var colorScheme

    public init(viewModel: ArcaAppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top Mobile Header Bar with Step Progress & Language Selector
            VStack(spacing: 12) {
                HStack {
                    HStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(ArcaTheme.accent)
                                .frame(width: 28, height: 28)
                            Image(systemName: "archivebox.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        Text(ArcaStrings.text("app.name", language: viewModel.language))
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                    }

                    Spacer()

                    Text("Step \(currentStep) of 4")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Menu {
                        ForEach(AppLanguage.allCases) { lang in
                            Button {
                                viewModel.language = lang
                            } label: {
                                Label(lang.displayName, systemImage: viewModel.language == lang ? "checkmark" : "globe")
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "globe")
                                .font(.system(size: 12, weight: .semibold))
                            Text(viewModel.language.rawValue.uppercased())
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(ArcaTheme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(ArcaTheme.accent.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }

                // Step Progress Bar
                HStack(spacing: 6) {
                    ForEach(1...4, id: \.self) { step in
                        Capsule()
                            .fill(step <= currentStep ? ArcaTheme.accent : Color.secondary.opacity(0.20))
                            .frame(height: 5)
                    }
                }
                .accessibilityLabel("Onboarding step \(currentStep) of 4")
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Group {
                switch currentStep {
                case 1:
                    welcomeStep
                case 2:
                    storageChoiceStep
                case 3:
                    cloudAccountSetupStep
                default:
                    starterTemplateStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(ArcaTheme.canvasBackground(for: colorScheme))
    }

    // MARK: Screen 1 — Welcome
    private var welcomeStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                // Hero Card
                VStack(alignment: .leading, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [ArcaTheme.accent, ArcaTheme.secondaryEmerald],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 64, height: 64)
                            .shadow(color: ArcaTheme.accent.opacity(0.30), radius: 12, x: 0, y: 6)

                        Image(systemName: "archivebox.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(ArcaStrings.text("app.tagline", language: viewModel.language))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text(ArcaStrings.text("app.heroPrompt", language: viewModel.language))
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 6)

                // Value Pillars Card
                ArcaSectionCard(title: "Why People Trust Arca", icon: "checkmark.seal.fill") {
                    VStack(alignment: .leading, spacing: 16) {
                        featureRow(
                            icon: "internaldrive.fill",
                            tint: ArcaTheme.accent,
                            title: "Local-First & Offline Ready",
                            subtitle: "Every Space lives on your phone first. Create, search, and edit records in a garage or on a flight with zero signal."
                        )
                        Divider().opacity(0.5)
                        featureRow(
                            icon: "slider.horizontal.3",
                            tint: ArcaTheme.secondaryEmerald,
                            title: "Friendly Forms, No Database Jargon",
                            subtitle: "Start with ready-made templates for vehicles, warranties, or home inventory. You can customize their fields."
                        )
                        Divider().opacity(0.5)
                        featureRow(
                            icon: "lock.shield.fill",
                            tint: ArcaTheme.plumSensitive,
                            title: "Per-Space Privacy Control",
                            subtitle: "Choose whether a Space syncs. In a synced Space, you can keep a sensitive field or collection on this device."
                        )
                    }
                }

                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) { currentStep = 2 }
                } label: {
                    HStack {
                        Text(ArcaStrings.text("welcome.getStarted", language: viewModel.language))
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(ArcaPrimaryButtonStyle())
            }
            .padding(20)
        }
    }

    // MARK: Screen 2 — Storage Choice & Privacy Explanation
    private var storageChoiceStep: some View {
        StorageModeComparisonStepView(
            selectedMode: $selectedMode,
            acceptedCloudTerms: $acceptedCloudTerms,
            language: viewModel.language,
            onBack: {
                withAnimation { currentStep = 1 }
            },
            onContinue: {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                    if selectedMode == .localOnly {
                        currentStep = 4
                    } else {
                        currentStep = 3
                    }
                }
            }
        )
    }

    // MARK: Screen 3 — Cloud Account Setup (Skippable through Local-Only Mode)
    private var cloudAccountSetupStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Set Up Arca Sync & Recovery Key")
                        .font(.system(size: 22, weight: .bold, design: .rounded))

                    Text("Your account password signs you in, while your Recovery Key decrypts your records if you ever lose all enrolled devices.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                CloudAccountForm(viewModel: viewModel) {
                    if viewModel.spaces.isEmpty {
                        withAnimation { currentStep = 4 }
                    } else {
                        viewModel.hasCompletedOnboarding = true
                    }
                }

                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Button("Back") {
                            withAnimation { currentStep = 2 }
                        }
                        .buttonStyle(ArcaSecondaryButtonStyle(tint: .secondary))

                        Button("Skip & Use Local-Only Instead") {
                            selectedMode = .localOnly
                            withAnimation { currentStep = 4 }
                        }
                        .buttonStyle(ArcaSecondaryButtonStyle(tint: ArcaTheme.accent, isFullWidth: true))
                    }
                }
            }
            .padding(20)
        }
    }

    // MARK: Screen 4 — Starter Template Selection
    private var starterTemplateStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Choose Starter Collections")
                        .font(.system(size: 22, weight: .bold, design: .rounded))

                    Text("These demo collections contain fictional records so you can try Arca.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                ForEach(StarterTemplateCatalog.visibleDemos) { template in
                    let isSelected = selectedTemplates.contains(template.id)
                    let tintColor = ArcaTheme.color(fromHex: template.colorHex)

                    Button {
                        if selectedTemplates.contains(template.id) {
                            selectedTemplates.remove(template.id)
                        } else {
                            selectedTemplates.insert(template.id)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .center, spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(tintColor)
                                        .frame(width: 42, height: 42)
                                    Image(systemName: template.iconName)
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(.white)
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(template.name)
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                        .foregroundStyle(.primary)
                                    Text(template.subtitle)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                }

                                Spacer()

                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(isSelected ? tintColor : Color.secondary.opacity(0.4))
                            }

                            if let disclosure = template.sensitivityDisclosure {
                                Text(disclosure)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(ArcaTheme.plumSensitive.opacity(0.08))
                                    )
                            }
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(ArcaTheme.cardBackground(for: colorScheme))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(isSelected ? tintColor.opacity(0.65) : ArcaTheme.cardBorder(for: colorScheme), lineWidth: isSelected ? 1.5 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 10) {
                    Button("Back") {
                        withAnimation { currentStep = 2 }
                    }
                    .buttonStyle(ArcaSecondaryButtonStyle(tint: .secondary))

                    Button {
                        Task {
                            await viewModel.finishOnboarding(
                                defaultMode: selectedMode == .personalCloudBackup ? .localOnly : selectedMode,
                                acceptedCloudTerms: acceptedCloudTerms,
                                selectedTemplates: Array(selectedTemplates)
                            )
                        }
                    } label: {
                        Label("Open My Spaces", systemImage: "sparkles")
                    }
                    .buttonStyle(ArcaPrimaryButtonStyle())
                }
                .padding(.top, 4)
            }
            .padding(20)
        }
    }

    private func featureRow(icon: String, tint: Color, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.14))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Screen 2: Storage Mode Comparison Step View (Arca Sync Default vs Local-Only)

@available(macOS 14.0, iOS 17.0, *)
public struct StorageModeComparisonStepView: View {
    @Binding public var selectedMode: SpaceStorageMode
    @Binding public var acceptedCloudTerms: Bool
    public var language: AppLanguage
    public var onBack: (() -> Void)?
    public var onContinue: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme

    public init(
        selectedMode: Binding<SpaceStorageMode>,
        acceptedCloudTerms: Binding<Bool>,
        language: AppLanguage = .english,
        onBack: (() -> Void)? = nil,
        onContinue: (() -> Void)? = nil
    ) {
        self._selectedMode = selectedMode
        self._acceptedCloudTerms = acceptedCloudTerms
        self.language = language
        self.onBack = onBack
        self.onContinue = onContinue
    }

    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(ArcaStrings.text("storage.title", language: language))
                        .font(.system(size: 22, weight: .bold, design: .rounded))

                    Text("Arca Sync is the default cloud-synced E2EE mode for new Spaces. Local-Only is always available whenever you want records never to leave this phone.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                storageModeOptionCard(
                    mode: .arcaSync,
                    badge: "Recommended",
                    icon: "arrow.triangle.2.circlepath.icloud.fill",
                    tint: ArcaTheme.accent,
                    title: "Arca Sync",
                    bullets: [
                        "Save records on your device and sync changes after connecting your Arca account.",
                        "Your device encrypts record changes before upload. Forge stores encrypted changes and wrapped keys for recovery.",
                        "Free accounts support up to 2 active devices; Pro expands to 10 devices."
                    ]
                )

                storageModeOptionCard(
                    mode: .localOnly,
                    badge: "On This Device",
                    icon: "iphone",
                    tint: ArcaTheme.secondaryEmerald,
                    title: "Local-Only (On This Device)",
                    bullets: [
                        "Your records stay on this device unless you choose to export them.",
                        "You can use a Local-Only Space without an account.",
                        "Search, insights and manual backups work offline."
                    ]
                )

                if selectedMode == .arcaSync {
                    Button {
                        acceptedCloudTerms.toggle()
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: acceptedCloudTerms ? "checkmark.square.fill" : "square")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(acceptedCloudTerms ? ArcaTheme.accent : .secondary)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("I understand and accept encrypted cloud storage for synced Spaces")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.primary)
                                Text("The sync service handles your account details, enrolled devices and their public keys, record identifiers, encrypted sizes and sync activity.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(ArcaTheme.accent.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(ArcaTheme.accent.opacity(0.28), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(acceptedCloudTerms ? .isSelected : [])
                }

                if onBack != nil || onContinue != nil {
                    HStack(spacing: 10) {
                        if let back = onBack {
                            Button("Back") {
                                back()
                            }
                            .buttonStyle(ArcaSecondaryButtonStyle(tint: .secondary))
                        }

                        if let cont = onContinue {
                            Button("Continue") {
                                cont()
                            }
                            .buttonStyle(ArcaPrimaryButtonStyle())
                            .disabled(selectedMode == .arcaSync && !acceptedCloudTerms)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(20)
        }
    }

    private func storageModeOptionCard(
        mode: SpaceStorageMode,
        badge: String,
        icon: String,
        tint: Color,
        title: String,
        bullets: [String]
    ) -> some View {
        let isSelected = selectedMode == mode
        return Button {
            withAnimation(.easeOut(duration: 0.16)) {
                selectedMode = mode
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(tint.opacity(0.14))
                            .frame(width: 34, height: 34)
                        Image(systemName: icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(tint)
                    }

                    Text(title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Spacer()

                    Text(badge)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(tint.opacity(0.14)))
                        .foregroundStyle(tint)
                }

                ForEach(bullets, id: \.self) { bullet in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(tint.opacity(0.6))
                            .frame(width: 5, height: 5)
                            .padding(.top, 5)
                        Text(bullet)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
            .padding(15)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(ArcaTheme.cardBackground(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? tint : ArcaTheme.cardBorder(for: colorScheme), lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: isSelected ? tint.opacity(0.12) : .clear, radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

@available(macOS 14.0, iOS 17.0, *)
struct CloudAccountForm: View {
    @Bindable var viewModel: ArcaAppViewModel
    var didConnect: () -> Void = {}
    @ViewState private var createAccount = false
    @ViewState private var email = ""
    @ViewState private var password = ""
    @ViewState private var recoveryPhrase = ""
    @ViewState private var errorMessage: String?
    @ViewState private var working = false

    var body: some View {
        ArcaSectionCard(title: "Arca Sync account", icon: "icloud") {
            Picker("Account", selection: $createAccount) {
                Text("Sign in").tag(false)
                Text("Create account").tag(true)
            }
            .pickerStyle(.segmented)
            ArcaStyledTextField("Email", text: $email, icon: "envelope")
            ArcaStyledTextField("Account password", text: $password, icon: "lock", isSecure: true)
            if createAccount {
                Text("Save this recovery key before continuing. You will need it on your next device.")
                Text(viewModel.recoveryKeyPhrase).font(.system(.body, design: .monospaced)).textSelection(.enabled)
            } else {
                ArcaStyledTextField("Recovery key from your first device", text: $recoveryPhrase, icon: "key", isSecure: true)
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(ArcaTheme.dangerRed) }
            Button(working ? "Connecting…" : (createAccount ? "Create account" : "Connect this device")) {
                Task {
                    working = true
                    defer { working = false }
                    do {
                        try await viewModel.connectCloudAccount(email: email, password: password,
                            createAccount: createAccount, recoveryPhrase: recoveryPhrase)
                        password = ""
                        recoveryPhrase = ""
                        errorMessage = nil
                        didConnect()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            .buttonStyle(ArcaPrimaryButtonStyle())
            .disabled(working || password.isEmpty || email.isEmpty || (!createAccount && recoveryPhrase.isEmpty))
        }
    }
}
