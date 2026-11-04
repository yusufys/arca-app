import SwiftUI
import UniformTypeIdentifiers
import ArcaCore

// MARK: - Screen 9: Field Editor & Reorder Interface (with Conversion Preview & Archived Retention)

@available(macOS 14.0, iOS 17.0, *)
public struct FieldEditorSheetView: View {
    @Bindable var viewModel: ArcaAppViewModel
    public let collectionId: UUID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @ViewState private var renamingField: FieldDefinition?
    @ViewState private var renameLabel = ""
    @ViewState private var convertingField: FieldDefinition?
    @ViewState private var targetConversionType: FieldType = .shortText
    @ViewState private var conversionPreview: FieldConversionPreview?
    @ViewState private var conversionError: String?
    @ViewState private var privacyTargetFieldId: UUID?
    @ViewState private var showingPrivacyConsent = false
    @ViewState private var privacyError: String?
    @ViewState private var newFieldLabel = ""
    @ViewState private var newFieldType: FieldType = .shortText

    private var currentSchema: CollectionSchema? {
        viewModel.schema(for: collectionId)
    }

    public var body: some View {
        VStack(spacing: 0) {
            ArcaSheetHeaderBar(
                title: "Manage Fields",
                subtitle: currentSchema.map { "\($0.name) • Schema v\($0.schemaVersion)" },
                leadingLabel: "Done",
                leadingAction: { dismiss() }
            )

            if let schema = currentSchema {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        ArcaSectionCard(title: "Collection privacy", icon: "hand.raised.fill") {
                            Text(schema.privacy == .localOnly ? "Sensitive · kept on this device" : schema.privacy == .syncWithConsent ? "Sensitive · cloud sync consented" : "Ordinary collection")
                            Button("Mark collection sensitive / change consent") {
                                Task {
                                    do {
                                        try await viewModel.keepSensitiveDataOnDevice(collectionId: schema.id)
                                        privacyTargetFieldId = nil; showingPrivacyConsent = true
                                    } catch { privacyError = error.localizedDescription }
                                }
                            }
                            if viewModel.pendingPrivacyDeletionCollectionIds.contains(schema.id) {
                                Text("Remote deletion pending. Uploads for this collection remain paused until confirmed. Offline devices may retain earlier copies.").font(.footnote).foregroundStyle(.orange)
                            }
                            if let privacyError { Text(privacyError).foregroundStyle(.red) }
                        }
                        ArcaSectionCard(
                            title: "Active Fields (\(schema.activeFields.count))",
                            subtitle: "Reorder, rename labels without losing values, or preview safe type conversions.",
                            icon: "slider.horizontal.3"
                        ) {
                            VStack(spacing: 8) {
                                ForEach(Array(schema.activeFields.enumerated()), id: \.element.id) { index, field in
                                    HStack(spacing: 10) {
                                        Image(systemName: field.type.iconName)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(ArcaTheme.accent)
                                            .frame(width: 30, height: 30)
                                            .background(Circle().fill(ArcaTheme.accent.opacity(0.12)))

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(field.label)
                                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                            Text("\(field.type.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)\(field.isRequired ? " • Required" : "")")
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        HStack(spacing: 4) {
                                            Button {
                                                Task { await viewModel.moveField(in: schema.id, fromIndex: index, direction: -1) }
                                            } label: {
                                                Image(systemName: "arrow.up")
                                                    .font(.system(size: 11, weight: .bold))
                                                    .frame(width: 26, height: 26)
                                                    .background(Circle().fill(Color.secondary.opacity(0.12)))
                                            }
                                            .buttonStyle(.plain)
                                            .disabled(index == 0)
                                            .opacity(index == 0 ? 0.35 : 1)

                                            Button {
                                                Task { await viewModel.moveField(in: schema.id, fromIndex: index, direction: 1) }
                                            } label: {
                                                Image(systemName: "arrow.down")
                                                    .font(.system(size: 11, weight: .bold))
                                                    .frame(width: 26, height: 26)
                                                    .background(Circle().fill(Color.secondary.opacity(0.12)))
                                            }
                                            .buttonStyle(.plain)
                                            .disabled(index == schema.activeFields.count - 1)
                                            .opacity(index == schema.activeFields.count - 1 ? 0.35 : 1)

                                            Menu {
                                                Button(field.privacy == nil ? "Mark Sensitive…" : "Sensitive Privacy / Consent…") {
                                                    Task {
                                                        do {
                                                            try await viewModel.keepSensitiveDataOnDevice(collectionId: schema.id, fieldId: field.id)
                                                            privacyTargetFieldId = field.id; showingPrivacyConsent = true
                                                        } catch { privacyError = error.localizedDescription }
                                                    }
                                                }
                                                Button("Rename Label (Preserves Values)…") {
                                                    renamingField = field
                                                    renameLabel = field.label
                                                }
                                                Button("Change Field Type (Dry-Run Preview)…") {
                                                    convertingField = field
                                                    targetConversionType = field.type
                                                    conversionPreview = viewModel.previewFieldConversion(collectionId: schema.id, field: field, targetType: field.type)
                                                }
                                                Divider()
                                                Button("Archive Field (Retain Existing Values)") {
                                                    Task {
                                                        await viewModel.removeField(in: schema.id, fieldId: field.id, policy: .archiveAndRetainValues)
                                                    }
                                                }
                                                Button("Permanently Purge Field & Values", role: .destructive) {
                                                    Task {
                                                        await viewModel.removeField(in: schema.id, fieldId: field.id, policy: .permanentlyPurgeValues)
                                                    }
                                                }
                                            } label: {
                                                Image(systemName: "ellipsis.circle.fill")
                                                    .font(.system(size: 20))
                                                    .foregroundStyle(.secondary)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(ArcaTheme.subtleFieldBackground(for: colorScheme))
                                    )
                                }
                            }
                        }

                        if let renamingField {
                            ArcaSectionCard(
                                title: "Rename “\(renamingField.label)”",
                                subtitle: "Renaming a field only updates its display label. All existing record values stay bound to its stable UUID.",
                                icon: "pencil"
                            ) {
                                ArcaStyledTextField("New Display Label", text: $renameLabel, icon: "tag")
                                HStack(spacing: 10) {
                                    Button("Cancel") { self.renamingField = nil }
                                        .buttonStyle(ArcaSecondaryButtonStyle(tint: .secondary))
                                    Button("Save Label") {
                                        Task {
                                            await viewModel.renameField(in: schema.id, fieldId: renamingField.id, newLabel: renameLabel)
                                            self.renamingField = nil
                                        }
                                    }
                                    .buttonStyle(ArcaPrimaryButtonStyle())
                                }
                            }
                        }

                        if let convertingField {
                            ArcaSectionCard(
                                title: "Convert Type for “\(convertingField.label)”",
                                subtitle: "Arca runs a non-destructive dry-run preview across all existing records before allowing a type change.",
                                icon: "arrow.triangle.swap"
                            ) {
                                HStack {
                                    Text("Target Type")
                                        .font(.system(size: 13, weight: .semibold))
                                    Spacer()
                                    Picker("Target Type", selection: $targetConversionType) {
                                        ForEach(FieldType.allCases, id: \.self) { t in
                                            Text(t.rawValue.replacingOccurrences(of: "_", with: " ").capitalized).tag(t)
                                        }
                                    }
                                    .labelsHidden()
                                }
                                .onChange(of: targetConversionType) { _, newValue in
                                    conversionPreview = viewModel.previewFieldConversion(collectionId: schema.id, field: convertingField, targetType: newValue)
                                    conversionError = nil
                                }

                                if let preview = conversionPreview {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Image(systemName: preview.isSafeToApplyWithoutLoss ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                                .foregroundStyle(preview.isSafeToApplyWithoutLoss ? ArcaTheme.secondaryEmerald : ArcaTheme.dangerRed)
                                            Text(preview.isSafeToApplyWithoutLoss
                                                 ? "All \(preview.totalRecordsExamined) records convert cleanly without data loss."
                                                 : "\(preview.failureCount) of \(preview.totalRecordsExamined) records cannot convert to \(preview.toType.rawValue).")
                                                .font(.system(size: 12, weight: .semibold))
                                        }
                                        ForEach(preview.sampleFailureDescriptions, id: \.self) { desc in
                                            Text("• \(desc)")
                                                .font(.system(size: 11))
                                                .foregroundStyle(ArcaTheme.dangerRed)
                                        }
                                    }
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(ArcaTheme.subtleFieldBackground(for: colorScheme)))
                                }

                                if let conversionError {
                                    Text(conversionError)
                                        .font(.caption)
                                        .foregroundStyle(ArcaTheme.dangerRed)
                                }

                                HStack(spacing: 10) {
                                    Button("Cancel") {
                                        self.convertingField = nil
                                        self.conversionPreview = nil
                                    }
                                    .buttonStyle(ArcaSecondaryButtonStyle(tint: .secondary))

                                    Button("Apply Conversion") {
                                        Task {
                                            do {
                                                try await viewModel.applyFieldConversion(collectionId: schema.id, fieldId: convertingField.id, targetType: targetConversionType)
                                                self.convertingField = nil
                                                self.conversionPreview = nil
                                            } catch {
                                                conversionError = error.localizedDescription
                                            }
                                        }
                                    }
                                    .buttonStyle(ArcaPrimaryButtonStyle())
                                    .disabled(!(conversionPreview?.isSafeToApplyWithoutLoss ?? false))
                                }
                            }
                        }

                        if !schema.archivedFields.isEmpty {
                            ArcaSectionCard(
                                title: "Archived Fields (Recoverable)",
                                subtitle: "Historical values remain stored and can be restored to active forms at any time.",
                                icon: "archivebox.fill",
                                iconTint: ArcaTheme.warmAmber
                            ) {
                               ForEach(schema.archivedFields) { archived in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(archived.label)
                                                .font(.system(size: 14, weight: .semibold))
                                            Text("Archived • Values preserved")
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        ArcaPillActionButton("Restore", icon: "arrow.uturn.backward") {
                                            Task { await viewModel.restoreArchivedField(in: schema.id, fieldId: archived.id) }
                                        }
                                    }
                                }
                            }
                        }

                        ArcaSectionCard(title: "Add New Field", icon: "plus.circle.fill") {
                            ArcaStyledTextField("Field Label", text: $newFieldLabel, icon: "plus")
                            HStack {
                                Text("Field Type")
                                    .font(.system(size: 13, weight: .medium))
                                Spacer()
                                Picker("Type", selection: $newFieldType) {
                                    ForEach(FieldType.allCases, id: \.self) { t in
                                        Text(t.rawValue.replacingOccurrences(of: "_", with: " ").capitalized).tag(t)
                                    }
                                }
                                .labelsHidden()
                            }
                            Button("Add Field") {
                                Task {
                                    await viewModel.addField(to: schema.id, label: newFieldLabel, type: newFieldType)
                                    newFieldLabel = ""
                                }
                            }
                            .buttonStyle(ArcaPrimaryButtonStyle())
                            .disabled(newFieldLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .padding(18)
                }
                .background(ArcaTheme.canvasBackground(for: colorScheme))
            }
        }
        .sheet(isPresented: $showingPrivacyConsent) {
            SensitivePrivacyConsentView(viewModel: viewModel, collectionId: collectionId, fieldId: privacyTargetFieldId)
        }
    }
}

