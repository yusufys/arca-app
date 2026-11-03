import SwiftUI
import ArcaCore

/// Root container view for Arca, handling:
/// - Biometric app lock screen when enabled.
/// - 4-step Onboarding flow (`Welcome`, `Storage Choice`, `Cloud Account & Recovery Key`, `Starter Templates`).
/// - Custom iOS bottom tab bar (`Home`, `Insights`, `Settings`) so macOS and iOS share the exact same mobile navigation layout.
/// - On macOS, an interactive iPhone 16 Pro device bezel preview mode (toggleable to full window).
@available(macOS 14.0, iOS 17.0, *)
public struct ArcaRootContainerView: View {
    @Bindable var viewModel: ArcaAppViewModel

    @ViewState private var selectedTab: Int = 0
    @ViewState private var useiPhoneBezelOnMac: Bool = true
    @Environment(\.colorScheme) private var systemColorScheme

    public init(viewModel: ArcaAppViewModel) {
        self.viewModel = viewModel
    }

    private var effectiveColorScheme: ColorScheme {
        viewModel.appearanceMode.colorScheme ?? systemColorScheme
    }

    public var body: some View {
        #if os(macOS)
        macStudioContainer
            .preferredColorScheme(viewModel.appearanceMode.colorScheme)
            .environment(\.layoutDirection, viewModel.language.layoutDirection)
            .environment(\.locale, viewModel.language.locale)
        #else
        mobileScreenContent
            .preferredColorScheme(viewModel.appearanceMode.colorScheme)
            .environment(\.layoutDirection, viewModel.language.layoutDirection)
            .environment(\.locale, viewModel.language.locale)
        #endif
    }

    // MARK: - Core Mobile Content (Shared 100% Between iPhone & Mac Preview)

