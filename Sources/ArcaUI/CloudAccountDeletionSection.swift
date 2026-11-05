import SwiftUI

@available(macOS 14.0, iOS 17.0, *)
struct CloudAccountDeletionSection: View {
    @Bindable var viewModel: ArcaAppViewModel
    @ViewState private var confirmDeletion = false
    @ViewState private var errorMessage: String?
    @ViewState private var resultMessage: String?

    var body: some View {
        if viewModel.cloudAccountConnected || viewModel.hasPendingAccountDeletionCleanup || resultMessage != nil {
            ArcaSectionCard(title: viewModel.language.localized("Cloud Account"), icon: "person.crop.circle.badge.xmark", iconTint: ArcaTheme.dangerRed) {
                Text(viewModel.language.localized("Delete your cloud account, encrypted remote records, recovery material and device registrations. Local records stay on this device in Local-Only Spaces. Any App Store subscription must be managed separately."))
                    .arcaFont(.footnote).foregroundStyle(.secondary)
                if let resultMessage { Text(viewModel.language.localized(resultMessage)).arcaFont(.footnote) }
                if let errorMessage { Text(errorMessage).arcaFont(.footnote).foregroundStyle(ArcaTheme.dangerRed) }
                if viewModel.hasPendingAccountDeletionCleanup {
                    Button(viewModel.language.localized("Finish Local Cleanup")) { performDeletion() }
                        .disabled(viewModel.isDeletingCloudAccount || viewModel.isSyncing)
                } else if viewModel.cloudAccountConnected {
                    Button(viewModel.language.localized("Delete Cloud Account"), role: .destructive) { confirmDeletion = true }
                        .disabled(viewModel.isDeletingCloudAccount || viewModel.isSyncing)
                }
                if viewModel.isDeletingCloudAccount { ProgressView(viewModel.language.localized("Completing account deletion…")) }
            }
            .confirmationDialog(viewModel.language.localized("Permanently delete your cloud account?"), isPresented: $confirmDeletion, titleVisibility: .visible) {
                Button(viewModel.language.localized("Delete Account and Remote Data"), role: .destructive) { performDeletion() }
                Button(viewModel.language.localized("Cancel"), role: .cancel) {}
            } message: {
                Text(viewModel.language.localized("This cannot be undone. Your local records will be kept, and all Spaces will become Local-Only."))
            }
        }
    }

    private func performDeletion() {
        errorMessage = nil
        Task {
            do {
                try await viewModel.deleteCloudAccountAndKeepLocalRecords()
                resultMessage = "Cloud account deleted. Your local records are preserved."
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