// MARK: - Screen 10: Collection Record List with Search, Sort, and Filters

@available(macOS 14.0, iOS 17.0, *)
public struct CollectionRecordListView: View {
    @Bindable var viewModel: ArcaAppViewModel
    public let schema: CollectionSchema
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @ViewState private var searchText = ""
    @ViewState private var sortCriterion: RecordSortCriterion = .updatedAtDescending
    @ViewState private var favoritesOnly = false
    @ViewState private var hasAttachmentsOnly = false
    @ViewState private var selectedOptionFilter: (fieldId: UUID, optionId: String)?
    @ViewState private var showingAddRecord = false
    @ViewState private var showingFieldEditor = false

    public init(viewModel: ArcaAppViewModel, schema: CollectionSchema) {
        self.viewModel = viewModel
        self.schema = schema
    }

    private var liveSchema: CollectionSchema {
        viewModel.schema(for: schema.id) ?? schema
    }

    private var filteredRecords: [RecordItem] {
        var filters: [RecordFieldFilter] = []
        if favoritesOnly { filters.append(.favoritesOnly) }
        if hasAttachmentsOnly { filters.append(.hasAttachments) }
        if let sel = selectedOptionFilter {
            filters.append(.selectContains(fieldId: sel.fieldId, optionId: sel.optionId))
        }
        let query = RecordQuery(
            searchText: searchText,
            collectionId: liveSchema.id,
            filters: filters,
            sort: sortCriterion
        )
        return viewModel.queryRecords(query)
    }