    private var mobileScreenContent: some View {
        ZStack {
            ArcaTheme.canvasBackground(for: effectiveColorScheme)
                .ignoresSafeArea()

            if let error = viewModel.storageStartupError {
                VStack(spacing: 12) {
                    Text("Your workspace could not be opened").font(.headline)
                    Text(error)
                    Text("Unlock the device and reopen Arca to try again.")
                }.padding()
            } else if viewModel.biometricLockEnabled && viewModel.isAppLocked {
                biometricLockScreen
            } else if !viewModel.hasCompletedOnboarding {
                OnboardingContainerView(viewModel: viewModel)
            } else {
                VStack(spacing: 0) {
                    ZStack {
                        switch selectedTab {
                        case 0:
                            HomeScreenView(viewModel: viewModel)
                        case 1:
                            InsightsScreenView(viewModel: viewModel)
                        default:
                            SettingsHubScreenView(viewModel: viewModel)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    customiOSTabBar
                }
            }
        }
    }

    // MARK: - Custom iOS Bottom Tab Bar

    private var customiOSTabBar: some View {
        HStack(spacing: 0) {
            tabBarButton(
                index: 0,
                title: ArcaStrings.text("tab.home", language: viewModel.language),
                icon: selectedTab == 0 ? "rectangle.grid.2x2.fill" : "rectangle.grid.2x2",
                badgeCount: 0
            )
            tabBarButton(
                index: 1,
                title: ArcaStrings.text("tab.insights", language: viewModel.language),
                icon: "chart.bar.xaxis",
                badgeCount: 0
            )
            tabBarButton(
                index: 2,
                title: ArcaStrings.text("tab.settings", language: viewModel.language),
                icon: selectedTab == 2 ? "gearshape.fill" : "gearshape",
                badgeCount: viewModel.syncConflicts.count
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(
            ArcaTheme.cardBackground(for: effectiveColorScheme)
                .opacity(0.96)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(ArcaTheme.cardBorder(for: effectiveColorScheme))
                .frame(height: 1)
        }
    }

    private func tabBarButton(index: Int, title: String, icon: String, badgeCount: Int) -> some View {
        let isSelected = selectedTab == index
        return Button {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                selectedTab = index
            }
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: isSelected ? .bold : .medium))
                        .foregroundStyle(isSelected ? ArcaTheme.accent : .secondary)
                        .frame(width: 48, height: 28)
                        .background(
                            Capsule()
                                .fill(isSelected ? ArcaTheme.accent.opacity(0.14) : .clear)
                        )

                    if badgeCount > 0 {
                        Text("\(badgeCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(ArcaTheme.plumSensitive))
                            .offset(x: 6, y: -3)
                    }
                }

                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium, design: .rounded))
                    .foregroundStyle(isSelected ? ArcaTheme.accent : .secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - macOS Studio iPhone 16 Pro Viewport Wrapper

    #if os(macOS)
    private var macStudioContainer: some View {
        ZStack {
            // Studio ambient background
            LinearGradient(
                colors: [
                    Color(red: 0.11, green: 0.12, blue: 0.15),
                    Color(red: 0.07, green: 0.08, blue: 0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 12) {
                // Studio Toolbar
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "iphone.gen3")
                            .foregroundStyle(.white.opacity(0.85))
                        Text("Arca iOS Simulator Viewport")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))
                    }

                    Spacer()

                    // Quick Space pill switcher in studio bar
                    if viewModel.hasCompletedOnboarding, let space = viewModel.currentSpace {
                        Text("\(space.name) • \(space.storageMode == .arcaSync ? "Arca Sync" : "Local Only")")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                    }

                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            useiPhoneBezelOnMac.toggle()
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: useiPhoneBezelOnMac ? "arrow.up.left.and.arrow.down.right" : "iphone")
                                .font(.system(size: 11, weight: .semibold))
                            Text(useiPhoneBezelOnMac ? "Expand Window" : "iPhone Frame")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)

                if useiPhoneBezelOnMac {
                    // Realistic iPhone 16 Pro Frame
                    VStack(spacing: 0) {
                        // iOS Status Bar + Dynamic Island
                        iOSStatusBar

                        // Phone Screen Content
                        mobileScreenContent
                            .clipShape(RoundedRectangle(cornerRadius: 0))

                        // iOS Home Indicator Bar
                        VStack(spacing: 0) {
                            Capsule()
                                .fill(effectiveColorScheme == .dark ? Color.white.opacity(0.35) : Color.black.opacity(0.28))
                                .frame(width: 134, height: 5)
                                .padding(.top, 6)
                                .padding(.bottom, 8)
                        }
                        .frame(maxWidth: .infinity)
                        .background(ArcaTheme.cardBackground(for: effectiveColorScheme))
                    }
                    .frame(width: 402, height: 836)
                    .clipShape(RoundedRectangle(cornerRadius: 48, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 48, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.38),
                                        Color.white.opacity(0.12),
                                        Color.white.opacity(0.25)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 6
                            )
                    )
                    .shadow(color: Color.black.opacity(0.55), radius: 32, x: 0, y: 16)
                    .padding(.bottom, 14)
                } else {
                    mobileScreenContent
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                }
            }
        }
    }

    private var iOSStatusBar: some View {
        HStack {
            Text("9:41")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                .frame(width: 68, alignment: .leading)

            Spacer()

            // Dynamic Island pill
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(red: 0.12, green: 0.14, blue: 0.22))
                    .frame(width: 10, height: 10)
            }
            .frame(width: 112, height: 28)
            .background(Capsule().fill(Color.black))

            Spacer()

            HStack(spacing: 5) {
                Image(systemName: viewModel.isOfflineSimulated ? "wifi.slash" : "wifi")
                    .font(.system(size: 12, weight: .semibold))
                Image(systemName: "battery.100percent")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
            .frame(width: 68, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(ArcaTheme.canvasBackground(for: effectiveColorScheme))
    }
    #endif

    // MARK: - Biometric App Lock Screen

    private var biometricLockScreen: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(ArcaTheme.accent.opacity(0.12))
                    .frame(width: 96, height: 96)
                Image(systemName: "faceid")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(ArcaTheme.accent)
            }

            VStack(spacing: 8) {
                Text("Arca is Locked")
                    .font(.system(size: 26, weight: .bold, design: .rounded))

                Text("Your personal spaces and attachments are encrypted and protected on this device.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Button {
                viewModel.unlockAppWithBiometrics()
            } label: {
                Label("Unlock with Face ID", systemImage: "lock.open.fill")
            }
            .buttonStyle(ArcaPrimaryButtonStyle(tint: ArcaTheme.accent, isFullWidth: true))
            .padding(.horizontal, 36)

            Spacer()
        }
        .padding(24)
    }
}
