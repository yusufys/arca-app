import SwiftUI
import ArcaCore

/// The first action persists Local-Only before this consent sheet opens.
@available(macOS 14.0, iOS 17.0, *)
public struct SensitivePrivacyConsentView: View {
    @Bindable var viewModel: ArcaAppViewModel
    let collectionId: UUID
    var fieldId: UUID?
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirmation = ""
    @State private var error: String?
    @State private var working = false
    @State private var configured = false

    private var name: String {
        guard let schema = viewModel.schema(for: collectionId) else { return "this item" }
        return fieldId.flatMap { id in schema.fields.first { $0.id == id }?.label } ?? schema.name
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(viewModel.language.format("Do you want to sync “%@” to the cloud?", name)).arcaFont(.headline)
                    Text(viewModel.language.localized("It is kept on this device until you explicitly enable sync. A Local-Only Space or collection overrides this choice."))
                    Button(viewModel.language.localized("Keep on this device")) { dismiss() }
                }
                Section(viewModel.language.localized(configured ? "Verify master password" : "Set up a master password")) {
                    SecureField(viewModel.language.localized(configured ? "Master password" : "At least 12 characters"), text: $password)
                        .textContentType(configured ? .password : .newPassword)
                    if !configured { SecureField(viewModel.language.localized("Confirm master password"), text: $confirmation).textContentType(.newPassword) }
                    Text(viewModel.language.localized("This password is verified on this device. It is separate from your account password and recovery phrase.")).arcaFont(.footnote)
                    Button(viewModel.language.localized("Sync securely")) {
                        working = true
                        Task {
                            do {
                                if !configured {
                                    try viewModel.setUpConsentMasterPassword(password, confirmation: confirmation)
                                    configured = true
                                }
                                try await viewModel.consentToSensitiveCloudSync(collectionId: collectionId, fieldId: fieldId, password: password)
                                password = ""; confirmation = ""; dismiss()
                            } catch { self.error = error.localizedDescription; password = ""; confirmation = "" }
                            working = false
                        }
                    }.disabled(working || password.isEmpty)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                if viewModel.pendingPrivacyDeletionCollectionIds.contains(collectionId) {
                    Section(viewModel.language.localized("Remote deletion pending")) {
                        Text(viewModel.language.localized("Older server copies must be removed before this collection can upload again. Reconnect and sync to retry. An offline device may still hold an earlier copy."))
                    }
                }
            }
            .navigationTitle(viewModel.language.localized("Sensitive data"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(viewModel.language.localized("Cancel")) { password = ""; dismiss() } } }
        }.onAppear { configured = viewModel.hasConsentMasterPassword }
    }
}