    public var body: some View {
        let tint = ArcaTheme.color(fromHex: liveSchema.colorHex)
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                // Custom Mobile Collection Header
                HStack(spacing: 10) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.backward")
                                .font(.system(size: 13, weight: .bold))
                            Text("Back")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(ArcaTheme.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(ArcaTheme.accent.opacity(0.10)))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        showingFieldEditor = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 12, weight: .bold))
                            Text("Fields")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(ArcaTheme.cardBackground(for: colorScheme)))
                        .overlay(Capsule().strokeBorder(ArcaTheme.cardBorder(for: colorScheme), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Button {
                        showingAddRecord = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                            Text("Add")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(tint))
                    }
                    .buttonStyle(.plain)
                }

                // Collection Hero Title
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(tint)
                            .frame(width: 46, height: 46)
                        Image(systemName: liveSchema.iconName)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(liveSchema.name)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        Text("\(filteredRecords.count) record\(filteredRecords.count == 1 ? "" : "s") • \(liveSchema.activeFields.count) fields")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                // Search Bar
                ArcaSearchBar(text: $searchText, placeholder: "Filter \(liveSchema.name)…")

                // Filter & Sort Chips Strip
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Menu {
                            Picker("Sort By", selection: $sortCriterion) {
                                Text("Recently Updated").tag(RecordSortCriterion.updatedAtDescending)
                                Text("Oldest Updated").tag(RecordSortCriterion.updatedAtAscending)
                                Text("Title (A → Z)").tag(RecordSortCriterion.titleAscending)
                                Text("Title (Z → A)").tag(RecordSortCriterion.titleDescending)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.arrow.down")
                                Text("Sort")
                            }
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(ArcaTheme.cardBackground(for: colorScheme)))
                            .overlay(Capsule().strokeBorder(ArcaTheme.cardBorder(for: colorScheme), lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        filterChip(
                            title: "Pinned",
                            icon: favoritesOnly ? "pin.fill" : "pin",
                            isSelected: favoritesOnly,
                            tint: ArcaTheme.warmAmber
                        ) {
                            favoritesOnly.toggle()
                        }

                        filterChip(
                            title: "Files",
                            icon: "paperclip",
                            isSelected: hasAttachmentsOnly,
                            tint: ArcaTheme.accent
                        ) {
                            hasAttachmentsOnly.toggle()
                        }

                        if let selectField = liveSchema.activeFields.first(where: { $0.type == .singleSelect }) {
                            ForEach(selectField.options) { opt in
                                let isActive = selectedOptionFilter?.fieldId == selectField.id && selectedOptionFilter?.optionId == opt.id
                                filterChip(
                                    title: opt.label,
                                    icon: nil,
                                    isSelected: isActive,
                                    tint: tint
                                ) {
                                    if isActive {
                                        selectedOptionFilter = nil
                                    } else {
                                        selectedOptionFilter = (selectField.id, opt.id)
                                    }
                                }
                            }
                        }
                    }
                }

                // Records List
                if filteredRecords.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: liveSchema.iconName)
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text("No Records Match Your View")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Button("Add Record to \(liveSchema.name)") {
                            showingAddRecord = true
                        }
                        .buttonStyle(ArcaPrimaryButtonStyle(tint: tint, isFullWidth: false))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(28)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(ArcaTheme.cardBackground(for: colorScheme))
                    )
                } else {
                    VStack(spacing: 10) {
                        ForEach(filteredRecords) { record in
                            NavigationLink {
                                RecordDetailView(viewModel: viewModel, recordId: record.id, schema: liveSchema)
                            } label: {
                                RecordRowCardView(record: record, schema: liveSchema, locale: viewModel.language.locale)
                            }
                            .buttonStyle(.plain)
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
        .sheet(isPresented: $showingAddRecord) {
            AddEditRecordSheetView(viewModel: viewModel, schema: liveSchema, existingRecord: nil)
                .frame(minWidth: 370, idealWidth: 400, minHeight: 580, idealHeight: 680)
        }
        .sheet(isPresented: $showingFieldEditor) {
            FieldEditorSheetView(viewModel: viewModel, collectionId: liveSchema.id)
                .frame(minWidth: 370, idealWidth: 400, minHeight: 580, idealHeight: 680)
        }
    }

    private func filterChip(title: String, icon: String?, isSelected: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(isSelected ? tint : ArcaTheme.cardBackground(for: colorScheme))
            )
            .overlay(
                Capsule().strokeBorder(isSelected ? Color.clear : ArcaTheme.cardBorder(for: colorScheme), lineWidth: 1)
            )
            .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Screen 11: Add / Edit Record Form (Supports all 11 Field Types + Validation)

@available(macOS 14.0, iOS 17.0, *)
public struct AddEditRecordSheetView: View {
    @Bindable var viewModel: ArcaAppViewModel
    public let schema: CollectionSchema
    public let existingRecord: RecordItem?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @ViewState private var draftValues: [UUID: FieldValue] = [:]
    @ViewState private var isFavorite: Bool = false
    @ViewState private var saveError: String?
    @ViewState private var saving = false
    @ViewState private var showAttachmentPicker = false
    @ViewState private var attachmentFieldId: UUID?
    @ViewState private var validationErrors: [RecordValidationError] = []
    @ViewState private var currencyTextInputs: [UUID: String] = [:]
    @ViewState private var numberTextInputs: [UUID: String] = [:]

    public init(viewModel: ArcaAppViewModel, schema: CollectionSchema, existingRecord: RecordItem?) {
        self.viewModel = viewModel
        self.schema = schema
        self.existingRecord = existingRecord
    }

    public var body: some View {
        VStack(spacing: 0) {
            ArcaSheetHeaderBar(
                title: existingRecord == nil ? "New \(schema.name)" : "Edit Record",
                subtitle: "Saved locally first",
                leadingLabel: "Cancel",
                leadingAction: { dismiss() },
                trailingLabel: "Save",
                trailingAction: { saveDraft() }
            )

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    if let saveError { Text(saveError).foregroundStyle(ArcaTheme.dangerRed) }
                    if !validationErrors.isEmpty {
                        ArcaSectionCard(title: "Please Check These Fields", icon: "exclamationmark.triangle.fill", iconTint: ArcaTheme.dangerRed) {
                            ForEach(validationErrors) { err in
                                Label(err.errorDescription ?? err.reason, systemImage: "xmark.circle.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(ArcaTheme.dangerRed)
                            }
                        }
                    }

                    // Pin toggle card
                    ArcaSectionCard {
                        Button {
                            isFavorite.toggle()
                        } label: {
                            HStack {
                                Image(systemName: isFavorite ? "pin.fill" : "pin")
                                    .foregroundStyle(ArcaTheme.warmAmber)
                                Text("Pin Record to Favorites")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: isFavorite ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20))
                                    .foregroundStyle(isFavorite ? ArcaTheme.warmAmber : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    // Dynamic Schema Fields Card
                    ArcaSectionCard(title: "\(schema.name) Fields", icon: schema.iconName, iconTint: ArcaTheme.color(fromHex: schema.colorHex)) {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(schema.activeFields) { field in
                                fieldEditorRow(for: field)
                                if field.id != schema.activeFields.last?.id {
                                    Divider().opacity(0.45)
                                }
                            }
                        }
                    }

                    Button {
                        saveDraft()
                    } label: {
                        Label(existingRecord == nil ? "Save Record" : "Save Changes", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(ArcaPrimaryButtonStyle(tint: ArcaTheme.color(fromHex: schema.colorHex)))
                }
                .padding(18)
            }
            .background(ArcaTheme.canvasBackground(for: colorScheme))
        }
        .onAppear {
            populateInitialDraft()
        }
        .fileImporter(isPresented: $showAttachmentPicker, allowedContentTypes: [.item]) { result in
            switch result {
            case .success(let url):
                guard let fieldId = attachmentFieldId else { return }
                Task {
                    do {
                        let ref = try await viewModel.attachFile(from: url, to: schema.spaceId)
                        var refs: [AttachmentReference] = []
                        if case .attachments(let current) = draftValues[fieldId] { refs = current }
                        refs.append(ref)
                        draftValues[fieldId] = .attachments(refs)
                    } catch { saveError = error.localizedDescription }
                }
            case .failure(let error): saveError = error.localizedDescription
            }
        }
        .alert(isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Alert(title: Text(ArcaStrings.text("record.checkInput", language: viewModel.language)),
                  message: Text(saveError ?? ""),
                  dismissButton: .default(Text(ArcaStrings.text("common.ok", language: viewModel.language))))
        }
    }

    private func populateInitialDraft() {
        if let rec = existingRecord {
            draftValues = rec.values
            isFavorite = rec.isFavorite
        } else {
            for field in schema.activeFields {
                if let def = field.defaultValue {
                    draftValues[field.id] = def
                }
            }
        }
        for field in schema.activeFields {
            if case .currency(let money) = draftValues[field.id] {
                currencyTextInputs[field.id] = LocalizedNumericInput.editingText(for: money, locale: viewModel.language.locale)
            } else if case .number(let number) = draftValues[field.id] {
                numberTextInputs[field.id] = LocalizedNumericInput.editingText(for: number, locale: viewModel.language.locale)
            }
        }
    }

    @ViewBuilder
    private func fieldEditorRow(for field: FieldDefinition) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(field.label, systemImage: field.type.iconName)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                if field.isRequired {
                    Text("REQUIRED")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(ArcaTheme.accent.opacity(0.12)))
                        .foregroundStyle(ArcaTheme.accent)
                }
                Spacer()
            }

            switch field.type {
            case .shortText:
                ArcaStyledTextField(
                    field.label,
                    text: Binding(
                        get: {
                            if case .shortText(let s) = draftValues[field.id] { return s }
                            return ""
                        },
                        set: { draftValues[field.id] = $0.isEmpty ? .null : .shortText($0) }
                    )
                )

            case .longText:
                TextEditor(text: Binding(
                    get: {
                        if case .longText(let s) = draftValues[field.id] { return s }
                        return ""
                    },
                    set: { draftValues[field.id] = $0.isEmpty ? .null : .longText($0) }
                ))
                .accessibilityLabel(Text(field.label))
                .font(.body)
                .frame(minHeight: 74)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(ArcaTheme.subtleFieldBackground(for: colorScheme))
                )

            case .number:
                ArcaStyledTextField(
                    field.label,
                    text: Binding(
                        get: { numberTextInputs[field.id] ?? "" },
                        set: { str in
                            numberTextInputs[field.id] = str
                            if let parsed = LocalizedNumericInput.number(str, locale: viewModel.language.locale) {
                                draftValues[field.id] = .number(parsed)
                            } else if str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                draftValues[field.id] = .null
                            }
                        }
                    ),
                    icon: "number"
                )

            case .currency:
                HStack(spacing: 8) {
                    Text(field.validation.defaultCurrencyCode)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(ArcaTheme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(ArcaTheme.accent.opacity(0.12)))

                    ArcaStyledTextField(
                        "\(field.label) (\(field.validation.defaultCurrencyCode))",
                        text: Binding(
                            get: { currencyTextInputs[field.id] ?? "" },
                            set: { str in
                                currencyTextInputs[field.id] = str
                                if let money = LocalizedNumericInput.money(str, currencyCode: field.validation.defaultCurrencyCode, locale: viewModel.language.locale) {
                                    draftValues[field.id] = .currency(money)
                                } else if str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    draftValues[field.id] = .null
                                }
                            }
                        )
                    )
                }

            case .date:
                DatePicker(
                    selection: Binding(
                        get: {
                            if case .date(let cd) = draftValues[field.id] { return cd.toDate() }
                            return Date()
                        },
                        set: { draftValues[field.id] = .date(CalendarDate(date: $0)) }
                    ),
                    displayedComponents: [.date]
                ) {
                    Text(field.label)
                        .font(.system(size: 13, weight: .medium))
                }

            case .dateTime:
                DatePicker(
                    selection: Binding(
                        get: {
                            if case .dateTime(let dt) = draftValues[field.id] { return dt }
                            return Date()
                        },
                        set: { draftValues[field.id] = .dateTime($0) }
                    ),
                    displayedComponents: [.date, .hourAndMinute]
                ) {
                    Text(field.label)
                        .font(.system(size: 13, weight: .medium))
                }

            case .boolean:
                Toggle(field.label, isOn: Binding(
                    get: {
                        if case .boolean(let b) = draftValues[field.id] { return b }
                        return false
                    },
                    set: { draftValues[field.id] = .boolean($0) }
                ))
                .font(.system(size: 14, weight: .medium))

            case .singleSelect:
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        let currentSelection: String = {
                            if case .singleSelect(let s) = draftValues[field.id] { return s }
                            return ""
                        }()
                        ForEach(field.options) { opt in
                            let selected = currentSelection == opt.id
                            Button {
                                draftValues[field.id] = selected ? .null : .singleSelect(opt.id)
                            } label: {
                                Text(opt.label)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Capsule().fill(selected ? ArcaTheme.accent : ArcaTheme.subtleFieldBackground(for: colorScheme)))
                                    .foregroundStyle(selected ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                }

            case .multiSelect:
                let currentSet: Set<String> = {
                    if case .multiSelect(let arr) = draftValues[field.id] { return Set(arr) }
                    return []
                }()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(field.options) { opt in
                            let selected = currentSet.contains(opt.id)
                            Button {
                                var updated = currentSet
                                if selected { updated.remove(opt.id) } else { updated.insert(opt.id) }
                                draftValues[field.id] = updated.isEmpty ? .null : .multiSelect(Array(updated).sorted())
                            } label: {
                                Text(opt.label)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Capsule().fill(selected ? ArcaTheme.accent : ArcaTheme.subtleFieldBackground(for: colorScheme)))
                                    .foregroundStyle(selected ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                }

            case .rating:
                let currentRating: Int = {
                    if case .rating(let r) = draftValues[field.id] { return r }
                    return 0
                }()
                HStack(spacing: 10) {
                    ForEach(1...field.validation.maxRating, id: \.self) { star in
                        Button {
                            draftValues[field.id] = .rating(star)
                        } label: {
                            Image(systemName: star <= currentRating ? "star.fill" : "star")
                                .font(.system(size: 22))
                                .foregroundStyle(star <= currentRating ? ArcaTheme.warmAmber : Color.secondary.opacity(0.35))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("\(field.label), \(star) / \(field.validation.maxRating)"))
                        .accessibilityAddTraits(star == currentRating ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)

            case .attachment:
                let currentAttachments: [AttachmentReference] = {
                    if case .attachments(let refs) = draftValues[field.id] { return refs }
                    return []
                }()
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(currentAttachments) { att in
                        HStack {
                            Image(systemName: "doc.fill")
                                .foregroundStyle(ArcaTheme.accent)
                            Text(att.filename)
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text("\(ByteCountFormatter.string(fromByteCount: att.byteSize, countStyle: .file))")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(ArcaTheme.subtleFieldBackground(for: colorScheme)))
                    }
                    Button {
                        attachmentFieldId = field.id
                        showAttachmentPicker = true
                    } label: {
                        Label("Attach File from Files", systemImage: "paperclip.badge.plus")
                    }
                    .buttonStyle(ArcaSecondaryButtonStyle())
                    .disabled(viewModel.spaces.first(where: { $0.id == schema.spaceId })?.storageMode != .localOnly)
                    if viewModel.spaces.first(where: { $0.id == schema.spaceId })?.storageMode != .localOnly {
                        Text("File attachments are available in Local-Only Spaces. Cloud attachment upload is not available yet.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func saveDraft() {
        guard !saving else { return }
        for field in schema.activeFields {
            if field.type == .number, let text = numberTextInputs[field.id],
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               LocalizedNumericInput.number(text, locale: viewModel.language.locale) == nil {
                saveError = String(format: ArcaStrings.text("record.invalidNumber", language: viewModel.language), field.label)
                return
            }
            if field.type == .currency, let text = currencyTextInputs[field.id],
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               LocalizedNumericInput.money(text, currencyCode: field.validation.defaultCurrencyCode, locale: viewModel.language.locale) == nil {
                saveError = String(format: ArcaStrings.text("record.invalidAmount", language: viewModel.language), field.label)
                return
            }
        }
        saveError = nil
        let errs = SchemaEngine.validate(values: draftValues, against: schema)
        if !errs.isEmpty {
            validationErrors = errs
            saveError = errs.map { $0.errorDescription ?? $0.reason }.joined(separator: "\n")
            return
        }
        saving = true
        Task {
            defer { saving = false }
            do {
                try await viewModel.saveRecord(existingRecord: existingRecord, schema: schema,
                                               values: draftValues, isFavorite: isFavorite)
                dismiss()
            } catch {
                saveError = "Could not save this record. " + error.localizedDescription
            }
        }
    }
}

// MARK: - Screen 12: Record Detail with Attachments, Duplicate, Local QR Deep Link, and Explicit Public Snapshot

@available(macOS 14.0, iOS 17.0, *)
public struct RecordDetailView: View {
    @Bindable var viewModel: ArcaAppViewModel
    public let recordId: UUID
    public let schema: CollectionSchema
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @ViewState private var showingEditSheet = false
    @ViewState private var showingLocalQRSheet = false
    @ViewState private var showingPublicSnapshotSheet = false
    @ViewState private var selectedSnapshotFieldIds: Set<UUID> = []
    @ViewState private var pendingRecordDeletion: RecordDeletionTarget?

    private var record: RecordItem? {
        viewModel.record(for: recordId)
    }

    private var liveSchema: CollectionSchema {
        viewModel.schema(for: schema.id) ?? schema
    }

    public init(viewModel: ArcaAppViewModel, recordId: UUID, schema: CollectionSchema) {
        self.viewModel = viewModel
        self.recordId = recordId
        self.schema = schema
    }

    public var body: some View {
        let tint = ArcaTheme.color(fromHex: liveSchema.colorHex)
        Group {
            if let rec = record {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        // Top Navigation Bar
                        HStack {
                            Button {
                                dismiss()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.backward")
                                        .font(.system(size: 13, weight: .bold))
                                    Text(liveSchema.name)
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                }
                                .foregroundStyle(ArcaTheme.accent)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(ArcaTheme.accent.opacity(0.10)))
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Button {
                                Task { await viewModel.toggleFavorite(recordId: rec.id) }
                            } label: {
                                Image(systemName: rec.isFavorite ? "pin.fill" : "pin")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(rec.isFavorite ? .white : ArcaTheme.warmAmber)
                                    .frame(width: 34, height: 34)
                                    .background(Circle().fill(rec.isFavorite ? ArcaTheme.warmAmber : ArcaTheme.warmAmber.opacity(0.14)))
                            }
                            .buttonStyle(.plain)

                            Button {
                                showingEditSheet = true
                            } label: {
                                Text("Edit")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(Capsule().fill(tint))
                            }
                            .buttonStyle(.plain)
                        }

                        // Record Hero Header Card
                        ArcaSectionCard {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(tint)
                                        .frame(width: 44, height: 44)
                                    Image(systemName: liveSchema.iconName)
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(.white)
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(rec.title(using: liveSchema))
                                        .font(.system(size: 21, weight: .bold, design: .rounded))
                                    Text("\(liveSchema.name) • Revision \(rec.revision) • Updated \(rec.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        // Structured Fields Card
                        ArcaSectionCard(title: "Saved Fields", icon: "list.clipboard.fill", iconTint: tint) {
                            VStack(alignment: .leading, spacing: 14) {
                                ForEach(liveSchema.activeFields) { field in
                                    let val = rec.values[field.id] ?? .null
                                    if !val.isNullOrEmpty {
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack(spacing: 5) {
                                                Image(systemName: field.type.iconName)
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .foregroundStyle(tint)
                                                Text(field.label.uppercased())
                                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                                    .tracking(0.5)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Text(val.plainTextSummary(for: field, locale: viewModel.language.locale))
                                                .font(.system(size: 15, weight: .medium))
                                                .foregroundStyle(.primary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(ArcaTheme.subtleFieldBackground(for: colorScheme))
                                        )
                                    }
                                }
                            }
                        }

                        // Attachments Card
                        if !rec.allAttachments.isEmpty {
                            ArcaSectionCard(title: "Attachments (SHA-256 Verified)", icon: "paperclip", iconTint: ArcaTheme.secondaryEmerald) {
                                ForEach(rec.allAttachments) { att in
                                    HStack(spacing: 12) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(ArcaTheme.secondaryEmerald.opacity(0.14))
                                                .frame(width: 38, height: 38)
                                            Image(systemName: "doc.text.fill")
                                                .foregroundStyle(ArcaTheme.secondaryEmerald)
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(att.filename)
                                                .font(.system(size: 14, weight: .semibold))
                                            Text("\(ByteCountFormatter.string(fromByteCount: att.byteSize, countStyle: .file)) • SHA-256 \(att.sha256Hex.prefix(10))…")
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text(att.uploadState.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                                            .font(.system(size: 10, weight: .bold, design: .rounded))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Capsule().fill(ArcaTheme.secondaryEmerald.opacity(0.12)))
                                            .foregroundStyle(ArcaTheme.secondaryEmerald)
                                    }
                                }
                            }
                        }

                        // Actions Card
                        ArcaSectionCard(title: "Record Actions & Sharing", icon: "square.and.arrow.up") {
                            VStack(spacing: 10) {
                                HStack(spacing: 10) {
                                    Button {
                                        Task { await viewModel.duplicateRecord(rec) }
                                    } label: {
                                        Label("Duplicate", systemImage: "plus.square.on.square")
                                    }
                                    .buttonStyle(ArcaSecondaryButtonStyle(isFullWidth: true))

                                    Button {
                                        showingLocalQRSheet = true
                                    } label: {
                                        Label("Local QR Tag", systemImage: "qrcode")
                                    }
                                    .buttonStyle(ArcaSecondaryButtonStyle(isFullWidth: true))
                                }

                                #if DEBUG
                                Button {
                                    selectedSnapshotFieldIds = Set(liveSchema.activeFields.map(\.id))
                                    showingPublicSnapshotSheet = true
                                } label: {
                                    Label("Create Explicit Public Snapshot…", systemImage: "square.and.arrow.up.on.square")
                                }
                                .buttonStyle(ArcaSecondaryButtonStyle(tint: ArcaTheme.secondaryEmerald, isFullWidth: true))
                                #endif

                                Button {
                                    pendingRecordDeletion = RecordDeletionTarget(id: rec.id, title: rec.title(using: liveSchema))
                                } label: {
                                    Label("Delete Record", systemImage: "trash")
                                }
                                .buttonStyle(ArcaSecondaryButtonStyle(tint: ArcaTheme.dangerRed, isFullWidth: true))
                            }
                        }
                    }
                    .padding(18)
                }
                .background(ArcaTheme.canvasBackground(for: colorScheme))
                #if os(iOS)
                .toolbar(.hidden, for: .navigationBar)
                #endif
                .sheet(isPresented: $showingEditSheet) {
                    AddEditRecordSheetView(viewModel: viewModel, schema: liveSchema, existingRecord: rec)
                        .frame(minWidth: 370, idealWidth: 400, minHeight: 580, idealHeight: 680)
                }
                .sheet(isPresented: $showingLocalQRSheet) {
                    localQRSheet(for: rec)
                        .frame(minWidth: 360, idealWidth: 390, minHeight: 420, idealHeight: 460)
                }
                .sheet(isPresented: $showingPublicSnapshotSheet) {
                    publicSnapshotSheet(for: rec)
                        .frame(minWidth: 370, idealWidth: 400, minHeight: 540, idealHeight: 620)
                }
            } else {
                Text("Record no longer available.")
                    .foregroundStyle(.secondary)
            }
        }
        .alert(item: $pendingRecordDeletion) { target in
            Alert(
                title: Text(String(format: ArcaStrings.text("delete.recordTitle", language: viewModel.language), target.title)),
                message: Text(ArcaStrings.text("delete.recordBody", language: viewModel.language)),
                primaryButton: .destructive(Text(ArcaStrings.text("common.delete", language: viewModel.language))) {
                    Task {
                        await viewModel.deleteRecord(id: target.id)
                        dismiss()
                    }
                },
                secondaryButton: .cancel(Text(ArcaStrings.text("common.cancel", language: viewModel.language)))
            )
        }
    }

    private struct RecordDeletionTarget: Identifiable {
        let id: UUID
        let title: String
    }

    private func localQRSheet(for rec: RecordItem) -> some View {
        let deepLink = OptionalCapabilityEngine.localRecordDeepLink(spaceId: rec.spaceId, collectionId: rec.collectionId, recordId: rec.id)
        return VStack(spacing: 0) {
            ArcaSheetHeaderBar(title: "Local QR Deep Link", leadingLabel: "Done", leadingAction: { showingLocalQRSheet = false })

            VStack(spacing: 20) {
                Spacer()
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(ArcaTheme.cardBackground(for: colorScheme))
                        .frame(width: 140, height: 140)
                        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 82))
                        .foregroundStyle(ArcaTheme.accent)
                }

                Text("Physical Asset Tag Deep Link")
                    .font(.system(size: 18, weight: .bold, design: .rounded))

                Text(deepLink.absoluteString)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(ArcaTheme.subtleFieldBackground(for: colorScheme)))

                Text("Privacy guarantee: A local QR code only identifies this record by UUID on devices that already have this Space. It never embeds or transmits your record contents.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)

                Spacer()
            }
            .padding(20)
            .background(ArcaTheme.canvasBackground(for: colorScheme))
        }
    }

    private func publicSnapshotSheet(for rec: RecordItem) -> some View {
        VStack(spacing: 0) {
            ArcaSheetHeaderBar(
                title: "Public Snapshot",
                subtitle: "Explicit Read-Only Share",
                leadingLabel: "Cancel",
                leadingAction: { showingPublicSnapshotSheet = false }
            )

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    ArcaSectionCard(
                        title: "1. Select Fields to Include",
                        subtitle: "Public snapshots are completely separate from private sync. Choose the exact fields to include and revoke anytime.",
                        icon: "checklist"
                    ) {
                        ForEach(liveSchema.activeFields) { field in
                            let isSelected = selectedSnapshotFieldIds.contains(field.id)
                            Button {
                                if isSelected { selectedSnapshotFieldIds.remove(field.id) } else { selectedSnapshotFieldIds.insert(field.id) }
                            } label: {
                                HStack {
                                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                        .font(.system(size: 18))
                                        .foregroundStyle(isSelected ? ArcaTheme.accent : .secondary)
                                    Text(field.label)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text((rec.values[field.id] ?? .null).plainTextSummary(for: field))
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .padding(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    ArcaSectionCard(title: "2. Snapshot Preview", icon: "eye.fill") {
                        ForEach(liveSchema.activeFields.filter { selectedSnapshotFieldIds.contains($0.id) }) { field in
                            HStack {
                                Text(field.label)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text((rec.values[field.id] ?? .null).plainTextSummary(for: field))
                                    .font(.system(size: 13, weight: .medium))
                            }
                        }
                    }

                    Button("Publish Explicit Snapshot") {
                        viewModel.createPublicSnapshot(for: rec, schema: liveSchema, selectedFieldIds: selectedSnapshotFieldIds)
                        showingPublicSnapshotSheet = false
                    }
                    .buttonStyle(ArcaPrimaryButtonStyle())
                    .disabled(selectedSnapshotFieldIds.isEmpty)
                }
                .padding(18)
            }
            .background(ArcaTheme.canvasBackground(for: colorScheme))
        }
    }
}
