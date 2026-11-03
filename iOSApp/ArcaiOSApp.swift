import SwiftUI
import ArcaUI

@main
struct ArcaiOSApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @ViewState private var viewModel = ArcaAppViewModel()

    var body: some Scene {
        WindowGroup {
            ArcaRootContainerView(viewModel: viewModel)
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    await viewModel.bootstrapIfNeeded()
                    while !Task.isCancelled {
                        if viewModel.cloudAccountConnected && !viewModel.isSyncing && !viewModel.needsCloudSignIn {
                            await viewModel.synchronizeCurrentSpaceNow()
                        }
                        do { try await Task.sleep(nanoseconds: 60_000_000_000) }
                        catch { return }
                    }
                }
        }
    }
}
