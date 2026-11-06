import SwiftUI
import UniformTypeIdentifiers
import ArcaCore

#if os(iOS)
import PhotosUI
#endif

// MARK: - Collection Settings Screen (⚙️ Name, Theme Color, Compact Field, Add Mode, 4-Tab Icon Picker & Fields)

@available(macOS 14.0, iOS 17.0, *)
public struct CollectionSettingsView: View {
    @Bindable var viewModel: ArcaAppViewModel
    public let schema: CollectionSchema
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let presentationStore: CollectionPresentationStore = .shared

    @ViewState private var draftName: String
    @ViewState private var didLoadIconState = false
    @ViewState private var metadataSaving = false
    @ViewState private var metadataError: String?
    @ViewState private var colColorDropdownOpen = false
    @ViewState private var compactFieldDropdownOpen = false
    @ViewState private var addFormModeDropdownOpen = false

    @ViewState private var iconTab: CollectionIconTab = .library
    @ViewState private var selectedLibraryCategory: String = CollectionDesignCatalog.iconCategories[0].titleKey
    @ViewState private var selectedLibrarySubcategory: String = CollectionDesignCatalog.iconCategories[0].subcategories[0].titleKey
    @ViewState private var customMonogram: String = ""
    @ViewState private var customEmojiInput: String = ""
    @ViewState private var showingIconFileImporter = false
    @ViewState private var iconUploadError: String?

    #if os(iOS)
    @ViewState private var selectedPhotoPickerItem: PhotosPickerItem?
    #endif

    @ViewState private var showingFieldEditor = false
    @ViewState private var showingPrivacyConsent = false
    @ViewState private var privacyError: String?
    @ViewState private var activeTestAddRecordSchema: CollectionSchema?

    public init(viewModel: ArcaAppViewModel, schema: CollectionSchema) {
        self.viewModel = viewModel
        self.schema = schema
        self._draftName = ViewState(initialValue: schema.name)
    }

    private var liveSchema: CollectionSchema {
        viewModel.schema(for: schema.id) ?? schema
    }

