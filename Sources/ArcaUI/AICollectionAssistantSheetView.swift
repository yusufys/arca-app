import SwiftUI
import ArcaCore
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// A user-directed handoff to an external assistant. Preparing a prompt never opens
/// another app or changes the clipboard; each handoff requires an explicit action.
@available(macOS 14.0, iOS 17.0, *)
public struct AICollectionAssistantSheetView: View {
    @Bindable var viewModel: ArcaAppViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    @ViewState private var intent = ""
    @ViewState private var preparedPrompt: String?
    @ViewState private var isImportingExistingReply = false
    @ViewState private var reply = ""
    @ViewState private var preview: CollectionSchema?
    @ViewState private var isPreparing = false
    @ViewState private var isCreating = false
    @ViewState private var errorMessage: String?
    @ViewState private var clipboardMessage: String?

    public init(viewModel: ArcaAppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            ArcaSheetHeaderBar(
                title: text("creation.ai"),
                subtitle: preview == nil ? text("creation.steps") : text("creation.review"),
                leadingLabel: isCreating ? nil : text("creation.close"),
                leadingAction: { dismiss() }
            )

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    if preparedPrompt == nil && !isImportingExistingReply {
                        intentSection
                    } else {
                        if preparedPrompt != nil {
                            intentSummary
                        }
                        if let preview {
                            previewSection(preview)
                        } else {
                            if preparedPrompt != nil {
                                assistantSection
                            }
                            replySection
                        }
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.circle")
                            .arcaFont(.subheadline)
                            .foregroundStyle(ArcaTheme.dangerRed)
                            .accessibilityIdentifier("aiCollection.error")
                    }
                }
                .padding(18)
            }
            .background(ArcaTheme.canvasBackground(for: colorScheme))
        }
        .interactiveDismissDisabled(isCreating)
        .onChange(of: reply) { _, _ in
            preview = nil
            errorMessage = nil
        }
        .accessibilityIdentifier("aiCollection.sheet")
        .environment(\.layoutDirection, viewModel.language.layoutDirection)
        .environment(\.locale, viewModel.language.locale)
    }

    private var intentSection: some View {
        ArcaSectionCard(
            title: text("creation.intentTitle"),
            subtitle: text("creation.intentBody"),
            icon: "sparkles"
        ) {
            TextField(
                text("creation.intentExample"),
                text: $intent,
                axis: .vertical
            )
            .lineLimit(4...7)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(ArcaTheme.subtleFieldBackground(for: colorScheme)))
            .disabled(isPreparing)
            .accessibilityLabel(text("creation.intentLabel"))
            .accessibilityIdentifier("aiCollection.intent")

            Text(text("creation.intentPrivacy"))
                .arcaFont(.caption)
                .foregroundStyle(.secondary)

            Button {
                preparePrompt()
            } label: {
                HStack(spacing: 8) {
                    if isPreparing { ProgressView().tint(.white) }
                    Text(isPreparing ? text("creation.preparing") : text("creation.prepare"))
                }
            }
            .buttonStyle(ArcaPrimaryButtonStyle())
            .disabled(isPreparing || intent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("aiCollection.prepare")

            Button(text("creation.existingReply")) {
                isImportingExistingReply = true
                errorMessage = nil
            }
            .buttonStyle(ArcaSecondaryButtonStyle(isFullWidth: true))
            .disabled(isPreparing)
            .accessibilityIdentifier("aiCollection.existingReply")
        }
    }

    private var intentSummary: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .foregroundStyle(ArcaTheme.accent)
            Text(intent.trimmingCharacters(in: .whitespacesAndNewlines))
                .arcaFont(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(text("creation.edit")) {
                preparedPrompt = nil
                isImportingExistingReply = false
                reply = ""
                preview = nil
                errorMessage = nil
                clipboardMessage = nil
            }
            .arcaFont(.subheadline, weight: .semibold)
            .disabled(isCreating)
        }
    }

    private var assistantSection: some View {
        ArcaSectionCard(
            title: text("creation.askTitle"),
            subtitle: text("creation.askBody"),
            icon: "bubble.left.and.bubble.right"
        ) {
            Button {
                copyPrompt()
            } label: {
                Label(text("creation.copy"), systemImage: "doc.on.doc")
            }
            .buttonStyle(ArcaPrimaryButtonStyle())
            .accessibilityIdentifier("aiCollection.copyPrompt")

            VStack(spacing: 8) {
                ForEach(AssistantDestination.allCases) { assistant in
                    Button {
                        copyPrompt()
                        openURL(assistant.url) { accepted in
                            if !accepted {
                                errorMessage = text("creation.openFailed", assistant.rawValue)
                            }
                        }
                    } label: {
                        HStack {
                            Text(text("creation.copyOpen", assistant.rawValue))
                            Spacer()
                            Image(systemName: "arrow.up.right")
                        }
                    }
                    .buttonStyle(ArcaSecondaryButtonStyle(isFullWidth: true))
                    .accessibilityHint(text("creation.openHint"))
                    .accessibilityIdentifier("aiCollection.open.\(assistant.rawValue)")
                }
            }

            Text(text("creation.openHint"))
                .arcaFont(.caption)
                .foregroundStyle(.secondary)

            if let clipboardMessage {
                Label(clipboardMessage, systemImage: "checkmark.circle.fill")
                    .arcaFont(.caption)
                    .foregroundStyle(ArcaTheme.secondaryEmerald)
                    .accessibilityIdentifier("aiCollection.clipboardStatus")
            }
        }
    }

    private var replySection: some View {
        ArcaSectionCard(
            title: text("creation.replyTitle"),
            subtitle: text("creation.replyBody"),
            icon: "doc.on.clipboard"
        ) {
            #if os(iOS)
            PasteButton(payloadType: String.self) { values in
                guard let text = values.first else { return }
                reply = text
                preview = nil
                errorMessage = nil
            }
            .tint(ArcaTheme.accent)
            .controlSize(.large)
            .accessibilityLabel(text("creation.paste"))
            .accessibilityIdentifier("aiCollection.pasteReply")
            #else
            Button {
                pasteReply()
            } label: {
                Label(text("creation.paste"), systemImage: "doc.on.clipboard")
            }
            .buttonStyle(ArcaSecondaryButtonStyle(isFullWidth: true))
            .accessibilityIdentifier("aiCollection.pasteReply")
            #endif

            TextEditor(text: $reply)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .font(.system(.footnote, design: .monospaced))
                .frame(minHeight: 150)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 12).fill(ArcaTheme.subtleFieldBackground(for: colorScheme)))
                .accessibilityLabel(text("creation.replyLabel"))
                .accessibilityIdentifier("aiCollection.reply")

            Button(text("creation.preview")) {
                errorMessage = nil
                do {
                    preview = try viewModel.previewAICollectionReply(reply)
                } catch {
                    preview = nil
                    errorMessage = text("creation.invalidReply")
                }
            }
            .buttonStyle(ArcaPrimaryButtonStyle())
            .disabled(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("aiCollection.preview")

            if preparedPrompt == nil {
                Button(text("creation.backToIntent")) {
                    isImportingExistingReply = false
                    preview = nil
                    errorMessage = nil
                }
                .buttonStyle(ArcaSecondaryButtonStyle(isFullWidth: true))
            }
        }
    }

    private func previewSection(_ schema: CollectionSchema) -> some View {
        ArcaSectionCard(
            title: schema.name,
            subtitle: text("creation.fieldCount", schema.activeFields.count),
            icon: "checkmark.circle"
        ) {
            ForEach(schema.activeFields) { field in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 10) {
                        Image(systemName: field.type.iconName)
                            .foregroundStyle(ArcaTheme.accent)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(field.label)
                                .arcaFont(.subheadline, weight: .semibold)
                            Text(ArcaStrings.text(field.type.displayNameKey, language: viewModel.language))
                                .arcaFont(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if field.isPrimaryTitle {
                            Text(text("creation.titleField"))
                                .arcaFont(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if field.isRequired {
                            Text(text("creation.required"))
                                .arcaFont(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !field.options.isEmpty {
                        Text(field.options.map(\.label).joined(separator: " • "))
                            .arcaFont(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 32)
                    }
                }
                .padding(.vertical, 5)
            }

            if let space = viewModel.currentSpace {
                Label(text("creation.space", space.name), systemImage: space.iconName)
                    .arcaFont(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                createCollection(schema)
            } label: {
                HStack(spacing: 8) {
                    if isCreating { ProgressView().tint(.white) }
                    Text(isCreating ? text("creation.creating") : text("creation.create"))
                }
            }
            .buttonStyle(ArcaPrimaryButtonStyle())
            .disabled(isCreating)
            .accessibilityIdentifier("aiCollection.create")

            Button(text("creation.editReply")) { preview = nil }
                .buttonStyle(ArcaSecondaryButtonStyle(isFullWidth: true))
                .disabled(isCreating)
        }
    }

    private func text(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: ArcaStrings.text(key, language: viewModel.language), locale: viewModel.language.locale, arguments: arguments)
    }

    private func preparePrompt() {
        isPreparing = true
        errorMessage = nil
        Task { @MainActor in
            defer { isPreparing = false }
            do {
                preparedPrompt = try await viewModel.prepareAIAssistantPrompt(intent: intent)
            } catch {
                errorMessage = text("creation.requestFailed")
            }
        }
    }

    private func copyPrompt() {
        guard let preparedPrompt else { return }
        #if os(iOS)
        UIPasteboard.general.string = preparedPrompt
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(preparedPrompt, forType: .string)
        #endif
        clipboardMessage = text("creation.copied")
        errorMessage = nil
    }

    private func pasteReply() {
        #if os(macOS)
        let pastedText = NSPasteboard.general.string(forType: .string)
        #else
        let pastedText: String? = nil
        #endif
        guard let pastedText, !pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = text("creation.clipboardEmpty")
            return
        }
        reply = pastedText
        preview = nil
        errorMessage = nil
    }

    private func createCollection(_ schema: CollectionSchema) {
        isCreating = true
        errorMessage = nil
        Task { @MainActor in
            defer { isCreating = false }
            do {
                try await viewModel.createAICollection(from: schema)
                dismiss()
            } catch {
                errorMessage = text("creation.requestFailed")
            }
        }
    }
}

private enum AssistantDestination: String, CaseIterable, Identifiable {
    case chatGPT = "ChatGPT"
    case claude = "Claude"
    case gemini = "Gemini"

    var id: String { rawValue }

    var url: URL {
        switch self {
        case .chatGPT: return URL(string: "https://chatgpt.com/")!
        case .claude: return URL(string: "https://claude.ai/new")!
        case .gemini: return URL(string: "https://gemini.google.com/app")!
        }
    }
}
