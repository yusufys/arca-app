import SwiftUI
import ArcaUI

@main
struct ArcaiOSApp: App {
    @ViewState private var viewModel = ArcaAppViewModel()

    var body: some Scene {
        WindowGroup {
            ArcaRootContainerView(viewModel: viewModel)
                .task {
                    await viewModel.bootstrapIfNeeded()
                }
        }
    }
}