    private var palette: CollectionColorPalette { CollectionColorPalette(hex: liveSchema.colorHex) }
    private var tint: Color { palette.fill }
    private var ink: Color { palette.ink(for: colorScheme) }
    private var trimmedName: String { draftName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var nameNeedsSave: Bool { trimmedName != liveSchema.name }

    private var activeColorOption: CollectionColorOption {
        CollectionDesignCatalog.colorOption(for: liveSchema.colorHex)
    }

    private var secondaryFieldOptions: [FieldDefinition] {
        CollectionPresentationStore.secondaryFieldCandidates(for: liveSchema)
    }

    private var activeCompactField: FieldDefinition? {
        presentationStore.resolvedSecondaryField(for: liveSchema)
    }

    private var activeAddFormMode: CollectionAddFormMode {
        presentationStore.addFormMode(for: liveSchema.id)
    }

    public var body: some View {
        VStack(spacing: 0) {
            settingsHeaderBar

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    identityPreviewCard
                    themeColorDropdownCard
                    thumbnailFieldCard
                    compactSecondaryFieldDropdownCard
                    addRecordFormStyleDropdownCard
                    iconPickerCard
                    collectionPrivacyCard
                    schemaFieldsSummaryCard
                }
                .padding(18)
            }
            .background(ArcaTheme.canvasBackground(for: colorScheme))
        }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .disabled(metadataSaving)
        .interactiveDismissDisabled(metadataSaving || nameNeedsSave)
        .onAppear {
            guard !didLoadIconState else { return }
            didLoadIconState = true
            syncInitialState()
        }
        .onChange(of: liveSchema.name) { oldName, newName in
            if trimmedName == oldName { draftName = newName }
        }
        .alert(isPresented: Binding(get: { metadataError != nil }, set: { if !$0 { metadataError = nil } })) {
            Alert(
                title: Text(metadataError ?? ""),
                dismissButton: .default(Text(viewModel.language.localized("common.ok")))
            )
        }
        .modifier(CollectionAddRecordPresenter(viewModel: viewModel, schema: $activeTestAddRecordSchema))
        .sheet(isPresented: $showingFieldEditor) {
            FieldEditorSheetView(viewModel: viewModel, collectionId: liveSchema.id)
                #if os(macOS)
                .frame(minWidth: 370, idealWidth: 400, minHeight: 580, idealHeight: 680)
                #endif
        }
        .sheet(isPresented: $showingPrivacyConsent) {
            SensitivePrivacyConsentView(viewModel: viewModel, collectionId: liveSchema.id, fieldId: nil)
        }
        .fileImporter(
            isPresented: $showingIconFileImporter,
            allowedContentTypes: [.image]
        ) { result in
            switch result {
            case .success(let url):
                do {
                    try presentationStore.saveCustomIconImage(fromFileURL: url, for: liveSchema.id)
                    iconUploadError = nil
                } catch {
                    iconUploadError = viewModel.language.localized((error as? CollectionIconImageError)?.errorDescription ?? "Could not load the selected photo.")
                }
            case .failure(let error):
                if (error as? CocoaError)?.code != .userCancelled {
                    iconUploadError = viewModel.language.localized("Could not load the selected photo.")
                }
            }
        }
        #if os(iOS)
        .onChange(of: selectedPhotoPickerItem) { _, newItem in
            guard let newItem else { return }
            Task { @MainActor in
                do {
                    let data = try await newItem.loadTransferable(type: Data.self)
                    guard selectedPhotoPickerItem == newItem else { return }
                    guard let data else { throw CollectionIconImageError.invalidImageData }
                    try presentationStore.saveCustomIconImageData(data, for: schema.id)
                    iconUploadError = nil
                } catch {
                    guard selectedPhotoPickerItem == newItem else { return }
                    iconUploadError = viewModel.language.localized((error as? CollectionIconImageError)?.errorDescription ?? "Could not load the selected photo.")
                }
                selectedPhotoPickerItem = nil
            }
        }
        #endif
    }

    private func syncInitialState() {
        let current = liveSchema
        draftName = current.name
        let pref = presentationStore.preferences(for: current.id).iconPreference
        if let pref {
            iconTab = pref.tab
            if case .monogram(let letters) = pref {
                customMonogram = letters
            } else {
                customMonogram = CollectionPresentationStore.computeInitials(for: current.name)
            }
        } else {
            // Default library icon for existing schema
            iconTab = .library
            customMonogram = CollectionPresentationStore.computeInitials(for: current.name)
        }
        let targetSymbol: String = {
            if case .library(let sym) = pref, !sym.isEmpty { return sym }
            return current.iconName
        }()
        if let match = CollectionDesignCatalog.locateCategoryAndSubcategory(forSymbol: targetSymbol) {
            selectedLibraryCategory = match.category
            selectedLibrarySubcategory = match.subcategory
        }
    }

    private func commitNameIfNeeded(dismissAfterSaving: Bool = false) {
        guard !metadataSaving else { return }
        let name = trimmedName
        guard !name.isEmpty else {
            metadataError = viewModel.language.localized("Enter a collection name.")
            return
        }
        guard nameNeedsSave else {
            if dismissAfterSaving { dismiss() }
            return
        }
        saveMetadata(name: name) {
            draftName = name
            if dismissAfterSaving { dismiss() }
        }
    }

    private func saveMetadata(
        name: String? = nil, icon: String? = nil, color: String? = nil,
        onSaved: @escaping () -> Void = {}
    ) {
        guard !metadataSaving else { return }
        metadataSaving = true
        Task {
            defer { metadataSaving = false }
            do {
                try await viewModel.updateCollectionMetadata(
                    collectionId: schema.id, name: name, iconName: icon, colorHex: color
                )
                onSaved()
            } catch {
                metadataError = viewModel.language.localized("Could not save collection settings. Try again.")
            }
        }
    }

    private func closeAllDropdowns() {
        colColorDropdownOpen = false
        compactFieldDropdownOpen = false
        addFormModeDropdownOpen = false
    }

    // MARK: - Top Header Bar

    private var settingsHeaderBar: some View {
        let title = Text(viewModel.language.localized("Collection Settings"))
            .arcaFont(.subheadline, weight: .bold)
            .accessibilityAddTraits(.isHeader)

        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        settingsBackButton
                        Spacer()
                        settingsDoneButton
                    }
                    title
                }
            } else {
                HStack(spacing: 10) {
                    settingsBackButton
                    Spacer()
                    title
                    Spacer()
                    settingsDoneButton
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(ArcaTheme.cardBackground(for: colorScheme).opacity(0.96))
        .overlay(alignment: .bottom) { Divider().opacity(0.45) }
    }

    private var settingsBackButton: some View {
        Button {
            commitNameIfNeeded(dismissAfterSaving: true)
        } label: {
            Image(systemName: "chevron.backward")
                .font(.footnote.weight(.bold))
                .foregroundStyle(ink)
                .frame(minWidth: 44, minHeight: 44)
                .background(Capsule().fill(tint.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(viewModel.language.localized("Back"))
    }

    private var settingsDoneButton: some View {
        Button {
            commitNameIfNeeded(dismissAfterSaving: true)
        } label: {
            Text(viewModel.language.localized("Done"))
                .arcaFont(.subheadline, weight: .bold)
                .foregroundStyle(palette.onFill)
                .padding(.horizontal, 15)
                .padding(.vertical, 8)
                .frame(minWidth: 44, minHeight: 44)
                .background(Capsule().fill(tint))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Live Identity Card

    private var identityPreviewCard: some View {
        let recordCount = viewModel.recordCount(for: liveSchema.id)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                CollectionBadgeView(schema: liveSchema, size: 52, presentationStore: presentationStore)

                VStack(alignment: .leading, spacing: 6) {
                    TextField(viewModel.language.localized("Collection Name"), text: $draftName)
                        .textFieldStyle(.plain)
                        .arcaFont(.headline, weight: .bold)
                        .submitLabel(.done)
                        .onSubmit {
                            commitNameIfNeeded()
                        }
                        .accessibilityLabel(viewModel.language.localized("Collection Name"))

                    Text(viewModel.language.format("count.records", recordCount) + " • " + viewModel.language.format("count.fields", liveSchema.activeFields.count))
                        .arcaFont(.caption, weight: .medium)
                        .foregroundStyle(.secondary)
                }

            }
            if nameNeedsSave {
                Button {
                    commitNameIfNeeded()
                } label: {
                    Text(viewModel.language.localized("Save"))
                        .arcaFont(.caption, weight: .bold)
                        .foregroundStyle(palette.onFill)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .frame(minWidth: 44, minHeight: 44)
                        .background(Capsule().fill(tint))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(ArcaTheme.cardBackground(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(ArcaTheme.cardBorder(for: colorScheme), lineWidth: 1)
        )
    }

    // MARK: - 1. Collection Theme Color Dropdown

    private var themeColorDropdownCard: some View {
        let activeOpt = activeColorOption
        return VStack(alignment: .leading, spacing: 10) {
            Text(viewModel.language.localized("Collection Theme Color"))
                .arcaFont(.footnote, weight: .bold)
                .accessibilityAddTraits(.isHeader)

            Button {
                let next = !colColorDropdownOpen
                closeAllDropdowns()
                colColorDropdownOpen = next
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(tint)
                            .frame(width: 26, height: 26)
                        Circle()
                            .fill(Color.white.opacity(0.65))
                            .frame(width: 8, height: 8)
                    }
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.language.localized(activeOpt.nameKey))
                            .arcaFont(.subheadline, weight: .bold)
                            .foregroundStyle(.primary)
                        Text(viewModel.language.localized(activeOpt.tagKey) + " · " + activeOpt.hex)
                            .arcaFont(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: colColorDropdownOpen ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(ArcaTheme.cardBackground(for: colorScheme)))
                }
                .padding(12)
                .frame(minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(ArcaTheme.subtleFieldBackground(for: colorScheme))
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.language.localized("Collection Theme Color"))
            .accessibilityValue(viewModel.language.localized(activeOpt.nameKey))

            if colColorDropdownOpen {
                VStack(spacing: 0) {
                    ForEach(Array(CollectionDesignCatalog.collectionColors.enumerated()), id: \.element.id) { index, item in
                        let isSelected = item.hex.caseInsensitiveCompare(liveSchema.colorHex) == .orderedSame
                        let itemColor = ArcaTheme.color(fromHex: item.hex)

                        Button {
                            saveMetadata(color: item.hex) { colColorDropdownOpen = false }
                        } label: {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(itemColor)
                                    .frame(width: 20, height: 20)
                                    .overlay(Circle().strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
                                    .accessibilityHidden(true)

                                Text(viewModel.language.localized(item.nameKey))
                                    .arcaFont(.footnote, weight: .bold)
                                    .foregroundStyle(.primary)

                                Spacer(minLength: 4)

                                if !dynamicTypeSize.isAccessibilitySize {
                                    Text(viewModel.language.localized("Sample"))
                                        .arcaFont(.caption2, weight: .semibold)
                                        .foregroundStyle(CollectionColorPalette(hex: item.hex).onFill)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Capsule().fill(itemColor))
                                        .accessibilityHidden(true)
                                }

                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.black))
                                        .foregroundStyle(CollectionColorPalette(hex: item.hex).ink(for: colorScheme))
                                        .frame(width: 16)
                                } else {
                                    Color.clear.frame(width: 16, height: 16)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(minHeight: 44)
                            .background(isSelected ? ArcaTheme.subtleFieldBackground(for: colorScheme) : Color.clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(viewModel.language.localized(item.nameKey) + ", " + viewModel.language.localized(item.tagKey))
                        .accessibilityAddTraits(isSelected ? .isSelected : [])

                        if index < CollectionDesignCatalog.collectionColors.count - 1 {
                            Divider().opacity(0.45)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(ArcaTheme.cardBackground(for: colorScheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(ArcaTheme.cardBorder(for: colorScheme), lineWidth: 1)
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(ArcaTheme.cardBackground(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(ArcaTheme.cardBorder(for: colorScheme), lineWidth: 1)
        )
    }

    private var thumbnailFieldCard: some View {
        Group {
            if !liveSchema.imageFields.isEmpty {
                ArcaSectionCard(title: viewModel.language.localized("Record thumbnail"), icon: "photo") {
                    Picker(viewModel.language.localized("Image field"), selection: Binding<UUID?>(
                        get: { presentationStore.preferences(for: liveSchema.id).thumbnailFieldId },
                        set: { presentationStore.setThumbnailField($0, for: liveSchema.id) }
                    )) {
                        Text(viewModel.language.localized("Automatic (one image field)")).tag(UUID?.none)
                        ForEach(liveSchema.imageFields) { field in
                            Text(field.label).tag(Optional(field.id))
                        }
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("collection.thumbnailField")
                    Text(viewModel.language.localized("With several image fields, choose which one appears on record cards. This view setting is saved on this device."))
                        .arcaFont(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - 2. Compact Secondary Field Dropdown (Strictly Inside Settings)

    private var compactSecondaryFieldDropdownCard: some View {
        let primaryLabel = liveSchema.primaryTitleField?.label ?? viewModel.language.localized("Title")
        let selectedField = activeCompactField

        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.language.localized("Field Shown Beside Title (Compact View)"))
                    .arcaFont(.footnote, weight: .bold)
                    .accessibilityAddTraits(.isHeader)
                Text(viewModel.language.localized("Select which field appears next to the title when using Compact View."))
                    .arcaFont(.caption)
                    .foregroundStyle(.secondary)
            }

            if let selectedField {
                Button {
                    let next = !compactFieldDropdownOpen
                    closeAllDropdowns()
                    compactFieldDropdownOpen = next
                } label: {
                    HStack(spacing: 12) {
                        Text(ArcaStrings.text("field.type." + selectedField.type.rawValue, language: viewModel.language).uppercased(with: viewModel.language.locale))
                            .arcaFont(.caption2, weight: .bold)
                            .foregroundStyle(palette.onFill)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(selectedField.label)
                                .arcaFont(.subheadline, weight: .bold)
                                .foregroundStyle(.primary)
                            Text(viewModel.language.format("Shown beside %@", primaryLabel))
                                .arcaFont(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: compactFieldDropdownOpen ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(ArcaTheme.cardBackground(for: colorScheme)))
                    }
                    .padding(12)
                    .frame(minHeight: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(ArcaTheme.subtleFieldBackground(for: colorScheme))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(viewModel.language.localized("Field Shown Beside Title (Compact View)"))
                .accessibilityValue(selectedField.label)

                if compactFieldDropdownOpen {
                    VStack(spacing: 0) {
                        ForEach(Array(secondaryFieldOptions.enumerated()), id: \.element.id) { index, field in
                            let isSelected = field.id == selectedField.id
                            Button {
                                presentationStore.setCompactSecondaryField(field.id, for: liveSchema.id)
                                compactFieldDropdownOpen = false
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: field.type.iconName)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(ink)
                                        .frame(width: 20)

                                    Text(field.label)
                                        .arcaFont(.footnote, weight: .bold)
                                        .foregroundStyle(.primary)

                                    Text(ArcaStrings.text("field.type." + field.type.rawValue, language: viewModel.language))
                                        .arcaFont(.caption2, weight: .medium)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .fill(ArcaTheme.subtleFieldBackground(for: colorScheme))
                                        )

                                    Spacer()

                                    if isSelected {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.black))
                                            .foregroundStyle(ink)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .frame(minHeight: 44)
                                .background(isSelected ? ArcaTheme.subtleFieldBackground(for: colorScheme) : Color.clear)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(field.label)
                            .accessibilityAddTraits(isSelected ? .isSelected : [])

                            if index < secondaryFieldOptions.count - 1 {
                                Divider().opacity(0.45)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(ArcaTheme.cardBackground(for: colorScheme))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(ArcaTheme.cardBorder(for: colorScheme), lineWidth: 1)
                    )
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(ArcaTheme.cardBackground(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(ArcaTheme.cardBorder(for: colorScheme), lineWidth: 1)
        )
    }

    // MARK: - 3. Add Record Form Style Dropdown (Popup Card vs. Complete New Screen)

    private var addRecordFormStyleDropdownCard: some View {
        let currentMode = activeAddFormMode
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.language.localized("“Add Record” Form Style"))
                        .arcaFont(.footnote, weight: .bold)
                        .accessibilityAddTraits(.isHeader)
                    Text(viewModel.language.localized("Open as a popup card or a complete new screen."))
                        .arcaFont(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    activeTestAddRecordSchema = liveSchema
                } label: {
                    HStack(spacing: 4) {
                        Text(viewModel.language.localized("Test"))
                        Image(systemName: "arrow.forward")
                    }
                    .arcaFont(.caption, weight: .bold)
                    .foregroundStyle(palette.onFill)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint))
                }
                .buttonStyle(.plain)
            }

            Button {
                let next = !addFormModeDropdownOpen
                closeAllDropdowns()
                addFormModeDropdownOpen = next
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: currentMode.iconName)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(palette.onFill)
                        .frame(width: 30, height: 30)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.language.localized(currentMode.titleKey))
                            .arcaFont(.subheadline, weight: .bold)
                            .foregroundStyle(.primary)
                        Text(viewModel.language.localized(currentMode.subtitleKey))
                            .arcaFont(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: addFormModeDropdownOpen ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(ArcaTheme.cardBackground(for: colorScheme)))
                }
                .padding(12)
                .frame(minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(ArcaTheme.subtleFieldBackground(for: colorScheme))
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.language.localized("“Add Record” Form Style"))
            .accessibilityValue(viewModel.language.localized(currentMode.titleKey))

            if addFormModeDropdownOpen {
                VStack(spacing: 0) {
                    ForEach(Array(CollectionAddFormMode.allCases.enumerated()), id: \.element.id) { index, mode in
                        let isSelected = mode == currentMode
                        Button {
                            presentationStore.setAddFormMode(mode, for: liveSchema.id)
                            addFormModeDropdownOpen = false
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: mode.iconName)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(palette.onFill)
                                    .frame(width: 26, height: 26)
                                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint))
                                    .accessibilityHidden(true)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(viewModel.language.localized(mode.titleKey))
                                        .arcaFont(.footnote, weight: .bold)
                                        .foregroundStyle(.primary)
                                    Text(viewModel.language.localized(mode.subtitleKey))
                                        .arcaFont(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.black))
                                        .foregroundStyle(ink)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(minHeight: 44)
                            .background(isSelected ? ArcaTheme.subtleFieldBackground(for: colorScheme) : Color.clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(viewModel.language.localized(mode.titleKey))
                        .accessibilityAddTraits(isSelected ? .isSelected : [])

                        if index < CollectionAddFormMode.allCases.count - 1 {
                            Divider().opacity(0.45)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(ArcaTheme.cardBackground(for: colorScheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(ArcaTheme.cardBorder(for: colorScheme), lineWidth: 1)
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(ArcaTheme.cardBackground(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(ArcaTheme.cardBorder(for: colorScheme), lineWidth: 1)
        )
    }

    // MARK: - 4. 4-Category Collection Icon Picker

    private var iconPickerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.language.localized("Collection Icon"))
                .arcaFont(.footnote, weight: .bold)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: Array(
                repeating: GridItem(.flexible(), spacing: 4),
                count: dynamicTypeSize.isAccessibilitySize ? 2 : 4
            ), spacing: 4) {
                ForEach(CollectionIconTab.allCases) { tab in
                    let isSelected = iconTab == tab
                    Button {
                        iconTab = tab
                    } label: {
                        Text(viewModel.language.localized(tab.titleKey))
                            .arcaFont(.caption, weight: .semibold)
                            .foregroundStyle(isSelected ? palette.onFill : .secondary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isSelected ? tint : Color.clear)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(ArcaTheme.subtleFieldBackground(for: colorScheme))
            )

            switch iconTab {
            case .library:
                libraryIconTabContent
            case .emoji:
                emojiIconTabContent
            case .upload:
                uploadIconTabContent
            case .letters:
                lettersIconTabContent
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(ArcaTheme.cardBackground(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(ArcaTheme.cardBorder(for: colorScheme), lineWidth: 1)
        )
    }

    private var libraryIconTabContent: some View {
        let activeCategory = CollectionDesignCatalog.iconCategories.first(where: { $0.titleKey == selectedLibraryCategory })
            ?? CollectionDesignCatalog.iconCategories[0]
        let activeSubcategory = activeCategory.subcategories.first(where: { $0.titleKey == selectedLibrarySubcategory })
            ?? activeCategory.subcategories[0]
        let currentPref = presentationStore.preferences(for: liveSchema.id).iconPreference
        let activeSymbol: String? = {
            if case .library(let sym) = currentPref { return sym }
            if currentPref == nil { return liveSchema.iconName }
            return nil
        }()

        return VStack(alignment: .leading, spacing: 10) {
            // Category Strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(CollectionDesignCatalog.iconCategories) { cat in
                        let isSelected = cat.titleKey == activeCategory.titleKey
                        Button {
                            selectedLibraryCategory = cat.titleKey
                            if let firstSub = cat.subcategories.first {
                                selectedLibrarySubcategory = firstSub.titleKey
                            }
                        } label: {
                            Text(viewModel.language.localized(cat.titleKey))
                                .arcaFont(.caption, weight: .semibold)
                                .foregroundStyle(isSelected ? palette.onFill : .primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(minHeight: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(isSelected ? tint : ArcaTheme.subtleFieldBackground(for: colorScheme))
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }

            // Subcategory Strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(activeCategory.subcategories) { sub in
                        let isSelected = sub.titleKey == activeSubcategory.titleKey
                        Button {
                            selectedLibrarySubcategory = sub.titleKey
                        } label: {
                            Text(viewModel.language.localized(sub.titleKey))
                                .arcaFont(.caption, weight: .medium)
                                .foregroundStyle(isSelected ? palette.onFill : .primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .frame(minHeight: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(isSelected ? tint : ArcaTheme.subtleFieldBackground(for: colorScheme))
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }

            // Icons Grid
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
                ForEach(activeSubcategory.icons) { item in
                    let isSelected = activeSymbol == item.symbol
                    Button {
                        selectLibraryIcon(item.symbol)
                    } label: {
                        Image(systemName: item.symbol)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(isSelected ? palette.onFill : .primary)
                            .frame(minWidth: 44, minHeight: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(isSelected ? tint : ArcaTheme.subtleFieldBackground(for: colorScheme))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(isSelected ? tint : Color.clear, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(viewModel.language.localized(item.labelKey))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    private func selectLibraryIcon(_ symbol: String) {
        let collectionId = liveSchema.id
        saveMetadata(icon: symbol) {
            presentationStore.setIcon(.library(symbol: symbol), for: collectionId)
        }
    }

    private var emojiIconTabContent: some View {
        let currentPref = presentationStore.preferences(for: liveSchema.id).iconPreference
        let activeEmoji: String? = {
            if case .emoji(let em) = currentPref { return em }
            return nil
        }()

        return VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
                ForEach(CollectionDesignCatalog.emojiOptions, id: \.self) { emoji in
                    let isSelected = activeEmoji == emoji
                    Button {
                        presentationStore.setIcon(.emoji(emoji), for: liveSchema.id)
                    } label: {
                        Text(verbatim: emoji)
                            .arcaFont(.title3)
                            .frame(minWidth: 44, minHeight: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(isSelected ? tint.opacity(0.22) : ArcaTheme.subtleFieldBackground(for: colorScheme))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(isSelected ? tint : Color.clear, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(emoji)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }

            HStack(spacing: 8) {
                ArcaStyledTextField(
                    viewModel.language.localized("Or type any emoji…"),
                    text: $customEmojiInput
                )
                Button {
                    let trimmed = customEmojiInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard let first = trimmed.first else { return }
                    presentationStore.setIcon(.emoji(String(first)), for: liveSchema.id)
                    customEmojiInput = ""
                } label: {
                    Text(viewModel.language.localized("Use"))
                        .arcaFont(.caption, weight: .bold)
                        .foregroundStyle(palette.onFill)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint))
                }
                .buttonStyle(.plain)
                .disabled(customEmojiInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var uploadIconTabContent: some View {
        let hasCustomImage: Bool = {
            if case .customImage = presentationStore.preferences(for: liveSchema.id).iconPreference {
                return true
            }
            return false
        }()

        return VStack(spacing: 10) {
            #if os(iOS)
            PhotosPicker(selection: $selectedPhotoPickerItem, matching: .images) {
                uploadBannerContent
            }
            .buttonStyle(.plain)
            #else
            Button {
                showingIconFileImporter = true
            } label: {
                uploadBannerContent
            }
            .buttonStyle(.plain)
            #endif

            HStack(spacing: 8) {
                Button {
                    showingIconFileImporter = true
                } label: {
                    Label(viewModel.language.localized("Choose Image from Files"), systemImage: "folder.fill")
                        .arcaFont(.caption, weight: .semibold)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(ArcaSecondaryButtonStyle(tint: ink, isFullWidth: true))

                if hasCustomImage {
                    Button {
                        presentationStore.setIcon(.library(symbol: liveSchema.iconName), for: liveSchema.id)
                    } label: {
                        Text(viewModel.language.localized("Reset Icon"))
                            .arcaFont(.caption, weight: .semibold)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(ArcaSecondaryButtonStyle(tint: .secondary))
                }
            }

            if let iconUploadError {
                Text(iconUploadError)
                    .arcaFont(.caption)
                    .foregroundStyle(ArcaTheme.dangerRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var uploadBannerContent: some View {
        VStack(spacing: 6) {
            Image(systemName: "photo.badge.plus")
                .font(.title3.weight(.semibold))
                .foregroundStyle(ink)
            Text(viewModel.language.localized("Upload Custom Photo / Icon"))
                .arcaFont(.footnote, weight: .bold)
                .foregroundStyle(.primary)
            Text(viewModel.language.localized("Choose from Photos or Files"))
                .arcaFont(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(ArcaTheme.subtleFieldBackground(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundStyle(tint.opacity(0.45))
        )
    }

    private var lettersIconTabContent: some View {
        let activeName = draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? liveSchema.name : draftName
        let suggested = CollectionPresentationStore.computeInitials(for: activeName)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(viewModel.language.format("Suggested from “%@”: %@", activeName, suggested))
                    .arcaFont(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    customMonogram = suggested
                    presentationStore.setIcon(.monogram(suggested), for: liveSchema.id)
                } label: {
                    Text(viewModel.language.format("Use “%@”", suggested))
                        .arcaFont(.caption, weight: .bold)
                        .foregroundStyle(palette.onFill)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .frame(minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                TextField(
                    "W",
                    text: Binding(
                        get: { customMonogram },
                        set: { newValue in
                            let clean = CollectionPresentationStore.sanitizeMonogram(newValue, fallbackName: activeName)
                            customMonogram = String(newValue.prefix(3)).uppercased()
                            presentationStore.setIcon(.monogram(clean), for: liveSchema.id)
                        }
                    )
                )
                .textFieldStyle(.plain)
                .arcaFont(.headline, weight: .black)
                .multilineTextAlignment(.center)
                .frame(width: 78)
                .frame(minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(ArcaTheme.subtleFieldBackground(for: colorScheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(ArcaTheme.cardBorder(for: colorScheme), lineWidth: 1)
                )
                .accessibilityLabel(viewModel.language.localized("Monogram Letters"))

                Text(viewModel.language.localized("Type 1–3 letters (e.g. W, HI, VM)"))
                    .arcaFont(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 5. Collection Privacy & Sensitive Data Controls Card

    private var collectionPrivacyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(ArcaTheme.plumSensitive)
                Text(viewModel.language.localized("Collection privacy"))
                    .arcaFont(.footnote, weight: .bold)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }

            Text(
                viewModel.language.localized(
                    liveSchema.privacy == .localOnly
                        ? "Sensitive · kept on this device"
                        : liveSchema.privacy == .syncWithConsent
                            ? "Sensitive · cloud sync consented"
                            : "Ordinary collection"
                )
            )
            .arcaFont(.caption)
            .foregroundStyle(.secondary)

            Button {
                let colId = liveSchema.id
                Task {
                    do {
                        try await viewModel.keepSensitiveDataOnDevice(collectionId: colId)
                        privacyError = nil
                        showingPrivacyConsent = true
                    } catch {
                        privacyError = error.localizedDescription
                    }
                }
            } label: {
                Label(
                    viewModel.language.localized("Mark collection sensitive / change consent"),
                    systemImage: "lock.shield"
                )
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(ArcaSecondaryButtonStyle(tint: ArcaTheme.plumSensitive, isFullWidth: true))

            if viewModel.pendingPrivacyDeletionCollectionIds.contains(liveSchema.id) {
                Text(viewModel.language.localized("Remote deletion pending. Uploads for this collection remain paused until confirmed. Offline devices may retain earlier copies."))
                    .arcaFont(.caption)
                    .foregroundStyle(.orange)
            }

            if let privacyError {
                Text(privacyError)
                    .arcaFont(.caption)
                    .foregroundStyle(ArcaTheme.dangerRed)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(ArcaTheme.cardBackground(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(ArcaTheme.cardBorder(for: colorScheme), lineWidth: 1)
        )
    }

    // MARK: - 6. Schema Fields Summary Card

    private var schemaFieldsSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(viewModel.language.format("Fields (%d)", liveSchema.activeFields.count))
                    .arcaFont(.footnote, weight: .bold)
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                Button {
                    showingFieldEditor = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text(viewModel.language.localized("Add Field"))
                    }
                    .arcaFont(.caption, weight: .bold)
                    .foregroundStyle(ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(minHeight: 44)
                    .background(Capsule().fill(tint.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 0) {
                ForEach(Array(liveSchema.activeFields.enumerated()), id: \.element.id) { index, field in
                    Button {
                        showingFieldEditor = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: field.type.iconName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ink)
                                .frame(width: 22)

                            Text(field.label)
                                .arcaFont(.footnote, weight: .semibold)
                                .foregroundStyle(.primary)

                            if field.isRequired {
                                Text(viewModel.language.localized("Required"))
                                    .arcaFont(.caption2, weight: .semibold)
                                    .foregroundStyle(ink)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(tint.opacity(0.12)))
                            }

                            if field.privacy != nil {
                                Image(systemName: "hand.raised.fill")
                                    .font(.caption2)
                                    .foregroundStyle(ArcaTheme.plumSensitive)
                            }

                            Spacer()

                            Text(ArcaStrings.text("field.type." + field.type.rawValue, language: viewModel.language))
                                .arcaFont(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(ArcaTheme.subtleFieldBackground(for: colorScheme))
                                )
                        }
                        .padding(.vertical, 10)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < liveSchema.activeFields.count - 1 {
                        Divider().opacity(0.45)
                    }
                }
            }

            Button {
                showingFieldEditor = true
            } label: {
                Label(viewModel.language.localized("Manage Fields"), systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(ArcaSecondaryButtonStyle(tint: ink, isFullWidth: true))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(ArcaTheme.cardBackground(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(ArcaTheme.cardBorder(for: colorScheme), lineWidth: 1)
        )
    }
}

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

    public init(viewModel: ArcaAppViewModel, collectionId: UUID) {
        self.viewModel = viewModel
        self.collectionId = collectionId
    }

    private var currentSchema: CollectionSchema? {
        viewModel.schema(for: collectionId)
    }

    public var body: some View {
        VStack(spacing: 0) {
            ArcaSheetHeaderBar(
                title: viewModel.language.localized("Manage Fields"),
                subtitle: currentSchema.map { "\($0.name) • Schema v\($0.schemaVersion)" },
                leadingLabel: "Done",
                leadingAction: { dismiss() }
            )

            if let schema = currentSchema {
                let tint = ArcaTheme.color(fromHex: schema.colorHex)
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        ArcaSectionCard(title: viewModel.language.localized("Collection privacy"), icon: "hand.raised.fill", iconTint: ArcaTheme.plumSensitive) {
                            Text(viewModel.language.localized(schema.privacy == .localOnly ? "Sensitive · kept on this device" : schema.privacy == .syncWithConsent ? "Sensitive · cloud sync consented" : "Ordinary collection"))
                            Button(viewModel.language.localized("Mark collection sensitive / change consent")) {
                                Task {
                                    do {
                                        try await viewModel.keepSensitiveDataOnDevice(collectionId: schema.id)
                                        privacyTargetFieldId = nil; showingPrivacyConsent = true
                                    } catch { privacyError = error.localizedDescription }
                                }
                            }
                            if viewModel.pendingPrivacyDeletionCollectionIds.contains(schema.id) {
                                Text(viewModel.language.localized("Remote deletion pending. Uploads for this collection remain paused until confirmed. Offline devices may retain earlier copies.")).arcaFont(.footnote).foregroundStyle(.orange)
                            }
                            if let privacyError { Text(privacyError).foregroundStyle(.red) }
                        }
                        ArcaSectionCard(
                            title: viewModel.language.localized("Active Fields"),
                            subtitle: viewModel.language.localized("Reorder, rename labels without losing values, or preview safe type conversions."),
                            icon: "slider.horizontal.3",
                            iconTint: tint
                        ) {
                            VStack(spacing: 8) {
                                ForEach(Array(schema.activeFields.enumerated()), id: \.element.id) { index, field in
                                    HStack(spacing: 10) {
                                        Image(systemName: field.type.iconName)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(tint)
                                            .frame(width: 30, height: 30)
                                            .background(Circle().fill(tint.opacity(0.12)))

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(field.label)
                                                .arcaFont(.subheadline, weight: .bold)
                                            Text(ArcaStrings.text("field.type." + field.type.rawValue, language: viewModel.language) + (field.isRequired ? " • " + viewModel.language.localized("Required") : ""))
                                                .arcaFont(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        HStack(spacing: 4) {
                                            Button {
                                                Task { await viewModel.moveField(in: schema.id, fromIndex: index, direction: -1) }
                                            } label: {
                                                Image(systemName: "arrow.up")
                                                    .font(.caption.weight(.bold))
                                                    .frame(width: 26, height: 26)
                                                    .background(Circle().fill(Color.secondary.opacity(0.12)))
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityLabel(viewModel.language.format("Move %@ up", field.label))
                                            .disabled(index == 0)
                                            .opacity(index == 0 ? 0.35 : 1)

                                            Button {
                                                Task { await viewModel.moveField(in: schema.id, fromIndex: index, direction: 1) }
                                            } label: {
                                                Image(systemName: "arrow.down")
                                                    .font(.caption.weight(.bold))
                                                    .frame(width: 26, height: 26)
                                                    .background(Circle().fill(Color.secondary.opacity(0.12)))
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityLabel(viewModel.language.format("Move %@ down", field.label))
                                            .disabled(index == schema.activeFields.count - 1)
                                            .opacity(index == schema.activeFields.count - 1 ? 0.35 : 1)

                                            Menu {
                                                Button(viewModel.language.localized(field.privacy == nil ? "Mark Sensitive…" : "Sensitive Privacy / Consent…")) {
                                                    Task {
                                                        do {
                                                            try await viewModel.keepSensitiveDataOnDevice(collectionId: schema.id, fieldId: field.id)
                                                            privacyTargetFieldId = field.id; showingPrivacyConsent = true
                                                        } catch { privacyError = error.localizedDescription }
                                                    }
                                                }
                                                Button(viewModel.language.localized("Rename Label (Preserves Values)…")) {
                                                    renamingField = field
                                                    renameLabel = field.label
                                                }
                                                Button(viewModel.language.localized("Change Field Type (Dry-Run Preview)…")) {
                                                    convertingField = field
                                                    targetConversionType = field.type
                                                    conversionPreview = viewModel.previewFieldConversion(collectionId: schema.id, field: field, targetType: field.type)
                                                }
                                                Divider()
                                                Button(viewModel.language.localized("Archive Field (Retain Existing Values)")) {
                                                    Task {
                                                        await viewModel.removeField(in: schema.id, fieldId: field.id, policy: .archiveAndRetainValues)
                                                    }
                                                }
                                                Button(viewModel.language.localized("Permanently Purge Field & Values"), role: .destructive) {
                                                    Task {
                                                        await viewModel.removeField(in: schema.id, fieldId: field.id, policy: .permanentlyPurgeValues)
                                                    }
                                                }
                                            } label: {
                                                Image(systemName: "ellipsis.circle.fill")
                                                    .font(.title3)
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
                                title: viewModel.language.format("Rename “%@”", renamingField.label),
                                subtitle: viewModel.language.localized("Renaming a field only updates its display label. All existing record values stay bound to its stable UUID."),
                                icon: "pencil",
                                iconTint: tint
                            ) {
                                ArcaStyledTextField(viewModel.language.localized("New Display Label"), text: $renameLabel, icon: "tag")
                                HStack(spacing: 10) {
                                    Button(viewModel.language.localized("Cancel")) { self.renamingField = nil }
                                        .buttonStyle(ArcaSecondaryButtonStyle(tint: .secondary))
                                    Button(viewModel.language.localized("Save Label")) {
                                        Task {
                                            await viewModel.renameField(in: schema.id, fieldId: renamingField.id, newLabel: renameLabel)
                                            self.renamingField = nil
                                        }
                                    }
                                    .buttonStyle(ArcaPrimaryButtonStyle(tint: tint))
                                }
                            }
                        }

                        if let convertingField {
                            ArcaSectionCard(
                                title: viewModel.language.format("Convert Type for “%@”", convertingField.label),
                                subtitle: viewModel.language.localized("Arca runs a non-destructive dry-run preview across all existing records before allowing a type change."),
                                icon: "arrow.triangle.swap",
                                iconTint: tint
                            ) {
                                HStack {
                                    Text(viewModel.language.localized("Target Type"))
                                        .arcaFont(.footnote, weight: .semibold)
                                    Spacer()
                                    Picker(viewModel.language.localized("Target Type"), selection: $targetConversionType) {
                                        ForEach(FieldType.allCases, id: \.self) { t in
                                            Text(ArcaStrings.text("field.type." + t.rawValue, language: viewModel.language)).tag(t)
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
                                                .arcaFont(.footnote, weight: .semibold)
                                        }
                                        ForEach(preview.sampleFailureDescriptions, id: \.self) { desc in
                                            Text("• \(desc)")
                                                .arcaFont(.caption)
                                                .foregroundStyle(ArcaTheme.dangerRed)
                                        }
                                    }
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(ArcaTheme.subtleFieldBackground(for: colorScheme)))
                                }

                                if let conversionError {
                                    Text(conversionError)
                                        .arcaFont(.caption)
                                        .foregroundStyle(ArcaTheme.dangerRed)
                                }

                                HStack(spacing: 10) {
                                    Button(viewModel.language.localized("Cancel")) {
                                        self.convertingField = nil
                                        self.conversionPreview = nil
                                    }
                                    .buttonStyle(ArcaSecondaryButtonStyle(tint: .secondary))

                                    Button(viewModel.language.localized("Apply Conversion")) {
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
                                    .buttonStyle(ArcaPrimaryButtonStyle(tint: tint))
                                    .disabled(!(conversionPreview?.isSafeToApplyWithoutLoss ?? false))
                                }
                            }
                        }

                        if !schema.archivedFields.isEmpty {
                            ArcaSectionCard(
                                title: viewModel.language.localized("Archived Fields (Recoverable)"),
                                subtitle: viewModel.language.localized("Historical values remain stored and can be restored to active forms at any time."),
                                icon: "archivebox.fill",
                                iconTint: ArcaTheme.warmAmber
                            ) {
                                ForEach(schema.archivedFields) { archived in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(archived.label)
                                                .arcaFont(.subheadline, weight: .semibold)
                                            Text(viewModel.language.localized("Archived • Values preserved"))
                                                .arcaFont(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        ArcaPillActionButton(viewModel.language.localized("Restore"), icon: "arrow.uturn.backward", tint: tint) {
                                            Task { await viewModel.restoreArchivedField(in: schema.id, fieldId: archived.id) }
                                        }
                                    }
                                }
                            }
                        }

                        ArcaSectionCard(title: viewModel.language.localized("Add New Field"), icon: "plus.circle.fill", iconTint: tint) {
                            ArcaStyledTextField(viewModel.language.localized("Field Label"), text: $newFieldLabel, icon: "plus")
                            HStack {
                                Text(viewModel.language.localized("Field Type"))
                                    .arcaFont(.footnote, weight: .medium)
                                Spacer()
                                Picker(viewModel.language.localized("Field Type"), selection: $newFieldType) {
                                    ForEach(FieldType.allCases, id: \.self) { t in
                                        Text(ArcaStrings.text("field.type." + t.rawValue, language: viewModel.language)).tag(t)
                                    }
                                }
                                .labelsHidden()
                            }
                            Button(viewModel.language.localized("Add Field")) {
                                Task {
                                    await viewModel.addField(to: schema.id, label: newFieldLabel, type: newFieldType)
                                    newFieldLabel = ""
                                }
                            }
                            .buttonStyle(ArcaPrimaryButtonStyle(tint: tint))
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

// MARK: - Collection Field Filters

enum NumericComparisonOperator: String, CaseIterable, Sendable, Identifiable {
    case between, greaterThan, lessThan, equals

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .between: return "Between"
        case .greaterThan: return "Greater than"
        case .lessThan: return "Less than"
        case .equals: return "filter.text.equals"
        }
    }

    func matches<Value: Comparable>(_ actual: Value, first: Value, second: Value?) -> Bool {
        switch self {
        case .between:
            guard let second else { return false }
            return (min(first, second)...max(first, second)).contains(actual)
        case .greaterThan: return actual > first
        case .lessThan: return actual < first
        case .equals: return actual == first
        }
    }
}

enum DateComparisonOperator: String, CaseIterable, Sendable, Identifiable {
    case between, after, before

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .between: return "Between Dates"
        case .after: return "After Date"
        case .before: return "Before Date"
        }
    }

    func matches(_ actual: CalendarDate, first: CalendarDate, second: CalendarDate) -> Bool {
        switch self {
        case .between: return (min(first, second)...max(first, second)).contains(actual)
        case .after: return actual > first
        case .before: return actual < first
        }
    }
}

enum TextComparisonOperator: String, CaseIterable, Sendable, Identifiable {
    case contains, equals, startsWith

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .contains: return "Contains"
        case .equals: return "filter.text.equals"
        case .startsWith: return "Starts with"
        }
    }

    func matches(_ actual: String, query: String, locale: Locale) -> Bool {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        switch self {
        case .contains: return actual.range(of: query, options: options, locale: locale) != nil
        case .equals: return actual.compare(query, options: options, locale: locale) == .orderedSame
        case .startsWith: return actual.range(of: query, options: options.union(.anchored), locale: locale) != nil
        }
    }
}

enum CollectionFieldPredicate: Equatable, Sendable {
    case number(NumericComparisonOperator, Double, Double?)
    case currency(NumericComparisonOperator, Decimal, Decimal?)
    case date(DateComparisonOperator, CalendarDate, CalendarDate)
    case text(TextComparisonOperator, String)
    case query(RecordFieldFilter)

    func matches(_ value: FieldValue?, locale: Locale) -> Bool {
        switch (self, value) {
        case let (.number(op, first, second), .number(actual)):
            return actual.isFinite && op.matches(actual, first: first, second: second)
        case let (.currency(op, first, second), .currency(actual)):
            return op.matches(actual.decimalValue, first: first, second: second)
        case let (.date(op, first, second), .date(actual)):
            return op.matches(actual, first: first, second: second)
        case let (.text(op, query), .shortText(actual)), let (.text(op, query), .longText(actual)):
            return op.matches(actual, query: query, locale: locale)
        case (.query, _):
            // Query predicates have already been applied by the view model.
            return true
        default:
            return false
        }
    }
}

private struct AppliedCollectionFieldFilter: Identifiable, Equatable, Sendable {
    var id: UUID { fieldId }
    let fieldId: UUID
    let fieldType: FieldType
    let summary: String
    let predicate: CollectionFieldPredicate
}

// MARK: - Screen 10: Collection Record List with Normal/Compact/Box Modes, Search, Sort & Field Filters

@available(macOS 14.0, iOS 17.0, *)
public struct CollectionRecordListView: View {
    @Bindable var viewModel: ArcaAppViewModel
    public let schema: CollectionSchema
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let presentationStore: CollectionPresentationStore = .shared

    @ViewState private var searchText = ""
    @ViewState private var sortCriterion: RecordSortCriterion = .updatedAtDescending
    @ViewState private var favoritesOnly = false
    @ViewState private var hasAttachmentsOnly = false
    @ViewState private var selectedOptionFilter: (fieldId: UUID, optionId: String)?

    @ViewState private var filterPanelOpen = false
    @ViewState private var appliedFieldFilters: [AppliedCollectionFieldFilter] = []
    @ViewState private var selectedDraftFilterFieldId: UUID?
    @ViewState private var draftNumericOp: NumericComparisonOperator = .between
    @ViewState private var draftNumberMinText: String = ""
    @ViewState private var draftNumberMaxText: String = ""
    @ViewState private var draftTextOp: TextComparisonOperator = .contains
    @ViewState private var draftText = ""
    @ViewState private var filterInputError = false
    @ViewState private var draftDateOp: DateComparisonOperator = .between
    @ViewState private var draftFromDate: Date = Date()
    @ViewState private var draftToDate: Date = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @ViewState private var draftBooleanValue: Bool = true
    @ViewState private var draftSelectOptionId: String = ""
    @ViewState private var draftMinimumRating: Int = 3

    @ViewState private var activeRecordSheetCollection: CollectionSchema?
    @ViewState private var showingCollectionSettings = false
    @ViewState private var showingExportSheet = false

    public init(viewModel: ArcaAppViewModel, schema: CollectionSchema) {
        self.viewModel = viewModel
        self.schema = schema
    }

    private var liveSchema: CollectionSchema {
        viewModel.schema(for: schema.id) ?? schema
    }

    private var palette: CollectionColorPalette { CollectionColorPalette(hex: liveSchema.colorHex) }
    private var tint: Color { palette.fill }
    private var ink: Color { palette.ink(for: colorScheme) }

    private var currentListMode: CollectionListMode {
        presentationStore.listMode(for: liveSchema.id)
    }

    private var filterableFields: [FieldDefinition] {
        liveSchema.activeFields.filter { field in
            switch field.type {
            case .shortText, .longText, .number, .currency, .date, .singleSelect, .multiSelect, .boolean, .rating:
                return true
            case .dateTime, .attachment, .image:
                return false
            }
        }
    }

    private var activeDraftFilterField: FieldDefinition? {
        if let id = selectedDraftFilterFieldId,
           let match = filterableFields.first(where: { $0.id == id }) {
            return match
        }
        return filterableFields.first
    }

    private var totalActiveFilterCount: Int {
        appliedFieldFilters.count + [favoritesOnly, hasAttachmentsOnly, selectedOptionFilter != nil].filter { $0 }.count
    }

    private func dropStaleFilters() {
        let fields = filterableFields
        appliedFieldFilters.removeAll { filter in
            guard let field = fields.first(where: { $0.id == filter.fieldId && $0.type == filter.fieldType }) else { return true }
            if case .query(.selectContains(_, let optionId)) = filter.predicate {
                return !field.options.contains { $0.id == optionId }
            }
            return false
        }
        if let selected = selectedOptionFilter,
           !fields.contains(where: { $0.id == selected.fieldId && $0.options.contains { $0.id == selected.optionId } }) {
            selectedOptionFilter = nil
        }
        if let selected = selectedDraftFilterFieldId, !fields.contains(where: { $0.id == selected }) {
            selectedDraftFilterFieldId = nil
            filterInputError = false
        }
    }

    private var filteredRecords: [RecordItem] {
        var filters: [RecordFieldFilter] = []
        if favoritesOnly { filters.append(.favoritesOnly) }
        if hasAttachmentsOnly { filters.append(.hasAttachments) }
        if let selected = selectedOptionFilter {
            filters.append(.selectContains(fieldId: selected.fieldId, optionId: selected.optionId))
        }
        for item in appliedFieldFilters {
            if case .query(let filter) = item.predicate, !filters.contains(filter) {
                filters.append(filter)
            }
        }
        let query = RecordQuery(
            searchText: searchText, collectionId: liveSchema.id, filters: filters, sort: sortCriterion
        )
        let locale = viewModel.language.locale
        return viewModel.queryRecords(query).filter { record in
            appliedFieldFilters.allSatisfy { $0.predicate.matches(record.values[$0.fieldId], locale: locale) }
        }
    }

    public var body: some View {
        let records = filteredRecords
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                topNavigationBar
                collectionHeroBanner(recordCount: records.count)
                ArcaSearchBar(
                    text: $searchText,
                    placeholder: viewModel.language.format("Filter %@…", liveSchema.name)
                )
                viewModeAndFilterTriggerBar
                quickSortAndFilterChipsStrip

                if filterPanelOpen {
                    fieldFilterDrawerCard
                }

                if !appliedFieldFilters.isEmpty {
                    activeAppliedFilterPillsStrip
                }

                recordsContentSection(records: records)
            }
            .padding(18)
        }
        .background(ArcaTheme.canvasBackground(for: colorScheme))
        .onChange(of: liveSchema.fields) { _, _ in dropStaleFilters() }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .modifier(CollectionAddRecordPresenter(viewModel: viewModel, schema: $activeRecordSheetCollection))
        .sheet(isPresented: $showingCollectionSettings) {
            CollectionSettingsView(viewModel: viewModel, schema: liveSchema)
            #if os(macOS)
                .frame(minWidth: 370, idealWidth: 410, minHeight: 600, idealHeight: 720)
            #endif
        }
        .sheet(isPresented: $showingExportSheet) {
            NavigationStack {
                BackupExportRestoreScreenView(viewModel: viewModel)
            }
            #if os(macOS)
            .frame(minWidth: 370, idealWidth: 400, minHeight: 540, idealHeight: 640)
            #endif
        }
    }

    // MARK: - Top Navigation Bar (Back · Export · ⚙️ Collection Settings)

    private var topNavigationBar: some View {
        let spaceName = viewModel.spaces.first(where: { $0.id == liveSchema.spaceId })?.name
            ?? viewModel.language.localized("Back")

        return HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.backward")
                        .font(.footnote.weight(.bold))
                    Text(spaceName)
                        .arcaFont(.subheadline, weight: .bold)
                        .lineLimit(1)
                }
                .foregroundStyle(ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minHeight: 44)
                .background(Capsule().fill(tint.opacity(0.12)))
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                showingExportSheet = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.caption.weight(.bold))
                    Text(viewModel.language.localized("Export"))
                        .arcaFont(.footnote, weight: .semibold)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(ArcaTheme.subtleFieldBackground(for: colorScheme))
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.language.localized("Export"))

            Button {
                showingCollectionSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(ArcaTheme.subtleFieldBackground(for: colorScheme))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.language.localized("Collection Settings"))
        }
    }

    // MARK: - Collection Hero Banner

    private func collectionHeroBanner(recordCount: Int) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            HStack(alignment: .top, spacing: 12) {
                CollectionBadgeView(schema: liveSchema, size: 46, presentationStore: presentationStore)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(liveSchema.name)
                            .arcaFont(.headline, weight: .heavy)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        if liveSchema.privacy != nil {
                            Image(systemName: "hand.raised.fill")
                                .font(.caption)
                                .accessibilityLabel(viewModel.language.localized("Collection privacy"))
                        }
                    }
                    Text(viewModel.language.format("count.records", recordCount))
                        .arcaFont(.caption, weight: .medium)
                }
                .foregroundStyle(palette.onFill)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                activeRecordSheetCollection = liveSchema
            } label: {
                Label(viewModel.language.localized("Add"), systemImage: "plus")
                    .arcaFont(.footnote, weight: .heavy)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 13).fill(.white))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.language.format("Add Record to %@", liveSchema.name))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20).fill(tint))
        .shadow(color: tint.opacity(0.24), radius: 8, x: 0, y: 4)
    }

    // MARK: - View Modes and Filter Trigger

    private var viewModeAndFilterTriggerBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                viewModeButtons.fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                filterTriggerButton.fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    viewModeButtons
                }
                filterTriggerButton
            }
        }
    }

    private var viewModeButtons: some View {
        HStack(spacing: 3) {
            ForEach(CollectionListMode.allCases) { mode in
                let isSelected = currentListMode == mode
                Button {
                    presentationStore.setListMode(mode, for: liveSchema.id)
                } label: {
                    Text(viewModel.language.localized(mode.titleKey))
                        .arcaFont(.caption, weight: .semibold)
                        .foregroundStyle(isSelected ? palette.onFill : .secondary)
                        .padding(.horizontal, 11)
                        .frame(minWidth: 44, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 9).fill(isSelected ? tint : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 12).fill(ArcaTheme.subtleFieldBackground(for: colorScheme)))
    }

    private var filterTriggerButton: some View {
        Button {
            filterPanelOpen.toggle()
        } label: {
            HStack(spacing: 6) {
                Label(viewModel.language.localized("Filter"), systemImage: "line.3.horizontal.decrease.circle")
                    .arcaFont(.caption, weight: .bold)
                if totalActiveFilterCount > 0 {
                    Text(totalActiveFilterCount, format: .number.locale(viewModel.language.locale))
                        .arcaFont(.caption2, weight: .bold)
                        .foregroundStyle(palette.onFill)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(tint))
                }
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 12)
            .frame(minWidth: 44, minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 12).fill(filterPanelOpen ? tint.opacity(0.14) : .clear))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(tint.opacity(0.42), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(filterPanelOpen ? .isSelected : [])
    }

    // MARK: - Preserved Quick Sort & Filter Chips Strip

    private var quickSortAndFilterChipsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Picker(viewModel.language.localized("Sort By"), selection: $sortCriterion) {
                        Text(viewModel.language.localized("Recently Updated")).tag(RecordSortCriterion.updatedAtDescending)
                        Text(viewModel.language.localized("Oldest Updated")).tag(RecordSortCriterion.updatedAtAscending)
                        Text(viewModel.language.localized("Title (A → Z)")).tag(RecordSortCriterion.titleAscending)
                        Text(viewModel.language.localized("Title (Z → A)")).tag(RecordSortCriterion.titleDescending)
                        ForEach(liveSchema.activeFields) { field in
                            Text("\(field.label) ↑").tag(RecordSortCriterion.fieldAscending(field.id))
                            Text("\(field.label) ↓").tag(RecordSortCriterion.fieldDescending(field.id))
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                        Text(viewModel.language.localized("Sort"))
                    }
                    .arcaFont(.footnote, weight: .semibold)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .frame(minHeight: 44)
                    .background(Capsule().fill(ArcaTheme.cardBackground(for: colorScheme)))
                    .overlay(Capsule().strokeBorder(ArcaTheme.cardBorder(for: colorScheme), lineWidth: 1))
                }
                .buttonStyle(.plain)

                filterChip(
                    title: viewModel.language.localized("Pinned"),
                    icon: favoritesOnly ? "pin.fill" : "pin",
                    isSelected: favoritesOnly,
                    tint: ArcaTheme.warmAmber
                ) {
                    favoritesOnly.toggle()
                }

                filterChip(
                    title: viewModel.language.localized("Files"),
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
    }

    // MARK: - Type-Aware Field Filter Drawer

    private var fieldFilterDrawerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.language.localized("Filter by Field"))
                .arcaFont(.footnote, weight: .bold)
                .foregroundStyle(ink)
                .accessibilityAddTraits(.isHeader)

            if filterableFields.isEmpty {
                Text(viewModel.language.localized("This collection has no fields to filter."))
                    .arcaFont(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(filterableFields) { field in
                            let isSelected = activeDraftFilterField?.id == field.id
                            Button {
                                selectDraftFilterField(field)
                            } label: {
                                Text(field.label)
                                    .arcaFont(.caption, weight: .semibold)
                                    .foregroundStyle(isSelected ? palette.onFill : .primary)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 7)
                                    .frame(minHeight: 44)
                                    .background(
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .fill(isSelected ? tint : ArcaTheme.subtleFieldBackground(for: colorScheme))
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                }

                if let draftField = activeDraftFilterField {
                    draftFilterInputControls(for: draftField)
                    if filterInputError {
                        Text(viewModel.language.localized("Enter a valid filter value."))
                            .arcaFont(.caption)
                            .foregroundStyle(.primary)
                    }

                    let layout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .trailing, spacing: 8))
                        : AnyLayout(HStackLayout(spacing: 8))
                    layout {
                        if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                        if totalActiveFilterCount > 0 {
                            Button {
                                appliedFieldFilters.removeAll()
                                favoritesOnly = false
                                hasAttachmentsOnly = false
                                selectedOptionFilter = nil
                                filterInputError = false
                            } label: {
                                Text(viewModel.language.localized("Reset"))
                                    .arcaFont(.caption, weight: .semibold)
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .frame(minHeight: 44)
                                    .background(
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .fill(ArcaTheme.subtleFieldBackground(for: colorScheme))
                                    )
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            applyCurrentDraftFilter(for: draftField)
                        } label: {
                            Text(viewModel.language.localized("Apply Filter"))
                                .arcaFont(.caption, weight: .bold)
                                .foregroundStyle(palette.onFill)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .frame(minHeight: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(tint)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(ArcaTheme.cardBackground(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(tint.opacity(0.32), lineWidth: 1)
        )
    }

    private func selectDraftFilterField(_ field: FieldDefinition) {
        guard activeDraftFilterField?.id != field.id else { return }
        selectedDraftFilterFieldId = field.id
        draftNumberMinText = ""
        draftNumberMaxText = ""
        draftText = ""
        draftSelectOptionId = field.options.first?.id ?? ""
        draftMinimumRating = min(3, ratingLimit(for: field))
        filterInputError = false
    }

    private func ratingLimit(for field: FieldDefinition) -> Int {
        max(1, min(10, field.validation.maxRating))
    }

    private func comparisonMenu<Option: Identifiable & Hashable>(
        _ label: String,
        options: [Option],
        selection: Binding<Option>,
        titleKey: @escaping (Option) -> String
    ) -> some View {
        let currentTitle = viewModel.language.localized(titleKey(selection.wrappedValue))
        return Menu {
            Picker(label, selection: selection) {
                ForEach(options) { option in
                    Text(viewModel.language.localized(titleKey(option))).tag(option)
                }
            }
        } label: {
            HStack {
                Text(currentTitle)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").accessibilityHidden(true)
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 10).fill(ArcaTheme.subtleFieldBackground(for: colorScheme)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(currentTitle)
    }

    @ViewBuilder
    private func draftFilterInputControls(for field: FieldDefinition) -> some View {
        switch field.type {
        case .shortText, .longText:
            VStack(alignment: .leading, spacing: 8) {
                comparisonMenu(
                    viewModel.language.localized("Comparison"),
                    options: TextComparisonOperator.allCases,
                    selection: $draftTextOp, titleKey: { $0.titleKey }
                )
                ArcaStyledTextField(viewModel.language.localized("Value"), text: $draftText, icon: "textformat")
            }

        case .number, .currency:
            VStack(alignment: .leading, spacing: 8) {
                comparisonMenu(
                    viewModel.language.localized("Comparison"),
                    options: NumericComparisonOperator.allCases,
                    selection: $draftNumericOp, titleKey: { $0.titleKey }
                )

                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                    : AnyLayout(HStackLayout(spacing: 8))
                layout {
                    ArcaStyledTextField(
                        viewModel.language.localized(draftNumericOp == .between ? "Min" : "Value"),
                        text: $draftNumberMinText,
                        icon: "number"
                    )
                    if draftNumericOp == .between {
                        ArcaStyledTextField(viewModel.language.localized("Max"), text: $draftNumberMaxText, icon: "number")
                    }
                }
            }

        case .date:
            VStack(alignment: .leading, spacing: 8) {
                comparisonMenu(
                    viewModel.language.localized("Date Range"),
                    options: DateComparisonOperator.allCases,
                    selection: $draftDateOp, titleKey: { $0.titleKey }
                )
                DatePicker(
                    viewModel.language.localized("From"),
                    selection: $draftFromDate,
                    displayedComponents: [.date]
                )
                .frame(minHeight: 44)

                if draftDateOp == .between {
                    DatePicker(
                        viewModel.language.localized("To"),
                        selection: $draftToDate,
                        displayedComponents: [.date]
                    )
                    .frame(minHeight: 44)
                }
            }

        case .singleSelect, .multiSelect:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(field.options) { opt in
                        let currentId = field.options.first(where: { $0.id == draftSelectOptionId })?.id ?? field.options.first?.id
                        let isSelected = currentId == opt.id
                        Button {
                            draftSelectOptionId = opt.id
                        } label: {
                            Text(opt.label)
                                .arcaFont(.caption, weight: .semibold)
                                .foregroundStyle(isSelected ? palette.onFill : .primary)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .frame(minHeight: 44)
                                .background(
                                    Capsule().fill(isSelected ? tint : ArcaTheme.subtleFieldBackground(for: colorScheme))
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }

        case .boolean:
            HStack(spacing: 8) {
                ForEach([true, false], id: \.self) { val in
                    let isSelected = draftBooleanValue == val
                    Button {
                        draftBooleanValue = val
                    } label: {
                        Text(viewModel.language.localized(val ? "Yes" : "No"))
                            .arcaFont(.caption, weight: .bold)
                            .foregroundStyle(isSelected ? palette.onFill : .primary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isSelected ? tint : ArcaTheme.subtleFieldBackground(for: colorScheme))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }

        case .rating:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    Text(viewModel.language.localized("At least"))
                        .arcaFont(.caption, weight: .semibold)
                        .foregroundStyle(.secondary)
                    let selected = min(draftMinimumRating, ratingLimit(for: field))
                    ForEach(1...ratingLimit(for: field), id: \.self) { star in
                        Button {
                            draftMinimumRating = star
                        } label: {
                            Image(systemName: star <= selected ? "star.fill" : "star")
                                .foregroundStyle(star <= selected ? ArcaTheme.warmAmber : .secondary)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(star.formatted(.number.locale(viewModel.language.locale)))
                        .accessibilityAddTraits(star == selected ? .isSelected : [])
                    }
                }
            }

        default:
            EmptyView()
        }
    }

    private func applyCurrentDraftFilter(for field: FieldDefinition) {
        guard let (predicate, detail) = draftPredicate(for: field) else {
            filterInputError = true
            return
        }
        filterInputError = false
        upsertAppliedFilter(AppliedCollectionFieldFilter(
            fieldId: field.id, fieldType: field.type, summary: "\(field.label): \(detail)", predicate: predicate
        ))
    }

    private func draftPredicate(for field: FieldDefinition) -> (CollectionFieldPredicate, String)? {
        let locale = viewModel.language.locale
        switch field.type {
        case .shortText, .longText:
            let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let title = viewModel.language.localized(draftTextOp.titleKey)
            return (.text(draftTextOp, text), "\(title) \(text)")

        case .number:
            let first = LocalizedNumericInput.number(draftNumberMinText, locale: locale)
            let second = LocalizedNumericInput.number(draftNumberMaxText, locale: locale)
            guard let first, draftNumericOp != .between || second != nil else { return nil }
            return (.number(draftNumericOp, first, second), numericFilterSummary)

        case .currency:
            let first = LocalizedNumericInput.decimal(draftNumberMinText, locale: locale)
            let second = LocalizedNumericInput.decimal(draftNumberMaxText, locale: locale)
            guard let first, draftNumericOp != .between || second != nil else { return nil }
            return (.currency(draftNumericOp, first, second), numericFilterSummary)

        case .date:
            let first = CalendarDate(date: draftFromDate)
            let second = CalendarDate(date: draftToDate)
            let summary: String
            switch draftDateOp {
            case .between:
                let start = min(first, second).formatted(locale: locale, style: .short)
                let end = max(first, second).formatted(locale: locale, style: .short)
                summary = "\(start) – \(end)"
            case .after, .before:
                let title = viewModel.language.localized(draftDateOp.titleKey)
                summary = "\(title) \(first.formatted(locale: locale, style: .short))"
            }
            return (.date(draftDateOp, first, second), summary)

        case .singleSelect, .multiSelect:
            guard let option = field.options.first(where: { $0.id == draftSelectOptionId }) ?? field.options.first else {
                return nil
            }
            return (.query(.selectContains(fieldId: field.id, optionId: option.id)), option.label)

        case .boolean:
            return (
                .query(.booleanEquals(fieldId: field.id, draftBooleanValue)),
                viewModel.language.localized(draftBooleanValue ? "Yes" : "No")
            )

        case .rating:
            let minimum = min(draftMinimumRating, ratingLimit(for: field))
            return (.query(.minimumRating(fieldId: field.id, minimum)), "≥ \(minimum.formatted(.number.locale(locale)))★")

        case .dateTime, .attachment, .image:
            return nil
        }
    }

    private var numericFilterSummary: String {
        switch draftNumericOp {
        case .between: return "\(draftNumberMinText) – \(draftNumberMaxText)"
        case .greaterThan: return "> \(draftNumberMinText)"
        case .lessThan: return "< \(draftNumberMinText)"
        case .equals: return "= \(draftNumberMinText)"
        }
    }

    private func upsertAppliedFilter(_ item: AppliedCollectionFieldFilter) {
        appliedFieldFilters.removeAll { $0.fieldId == item.fieldId }
        appliedFieldFilters.append(item)
    }

    private var activeAppliedFilterPillsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(appliedFieldFilters) { item in
                    Button {
                        appliedFieldFilters.removeAll { $0.id == item.id }
                    } label: {
                        HStack(spacing: 5) {
                            Text(item.summary)
                                .arcaFont(.caption, weight: .semibold)
                            Image(systemName: "xmark")
                                .font(.caption2.weight(.bold))
                        }
                        .foregroundStyle(palette.onFill)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .frame(minWidth: 44, minHeight: 44)
                        .background(Capsule().fill(tint))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(viewModel.language.format("Remove filter %@", item.summary))
                }
            }
        }
    }

    // MARK: - Records List Content (Normal | Compact | Box)

    @ViewBuilder
    private func recordsContentSection(records: [RecordItem]) -> some View {
        if records.isEmpty {
            VStack(spacing: 14) {
                CollectionBadgeView(schema: liveSchema, size: 52, presentationStore: presentationStore)
                Text(viewModel.language.localized("No Records Match Your View"))
                    .arcaFont(.body, weight: .bold)
                Button(viewModel.language.format("Add Record to %@", liveSchema.name)) {
                    activeRecordSheetCollection = liveSchema
                }
                .buttonStyle(ArcaPrimaryButtonStyle(tint: tint, foreground: palette.onFill, isFullWidth: false))
            }
            .frame(maxWidth: .infinity)
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(ArcaTheme.cardBackground(for: colorScheme))
            )
        } else {
            switch currentListMode {
            case .compact:
                compactRecordsList(records: records)
            case .box:
                boxRecordsGrid(records: records)
            case .normal:
                normalRecordsList(records: records)
            }
        }
    }

    private func compactRecordsList(records: [RecordItem]) -> some View {
        let secondaryField = presentationStore.resolvedSecondaryField(for: liveSchema)
        return VStack(spacing: 0) {
            ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                NavigationLink {
                    RecordDetailView(viewModel: viewModel, recordId: record.id, schema: liveSchema)
                } label: {
                    HStack(spacing: 10) {
                        RecordThumbnail(viewModel: viewModel, record: record, schema: liveSchema, size: 36)
                        HStack(spacing: 6) {
                            Text(record.title(using: liveSchema))
                                .arcaFont(.subheadline, weight: .bold)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            if record.isFavorite {
                                Image(systemName: "pin.fill")
                                    .font(.caption2)
                                    .foregroundStyle(ArcaTheme.warmAmber)
                            }
                            if !record.allAttachments.isEmpty {
                                Image(systemName: "paperclip")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(ink)
                            }
                        }

                        Spacer(minLength: 6)

                        if let secondaryField,
                           let val = record.values[secondaryField.id],
                           !val.isNullOrEmpty {
                            let text = val.plainTextSummary(for: secondaryField, locale: viewModel.language.locale)
                            if !text.isEmpty {
                                Text(text)
                                    .arcaFont(.caption, weight: .semibold)
                                    .foregroundStyle(ink)
                                    .lineLimit(1)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(tint.opacity(0.12))
                                    )
                            }
                        }

                        Image(systemName: "chevron.forward")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if index < records.count - 1 {
                    Divider().opacity(0.45)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(ArcaTheme.cardBackground(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(ArcaTheme.cardBorder(for: colorScheme), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.16 : 0.025), radius: 6, x: 0, y: 2)
    }

    private func boxRecordsGrid(records: [RecordItem]) -> some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 10), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
        return LazyVGrid(columns: cols, spacing: 10) {
            ForEach(records) { record in
                NavigationLink {
                    RecordDetailView(viewModel: viewModel, recordId: record.id, schema: liveSchema)
                } label: {
                    boxRecordCard(for: record)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func boxRecordCard(for record: RecordItem) -> some View {
        let nonTitleFields = CollectionPresentationStore.secondaryFieldCandidates(for: liveSchema)
        let firstSubtitle: String = {
            for field in nonTitleFields {
                if let val = record.values[field.id], !val.isNullOrEmpty {
                    let s = val.plainTextSummary(for: field, locale: viewModel.language.locale)
                    if !s.isEmpty { return s }
                }
            }
            return liveSchema.name
        }()
        let badgeValueText = presentationStore.compactSecondaryDisplayText(
            for: record,
            schema: liveSchema,
            locale: viewModel.language.locale
        )
        let dateText: String = {
            if let dateField = liveSchema.activeFields.first(where: { $0.type == .date }),
               case .date(let cd) = record.values[dateField.id] {
                return cd.formatted(locale: viewModel.language.locale, style: .short)
            }
            return record.updatedAt.formatted(.dateTime.month(.abbreviated).day().locale(viewModel.language.locale))
        }()

        return VStack(alignment: .leading, spacing: 8) {
            RecordThumbnail(viewModel: viewModel, record: record, schema: liveSchema, size: 96)
            HStack {
                Text("#\(String(record.id.uuidString.prefix(5)).uppercased())")
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(ArcaTheme.subtleFieldBackground(for: colorScheme))
                    )

                Spacer()

                HStack(spacing: 4) {
                    if record.isFavorite {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(ArcaTheme.warmAmber)
                    }
                    Circle()
                        .fill(tint)
                        .frame(width: 8, height: 8)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(record.title(using: liveSchema))
                    .arcaFont(.subheadline, weight: .bold)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(firstSubtitle)
                    .arcaFont(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 2)

            Divider().opacity(0.45)

            HStack {
                Text(badgeValueText ?? "v\(record.revision)")
                    .arcaFont(.caption, weight: .bold)
                    .foregroundStyle(ink)
                    .lineLimit(1)

                Spacer()

                Text(dateText)
                    .arcaFont(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 122, alignment: .topLeading)
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

    private func normalRecordsList(records: [RecordItem]) -> some View {
        VStack(spacing: 10) {
            ForEach(records) { record in
                NavigationLink {
                    RecordDetailView(viewModel: viewModel, recordId: record.id, schema: liveSchema)
                } label: {
                    normalRecordCard(for: record)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func normalRecordCard(for record: RecordItem) -> some View {
        let secondaryText = presentationStore.compactSecondaryDisplayText(
            for: record,
            schema: liveSchema,
            locale: viewModel.language.locale
        )
        let subtitle = record.subtitle(using: liveSchema, locale: viewModel.language.locale)
        let dateFieldPair: (label: String, value: String)? = {
            if let df = liveSchema.activeFields.first(where: { $0.type == .date }),
               let val = record.values[df.id], !val.isNullOrEmpty {
                return (df.label, val.plainTextSummary(for: df, locale: viewModel.language.locale))
            }
            return nil
        }()

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                RecordThumbnail(viewModel: viewModel, record: record, schema: liveSchema, size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(record.title(using: liveSchema))
                            .arcaFont(.subheadline, weight: .bold)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if record.isFavorite {
                            Image(systemName: "pin.fill")
                                .font(.caption)
                                .foregroundStyle(ArcaTheme.warmAmber)
                        }
                        if !record.allAttachments.isEmpty {
                            Image(systemName: "paperclip")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ink)
                        }
                    }

                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .arcaFont(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 6)

                if let secondaryText {
                    Text(secondaryText)
                        .arcaFont(.caption, weight: .bold)
                        .foregroundStyle(ink)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(tint.opacity(0.14)))
                }
            }

            if let pair = dateFieldPair {
                Divider().opacity(0.45)
                HStack {
                    Text("#\(String(record.id.uuidString.prefix(6)).uppercased())")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 4) {
                        Text("\(pair.label):")
                            .arcaFont(.caption)
                            .foregroundStyle(.secondary)
                        Text(pair.value)
                            .arcaFont(.caption, weight: .bold)
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .padding(14)
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

    private func filterChip(title: String, icon: String?, isSelected: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption.weight(.semibold))
                }
                Text(title)
                    .arcaFont(.footnote, weight: .semibold)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(minHeight: 44)
            .background(
                Capsule().fill(isSelected ? tint : ArcaTheme.cardBackground(for: colorScheme))
            )
            .overlay(
                Capsule().strokeBorder(isSelected ? Color.clear : ArcaTheme.cardBorder(for: colorScheme), lineWidth: 1)
            )
            .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Screen 11: Add / Edit Record Form (Supports all 11 Field Types + Validation + Popup/FullScreen Banner)

@available(macOS 14.0, iOS 17.0, *)
public struct AddEditRecordSheetView: View {
    @Bindable var viewModel: ArcaAppViewModel
    public let schema: CollectionSchema
    public let existingRecord: RecordItem?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private let presentationStore: CollectionPresentationStore = .shared

    @ViewState private var draftValues: [UUID: FieldValue] = [:]
    @ViewState private var isFavorite: Bool = false
    @ViewState private var saveError: String?
    @ViewState private var saving = false
    @ViewState private var showAttachmentPicker = false
    @ViewState private var attachmentFieldId: UUID?
    @ViewState private var importingImageFields: Set<UUID> = []
    @ViewState private var validationErrors: [RecordValidationError] = []
    @ViewState private var currencyTextInputs: [UUID: String] = [:]
    @ViewState private var numberTextInputs: [UUID: String] = [:]

    public init(viewModel: ArcaAppViewModel, schema: CollectionSchema, existingRecord: RecordItem?) {
        self.viewModel = viewModel
        self.schema = schema
        self.existingRecord = existingRecord
    }

    private var liveSchema: CollectionSchema {
        viewModel.schema(for: schema.id) ?? schema
    }

    private var palette: CollectionColorPalette { CollectionColorPalette(hex: liveSchema.colorHex) }
    private var tint: Color { palette.fill }
    private var ink: Color { palette.ink(for: colorScheme) }

    private var activeAddMode: CollectionAddFormMode {
        presentationStore.addFormMode(for: liveSchema.id)
    }

    public var body: some View {
        VStack(spacing: 0) {
            ArcaSheetHeaderBar(
                title: existingRecord == nil ? viewModel.language.format("New %@", liveSchema.name) : viewModel.language.localized("Edit Record"),
                subtitle: viewModel.language.localized(
                    existingRecord == nil
                        ? (activeAddMode == .fullScreen ? "Full-Screen Form Mode" : "Popup Card Mode")
                        : "Saved locally first"
                ),
                leadingLabel: "Cancel",
                leadingAction: { dismiss() },
                trailingLabel: "Save",
                trailingAction: { saveDraft() }
            )
            .disabled(!importingImageFields.isEmpty)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    collectionFormIdentityBanner

                    if let saveError { Text(saveError).foregroundStyle(ArcaTheme.dangerRed) }
                    if !validationErrors.isEmpty {
                        ArcaSectionCard(title: viewModel.language.localized("Please Check These Fields"), icon: "exclamationmark.triangle.fill", iconTint: ArcaTheme.dangerRed) {
                            ForEach(validationErrors) { err in
                                Label(err.errorDescription ?? err.reason, systemImage: "xmark.circle.fill")
                                    .arcaFont(.footnote, weight: .semibold)
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
                                Text(viewModel.language.localized("Pin Record to Favorites"))
                                    .arcaFont(.subheadline, weight: .semibold)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: isFavorite ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(isFavorite ? ArcaTheme.warmAmber : .secondary)
                            }
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isFavorite ? .isSelected : [])
                    }

                    // Dynamic Schema Fields Card
                    ArcaSectionCard(title: viewModel.language.format("%@ Fields", liveSchema.name), icon: liveSchema.iconName, iconTint: ink) {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(liveSchema.activeFields) { field in
                                fieldEditorRow(for: field)
                                if field.id != liveSchema.activeFields.last?.id {
                                    Divider().opacity(0.45)
                                }
                            }
                        }
                    }

                    Button {
                        saveDraft()
                    } label: {
                        Label(viewModel.language.localized(existingRecord == nil ? "Save Record" : "Save Changes"), systemImage: "checkmark.circle.fill")
                    }
                    .disabled(saving || !importingImageFields.isEmpty)
                    .buttonStyle(ArcaPrimaryButtonStyle(tint: tint, foreground: palette.onFill))
                }
                .padding(18)
            }
            .background(ArcaTheme.canvasBackground(for: colorScheme))
        }
        .onAppear {
            populateInitialDraft()
        }
        .fileImporter(isPresented: $showAttachmentPicker, allowedContentTypes: attachmentFieldId.flatMap { id in liveSchema.fields.first { $0.id == id } }?.type == .image ? [.image] : [.item]) { result in
            switch result {
            case .success(let url):
                guard let fieldId = attachmentFieldId else { return }
                importingImageFields.insert(fieldId)
                Task {
                    defer { importingImageFields.remove(fieldId) }
                    do {
                        let isImage = liveSchema.fields.first(where: { $0.id == fieldId })?.type == .image
                        let ref = try await (isImage ? viewModel.attachImage(from: url, to: liveSchema.spaceId) : viewModel.attachFile(from: url, to: liveSchema.spaceId))
                        var refs: [AttachmentReference] = []
                        if !isImage, case .attachments(let current) = draftValues[fieldId] { refs = current }
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

    private var collectionFormIdentityBanner: some View {
        HStack(spacing: 12) {
            CollectionBadgeView(schema: liveSchema, size: 38, presentationStore: presentationStore)
            VStack(alignment: .leading, spacing: 2) {
                Text(existingRecord == nil ? viewModel.language.format("New %@", liveSchema.name) : viewModel.language.localized("Edit Record"))
                    .arcaFont(.subheadline, weight: .heavy)
                    .foregroundStyle(palette.onFill)
                Text(viewModel.language.localized(activeAddMode == .fullScreen ? "Full-Screen Form Mode" : "Popup Card Mode"))
                    .arcaFont(.caption)
                    .foregroundStyle(palette.onFill)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint, tint.opacity(0.82)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }

    private func populateInitialDraft() {
        if let rec = existingRecord {
            draftValues = rec.values
            isFavorite = rec.isFavorite
        } else {
            for field in liveSchema.activeFields {
                if let def = field.defaultValue {
                    draftValues[field.id] = def
                }
            }
        }
        for field in liveSchema.activeFields {
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
                    .arcaFont(.footnote, weight: .bold)
                    .foregroundStyle(.secondary)
                if field.isRequired {
                    Text(viewModel.language.localized("Required"))
                        .arcaFont(.caption2, weight: .bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(tint.opacity(0.14)))
                        .foregroundStyle(ink)
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
                .arcaFont(.body)
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
                        .arcaFont(.footnote, weight: .bold)
                        .foregroundStyle(ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.12)))

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
                        .arcaFont(.footnote, weight: .medium)
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
                        .arcaFont(.footnote, weight: .medium)
                }

            case .boolean:
                Toggle(field.label, isOn: Binding(
                    get: {
                        if case .boolean(let b) = draftValues[field.id] { return b }
                        return false
                    },
                    set: { draftValues[field.id] = .boolean($0) }
                ))
                .arcaFont(.subheadline, weight: .medium)

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
                                    .arcaFont(.footnote, weight: .semibold)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .frame(minHeight: 44)
                                    .background(Capsule().fill(selected ? tint : ArcaTheme.subtleFieldBackground(for: colorScheme)))
                                    .foregroundStyle(selected ? palette.onFill : .primary)
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
                                    .arcaFont(.footnote, weight: .semibold)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .frame(minHeight: 44)
                                    .background(Capsule().fill(selected ? tint : ArcaTheme.subtleFieldBackground(for: colorScheme)))
                                    .foregroundStyle(selected ? palette.onFill : .primary)
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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 8) {
                    ForEach(1...max(1, min(10, field.validation.maxRating)), id: \.self) { star in
                        Button {
                            draftValues[field.id] = .rating(star)
                        } label: {
                            Image(systemName: star <= currentRating ? "star.fill" : "star")
                                .font(.title2)
                                .frame(minWidth: 44, minHeight: 44)
                                .foregroundStyle(star <= currentRating ? ArcaTheme.warmAmber : Color.secondary.opacity(0.35))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("\(field.label), \(star) / \(field.validation.maxRating)"))
                        .accessibilityAddTraits(star == currentRating ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)

            case .image:
                ImageFieldEditor(viewModel: viewModel, spaceId: liveSchema.spaceId, field: field,
                    value: Binding(get: { draftValues[field.id] ?? .null }, set: { draftValues[field.id] = $0 }),
                    chooseFile: { attachmentFieldId = field.id; showAttachmentPicker = true },
                    importingChanged: { busy in
                        if busy { importingImageFields.insert(field.id) } else { importingImageFields.remove(field.id) }
                    })
                    .disabled(importingImageFields.contains(field.id))

            case .attachment:
                let currentAttachments: [AttachmentReference] = {
                    if case .attachments(let refs) = draftValues[field.id] { return refs }
                    return []
                }()
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(currentAttachments) { att in
                        HStack {
                            Image(systemName: "doc.fill")
                                .foregroundStyle(ink)
                            Text(att.filename)
                                .arcaFont(.footnote, weight: .medium)
                            Spacer()
                            Text("\(ByteCountFormatter.string(fromByteCount: att.byteSize, countStyle: .file))")
                                .arcaFont(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(ArcaTheme.subtleFieldBackground(for: colorScheme)))
                    }
                    Button {
                        attachmentFieldId = field.id
                        showAttachmentPicker = true
                    } label: {
                        Label(viewModel.language.localized("Attach File from Files"), systemImage: "paperclip.badge.plus")
                    }
                    .buttonStyle(ArcaSecondaryButtonStyle(tint: ink))
                    .disabled(viewModel.spaces.first(where: { $0.id == liveSchema.spaceId })?.storageMode != .localOnly)
                    if viewModel.spaces.first(where: { $0.id == liveSchema.spaceId })?.storageMode != .localOnly {
                        Text(viewModel.language.localized("File attachments are available in Local-Only Spaces. Cloud attachment upload is not available yet."))
                            .arcaFont(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func saveDraft() {
        guard !saving, importingImageFields.isEmpty else { return }
        for field in liveSchema.activeFields {
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
        let errs = SchemaEngine.validate(values: draftValues, against: liveSchema, locale: viewModel.language.locale)
        if !errs.isEmpty {
            validationErrors = errs
            saveError = errs.map { $0.errorDescription ?? $0.reason }.joined(separator: "\n")
            return
        }
        saving = true
        Task {
            defer { saving = false }
            do {
                try await viewModel.saveRecord(existingRecord: existingRecord, schema: liveSchema,
                                               values: draftValues, isFavorite: isFavorite)
                dismiss()
            } catch {
                saveError = "Could not save this record. " + error.localizedDescription
            }
        }
    }
}

// MARK: - Screen 12: Record Detail with Color Header, Clean Field Cards, Attachments, Edit/Favorite & Security

@available(macOS 14.0, iOS 17.0, *)
public struct RecordDetailView: View {
    @Bindable var viewModel: ArcaAppViewModel
    public let recordId: UUID
    public let schema: CollectionSchema
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let presentationStore: CollectionPresentationStore = .shared

    @ViewState private var showingEditSheet = false
    @ViewState private var duplicateError: String?
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

    private var palette: CollectionColorPalette { CollectionColorPalette(hex: liveSchema.colorHex) }
    private var ink: Color { palette.ink(for: colorScheme) }

    public var body: some View {
        let tint = palette.fill
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
                                        .font(.footnote.weight(.bold))
                                    Text(liveSchema.name)
                                        .arcaFont(.subheadline, weight: .bold)
                                }
                                .foregroundStyle(ink)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(minHeight: 44)
                                .background(Capsule().fill(tint.opacity(0.12)))
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Button {
                                Task { await viewModel.toggleFavorite(recordId: rec.id) }
                            } label: {
                                Image(systemName: rec.isFavorite ? "pin.fill" : "pin")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(rec.isFavorite ? .white : ArcaTheme.warmAmber)
                                    .frame(width: 44, height: 44)
                                    .background(Circle().fill(rec.isFavorite ? ArcaTheme.warmAmber : ArcaTheme.warmAmber.opacity(0.14)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(viewModel.language.localized("Pin Record to Favorites"))
                            .accessibilityAddTraits(rec.isFavorite ? .isSelected : [])

                            Button {
                                showingEditSheet = true
                            } label: {
                                Text(viewModel.language.localized("Edit"))
                                    .arcaFont(.subheadline, weight: .bold)
                                    .foregroundStyle(palette.onFill)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .frame(minHeight: 44)
                                    .background(Capsule().fill(tint))
                            }
                            .buttonStyle(.plain)
                        }

                        // Record Color Header Hero Card
                        recordColorHeroHeaderCard(for: rec, tint: tint)

                        ForEach(liveSchema.imageFields) { field in
                            if case .attachments(let images) = rec.values[field.id], let image = images.first {
                                ArcaSectionCard(title: field.label, icon: "photo") {
                                    StoredRecordImage(viewModel: viewModel, spaceId: rec.spaceId, reference: image, size: 240)
                                }
                            }
                        }

                        // Clean Structured Details Card
                        savedFieldsDetailCard(for: rec, tint: tint)

                        // Archived Field Values (if any retained on this record)
                        archivedFieldsDetailCard(for: rec)

                        // Attachments Card
                        let fileAttachments = liveSchema.fields.filter { $0.type == .attachment }.flatMap { field -> [AttachmentReference] in
                            if case .attachments(let refs) = rec.values[field.id] { return refs }; return []
                        }
                        if !fileAttachments.isEmpty {
                            ArcaSectionCard(title: viewModel.language.localized("Attachments (SHA-256 Verified)"), icon: "paperclip", iconTint: ArcaTheme.secondaryEmerald) {
                                ForEach(fileAttachments) { att in
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
                                                .arcaFont(.subheadline, weight: .semibold)
                                            Text("\(ByteCountFormatter.string(fromByteCount: att.byteSize, countStyle: .file)) • SHA-256 \(att.sha256Hex.prefix(10))…")
                                                .arcaFont(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text(att.uploadState.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                                            .arcaFont(.caption2, weight: .bold)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Capsule().fill(ArcaTheme.secondaryEmerald.opacity(0.12)))
                                            .foregroundStyle(ArcaTheme.secondaryEmerald)
                                    }
                                }
                            }
                        }

                        // Actions Card
                        ArcaSectionCard(title: viewModel.language.localized("Record Actions & Sharing"), icon: "square.and.arrow.up", iconTint: tint) {
                            VStack(spacing: 10) {
                                HStack(spacing: 10) {
                                    Button {
                                        Task { do { try await viewModel.duplicateRecord(rec) } catch { duplicateError = viewModel.language.localized(error.localizedDescription) } }
                                    } label: {
                                        Label(viewModel.language.localized("Duplicate"), systemImage: "plus.square.on.square")
                                    }
                                    .buttonStyle(ArcaSecondaryButtonStyle(tint: tint, isFullWidth: true))

                                    Button {
                                        showingLocalQRSheet = true
                                    } label: {
                                        Label(viewModel.language.localized("Local QR Tag"), systemImage: "qrcode")
                                    }
                                    .buttonStyle(ArcaSecondaryButtonStyle(tint: tint, isFullWidth: true))
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
                                    Label(viewModel.language.localized("Delete Record"), systemImage: "trash")
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
                        #if os(macOS)
                        .frame(minWidth: 370, idealWidth: 400, minHeight: 580, idealHeight: 680)
                        #endif
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
                Text(viewModel.language.localized("Record no longer available."))
                    .foregroundStyle(.secondary)
            }
        }
        .alert(viewModel.language.localized("Could not duplicate record"), isPresented: Binding(get: { duplicateError != nil }, set: { if !$0 { duplicateError = nil } })) {
            Button(viewModel.language.localized("OK")) { duplicateError = nil }
        } message: { Text(duplicateError ?? "") }
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

    // MARK: - Record Color Header Hero Card

    private func recordColorHeroHeaderCard(for rec: RecordItem, tint: Color) -> some View {
        let primaryId = liveSchema.primaryTitleField?.id
        let highlightFields = liveSchema.activeFields.filter { field in
            guard field.id != primaryId,
                  let val = rec.values[field.id],
                  !val.isNullOrEmpty else { return false }
            return field.type != .attachment && field.type != .image && field.type != .longText
        }
        let topHighlights = Array(highlightFields.prefix(2))

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                CollectionBadgeView(schema: liveSchema, size: 38, presentationStore: presentationStore)

                VStack(alignment: .leading, spacing: 2) {
                    Text(liveSchema.name.uppercased(with: viewModel.language.locale))
                        .arcaFont(.caption, weight: .bold)
                        .tracking(0.6)
                        .foregroundStyle(ink)
                    Text(viewModel.language.format("%@ • Revision %d • Updated %@", liveSchema.name, rec.revision, rec.updatedAt.formatted(.dateTime.day().month().hour().minute().locale(viewModel.language.locale))))
                        .arcaFont(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("#\(String(rec.id.uuidString.prefix(6)).uppercased())")
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .foregroundStyle(ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(tint.opacity(0.14)))
            }

            Text(rec.title(using: liveSchema))
                .arcaFont(.title3, weight: .heavy)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)

            if !topHighlights.isEmpty {
                Divider().opacity(0.45)
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: dynamicTypeSize.isAccessibilitySize ? 1 : max(1, topHighlights.count)),
                    spacing: 10
                ) {
                    ForEach(topHighlights) { field in
                        let summary = (rec.values[field.id] ?? .null).plainTextSummary(for: field, locale: viewModel.language.locale)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(field.label)
                                .arcaFont(.caption, weight: .semibold)
                                .foregroundStyle(.secondary)
                            Text(summary)
                                .arcaFont(.subheadline, weight: .heavy)
                                .foregroundStyle(field.type == .currency || field.type == .number ? ink : .primary)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(ArcaTheme.subtleFieldBackground(for: colorScheme))
                        )
                    }
                }
            }
        }
        .padding(16)
        .padding(.top, 4)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(ArcaTheme.cardBackground(for: colorScheme))
        )
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(
                topLeadingRadius: 18,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 18,
                style: .continuous
            )
            .fill(tint)
            .frame(height: 6)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(ArcaTheme.cardBorder(for: colorScheme), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.035), radius: 10, x: 0, y: 4)
    }

    // MARK: - Clean Structured Field Cards

    private func savedFieldsDetailCard(for rec: RecordItem, tint: Color) -> some View {
        let populatedFields = liveSchema.activeFields.filter { field in
            guard field.type != .image, let val = rec.values[field.id] else { return false }
            return !val.isNullOrEmpty
        }

        return ArcaSectionCard(title: viewModel.language.localized("Saved Fields"), icon: "list.clipboard.fill", iconTint: tint) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(populatedFields) { field in
                    let val = rec.values[field.id] ?? .null
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Image(systemName: field.type.iconName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ink)
                            Text(field.label.uppercased(with: viewModel.language.locale))
                                .arcaFont(.caption2, weight: .bold)
                                .tracking(0.5)
                                .foregroundStyle(.secondary)
                            if field.privacy != nil {
                                Image(systemName: "hand.raised.fill")
                                    .font(.caption2)
                                    .foregroundStyle(ArcaTheme.plumSensitive)
                            }
                        }
                        Text(val.plainTextSummary(for: field, locale: viewModel.language.locale))
                            .arcaFont(.body, weight: .medium)
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

    @ViewBuilder
    private func archivedFieldsDetailCard(for rec: RecordItem) -> some View {
        let populatedArchived = liveSchema.archivedFields.filter { field in
            guard let val = rec.values[field.id] else { return false }
            return !val.isNullOrEmpty
        }
        if !populatedArchived.isEmpty {
            ArcaSectionCard(title: viewModel.language.localized("Archived Fields (Recoverable)"), icon: "archivebox.fill", iconTint: ArcaTheme.warmAmber) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(populatedArchived) { field in
                        let val = rec.values[field.id] ?? .null
                        VStack(alignment: .leading, spacing: 4) {
                            Text(field.label.uppercased(with: viewModel.language.locale))
                                .arcaFont(.caption2, weight: .bold)
                                .foregroundStyle(.secondary)
                            Text(val.plainTextSummary(for: field, locale: viewModel.language.locale))
                                .arcaFont(.subheadline, weight: .medium)
                                .foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(ArcaTheme.subtleFieldBackground(for: colorScheme))
                        )
                    }
                }
            }
        }
    }

    private struct RecordDeletionTarget: Identifiable {
        let id: UUID
        let title: String
    }

    private func localQRSheet(for rec: RecordItem) -> some View {
        let deepLink = OptionalCapabilityEngine.localRecordDeepLink(spaceId: rec.spaceId, collectionId: rec.collectionId, recordId: rec.id)
        return VStack(spacing: 0) {
            ArcaSheetHeaderBar(title: viewModel.language.localized("Local QR Deep Link"), leadingLabel: "Done", leadingAction: { showingLocalQRSheet = false })

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

                Text(viewModel.language.localized("Physical Asset Tag Deep Link"))
                    .arcaFont(.headline, weight: .bold)

                Text(deepLink.absoluteString)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(ArcaTheme.subtleFieldBackground(for: colorScheme)))

                Text(viewModel.language.localized("Privacy guarantee: A local QR code only identifies this record by UUID on devices that already have this Space. It never embeds or transmits your record contents."))
                    .arcaFont(.footnote)
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
                                        .font(.headline)
                                        .foregroundStyle(isSelected ? ArcaTheme.accent : .secondary)
                                    Text(field.label)
                                        .arcaFont(.subheadline, weight: .semibold)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text((rec.values[field.id] ?? .null).plainTextSummary(for: field))
                                        .arcaFont(.footnote)
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
                                    .arcaFont(.footnote, weight: .bold)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text((rec.values[field.id] ?? .null).plainTextSummary(for: field))
                                    .arcaFont(.footnote, weight: .medium)
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
