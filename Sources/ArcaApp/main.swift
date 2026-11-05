import SwiftUI
import ArcaUI
#if os(macOS)
import AppKit
#endif

@available(macOS 14.0, iOS 17.0, *)
public struct ArcaApplication: App {
    @ViewState private var viewModel = ArcaAppViewModel()

    public init() {
        #if os(macOS)
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
            if let window = NSApplication.shared.windows.first {
                window.title = "Arca — iOS Simulator Viewport"
                window.titlebarAppearsTransparent = true
            }
        }
        #endif
    }

    public var body: some Scene {
        WindowGroup {
            ArcaRootContainerView(viewModel: viewModel)
                .task { await viewModel.refreshSuggestedTemplates() }
                #if os(macOS)
                .frame(minWidth: 450, idealWidth: 480, maxWidth: .infinity, minHeight: 890, idealHeight: 920, maxHeight: .infinity)
                #endif
                .task {
                    await viewModel.bootstrapIfNeeded()
                }
        }
    }
}

if #available(macOS 14.0, iOS 17.0, *) {
    ArcaApplication.main()
}
