import SwiftUI
import ArcaCore

// MARK: - Screen 5: Home with Space Switcher, Collections, Recent Records, and Global Search

@available(macOS 14.0, iOS 17.0, *)
public struct HomeScreenView: View {
    @Bindable var viewModel: ArcaAppViewModel

    @ViewState private var showingSpaceManager = false
    @ViewState private var showingTemplateGallery = false
    @ViewState private var showingAIAssistant = false
    @ViewState private var showingManualBuilder = false
    @ViewState private var activeRecordSheetCollection: CollectionSchema?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme

    public init(viewModel: ArcaAppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    // Custom iOS Large Title Header + Quick Actions
                    homeHeaderBar

                    // Operational state banner (offline, conflict, quota, etc.)
                    OperationalStateBannerView(state: viewModel.bannerState) {
                        viewModel.handleBannerAction()
                    }

                    // Space Switcher Strip
                    spaceSwitcherCard

                    // Native-feel Embedded Search Bar
                    ArcaSearchBar(
                        text: $viewModel.globalSearchText,
                        placeholder: ArcaStrings.text("home.searchPlaceholder", language: viewModel.language)
                    )

                    // Search Results (when search query is non-empty)
                    if !viewModel.globalSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        globalSearchResultsSection
                    } else {
                        // Collections Grid
                        collectionsSection

                        // Pinned / Favorites Section
                        if !viewModel.favoriteRecordsInCurrentSpace.isEmpty {
                            favoritesSection
                        }

                        // Recent Records Section
                        recentRecordsSection
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 28)
            }
            .background(ArcaTheme.canvasBackground(for: colorScheme))
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .sheet(isPresented: $showingSpaceManager) {
                ManageSpacesSheetView(viewModel: viewModel)
                    .frame(minWidth: 370, idealWidth: 400, minHeight: 580, idealHeight: 680)
            }
            .sheet(isPresented: $showingAIAssistant) {
                AICollectionAssistantSheetView(viewModel: viewModel)
                    .frame(minWidth: 370, idealWidth: 400, minHeight: 580, idealHeight: 680)
            }
            .sheet(isPresented: $showingTemplateGallery) {
                TemplateGallerySheetView(viewModel: viewModel)
                    .frame(minWidth: 370, idealWidth: 400, minHeight: 580, idealHeight: 680)
            }
            .sheet(isPresented: $showingManualBuilder) {
                ManualCollectionBuilderSheetView(viewModel: viewModel)
                    .frame(minWidth: 370, idealWidth: 400, minHeight: 580, idealHeight: 680)
            }
            .sheet(item: $activeRecordSheetCollection) { col in
                AddEditRecordSheetView(viewModel: viewModel, schema: col, existingRecord: nil)
                    .frame(minWidth: 370, idealWidth: 400, minHeight: 580, idealHeight: 680)
            }
        }
    }

    private func creationText(_ key: String) -> String {
        ArcaStrings.text(key, language: viewModel.language)
    }

    private var homeHeaderBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                if let current = viewModel.currentSpace {
                    storageModePill(for: current.storageMode)
                }
                Text(viewModel.currentSpace?.name ?? ArcaStrings.text("app.name", language: viewModel.language))
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.primary)
            }

            Spacer()

            HStack(spacing: 8) {
                if let firstCol = viewModel.collectionsInCurrentSpace.first {
                    Button {
                        activeRecordSheetCollection = firstCol
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                                .font(.footnote.weight(.bold))
                            Text(ArcaStrings.text("home.quickAddRecord", language: viewModel.language))
                                .font(.footnote.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(ArcaTheme.accent))
                        .shadow(color: ArcaTheme.accent.opacity(0.24), radius: 6, x: 0, y: 3)
                    }
                    .buttonStyle(.plain)
                }

                Menu {
                    Button {
                        showingAIAssistant = true
                    } label: {
                        Label(creationText("creation.aiMenu"), systemImage: "sparkles")
                    }
                    Button {
                        showingTemplateGallery = true
                    } label: {
                        Label(creationText("creation.templatesMenu"), systemImage: "sparkles.rectangle.stack")
                    }
                    Button {
                        showingManualBuilder = true
                    } label: {
                        Label(creationText("creation.manualMenu"), systemImage: "slider.horizontal.3")
                    }
                    Divider()
                    Button {
                        showingSpaceManager = true
                    } label: {
                        Label(viewModel.language.localized("Manage Spaces…"), systemImage: "rectangle.stack.fill")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.title)
                        .foregroundStyle(ArcaTheme.accent)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var spaceSwitcherCard: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.spaces) { space in
                    let isSelected = space.id == viewModel.currentSpaceId
                    let spaceTint = ArcaTheme.color(fromHex: space.accentHex)
                    Button {
                        Task { await viewModel.selectSpace(space.id) }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: space.iconName)
                                .font(.footnote.weight(.semibold))
                            Text(space.name)
                                .font(.footnote.weight(.semibold))
                            if space.storageMode == .localOnly {
                                Image(systemName: "lock.fill")
                                    .font(.caption2)
                                    .opacity(0.75)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            Capsule().fill(
                                isSelected
                                    ? spaceTint
                                    : ArcaTheme.cardBackground(for: colorScheme)
                            )
                        )
                        .overlay(
                            Capsule().strokeBorder(
                                isSelected ? Color.clear : ArcaTheme.cardBorder(for: colorScheme),
                                lineWidth: 1
                            )
                        )
                        .foregroundStyle(isSelected ? .white : .primary)
                        .shadow(color: isSelected ? spaceTint.opacity(0.25) : .clear, radius: 6, x: 0, y: 3)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    showingSpaceManager = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus.rectangle.on.folder")
                            .font(.caption.weight(.semibold))
                        Text(viewModel.language.localized("Spaces"))
                            .font(.footnote.weight(.semibold))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        Capsule().strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func storageModePill(for mode: SpaceStorageMode) -> some View {
        let isLocal = mode == .localOnly
        let tint = isLocal ? ArcaTheme.secondaryEmerald : ArcaTheme.accent
        return HStack(spacing: 5) {
            Image(systemName: mode == .arcaSync ? "checkmark.icloud.fill" : (isLocal ? "internaldrive.fill" : "externaldrive.fill.badge.icloud"))
                .font(.caption2.weight(.bold))
            Text(viewModel.language.localized(mode == .arcaSync ? "Arca Sync (E2EE)" : (isLocal ? "On This Device Only" : "Personal Cloud Backup")))
                .font(.caption2.weight(.bold))
                .tracking(0.4)
        }
        .foregroundStyle(tint)
    }

    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(ArcaStrings.text("home.collections", language: viewModel.language).uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)

                Spacer()

                Menu {
                    Button { showingAIAssistant = true } label: {
                        Label(creationText("creation.aiMenu"), systemImage: "sparkles")
                    }
                    Button { showingTemplateGallery = true } label: {
                        Label(creationText("creation.templatesMenu"), systemImage: "rectangle.stack")
                    }
                    Button { showingManualBuilder = true } label: {
                        Label(creationText("creation.manualMenu"), systemImage: "slider.horizontal.3")
                    }
                } label: {
                    Label(ArcaStrings.text("home.newCollection", language: viewModel.language), systemImage: "plus.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(ArcaTheme.accent)
                }
                .buttonStyle(.plain)
            }

            if viewModel.collectionsInCurrentSpace.isEmpty {
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(ArcaTheme.accent.opacity(0.10))
                            .frame(width: 56, height: 56)
                        Image(systemName: "sparkles")
                            .font(.title)
                            .foregroundStyle(ArcaTheme.accent)
                    }
                    Text(creationText("creation.emptyTitle"))
                        .font(.body.weight(.bold))
                    Text(creationText("creation.emptyBody"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button { showingAIAssistant = true } label: {
                        Label(creationText("creation.ai"), systemImage: "sparkles")
                    }
                    .buttonStyle(ArcaPrimaryButtonStyle())
                    HStack(spacing: 18) {
                        Button(creationText("creation.templates")) { showingTemplateGallery = true }
                        Button(creationText("creation.manual")) { showingManualBuilder = true }
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(ArcaTheme.accent)
                    .buttonStyle(.plain)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(ArcaTheme.cardBackground(for: colorScheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(ArcaTheme.cardBorder(for: colorScheme), lineWidth: 1)
                )
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                    ForEach(viewModel.collectionsInCurrentSpace) { col in
                        NavigationLink {
                            CollectionRecordListView(viewModel: viewModel, schema: col)
                        } label: {
                            collectionCard(col)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func collectionCard(_ col: CollectionSchema) -> some View {
        let count = viewModel.recordCount(for: col.id)
        let tint = ArcaTheme.color(fromHex: col.colorHex)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(tint)
                        .frame(width: 38, height: 38)
                        .shadow(color: tint.opacity(0.28), radius: 6, x: 0, y: 3)
                    Image(systemName: col.iconName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                }

                Spacer()

                Text("\(count)")
                    .font(.body.weight(.bold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(tint.opacity(0.12)))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(col.name)
                    .font(.body.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(viewModel.language.format("count.fields", col.activeFields.count))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(ArcaTheme.cardBackground(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(ArcaTheme.cardBorder(for: colorScheme), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.20 : 0.03), radius: 8, x: 0, y: 4)
    }

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "pin.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ArcaTheme.warmAmber)
                Text(ArcaStrings.text("home.favorites", language: viewModel.language).uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
            }

            ForEach(viewModel.favoriteRecordsInCurrentSpace) { record in
                if let schema = viewModel.schema(for: record.collectionId) {
                    NavigationLink {
                        RecordDetailView(viewModel: viewModel, recordId: record.id, schema: schema)
                    } label: {
                        RecordRowCardView(record: record, schema: schema, locale: viewModel.language.locale)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var recentRecordsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ArcaStrings.text("home.recentRecords", language: viewModel.language).uppercased())
                .font(.caption.weight(.bold))
                .tracking(0.6)
                .foregroundStyle(.secondary)

            if viewModel.recentRecordsInCurrentSpace.isEmpty {
                Text(viewModel.language.localized("Saved records will appear here for instant retrieval."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(viewModel.recentRecordsInCurrentSpace.prefix(8)) { record in
                    if let schema = viewModel.schema(for: record.collectionId) {
                        NavigationLink {
                            RecordDetailView(viewModel: viewModel, recordId: record.id, schema: schema)
                        } label: {
                            RecordRowCardView(record: record, schema: schema, locale: viewModel.language.locale)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var globalSearchResultsSection: some View {
        let matches = viewModel.searchRecordsInCurrentSpace(queryText: viewModel.globalSearchText)
        return VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.language.format("SEARCH RESULTS (%d)", matches.count))
                .font(.caption.weight(.bold))
                .tracking(0.6)
                .foregroundStyle(.secondary)

            if matches.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(viewModel.language.format("No matching records found for “%@”", viewModel.globalSearchText))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(28)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(ArcaTheme.cardBackground(for: colorScheme))
                )
            } else {
                ForEach(matches) { record in
                    if let schema = viewModel.schema(for: record.collectionId) {
                        NavigationLink {
                            RecordDetailView(viewModel: viewModel, recordId: record.id, schema: schema)
                        } label: {
                            RecordRowCardView(record: record, schema: schema, locale: viewModel.language.locale)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

@available(macOS 14.0, iOS 17.0, *)
public struct RecordRowCardView: View {
    public let record: RecordItem
    public let schema: CollectionSchema
    public let locale: Locale
    @Environment(\.colorScheme) private var colorScheme

    public init(record: RecordItem, schema: CollectionSchema, locale: Locale = .current) {
        self.record = record
        self.schema = schema
        self.locale = locale
    }

    public var body: some View {
        let tint = ArcaTheme.color(fromHex: schema.colorHex)
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(tint.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: schema.iconName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(record.title(using: schema))
                        .font(.body.weight(.semibold))
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
                            .foregroundStyle(ArcaTheme.accent)
                    }
                }

                let sub = record.subtitle(using: schema, locale: locale)
                HStack(spacing: 6) {
                    Text(schema.name)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(tint.opacity(0.10)))

                    if !sub.isEmpty {
                        Text(sub)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(13)
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
}

// MARK: - Screen 6: Create / Manage Spaces

@available(macOS 14.0, iOS 17.0, *)
public struct ManageSpacesSheetView: View {
    @Bindable var viewModel: ArcaAppViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @ViewState private var newSpaceName = ""
    @ViewState private var newSpaceMode: SpaceStorageMode = .arcaSync
    @ViewState private var newSpaceIcon = "folder.fill"
    @ViewState private var renamingSpace: SpaceMetadata?
    @ViewState private var renameText = ""
    @ViewState private var pendingSpaceDeletion: SpaceMetadata?

    private let availableIcons: [(label: String, icon: String)] = [
        ("Folder", "folder.fill"),
        ("Home", "house.fill"),
        ("Vehicle", "car.fill"),
        ("Work", "briefcase.fill")
    ]

    public var body: some View {
        VStack(spacing: 0) {
            ArcaSheetHeaderBar(
                title: viewModel.language.localized("Spaces"),
                subtitle: viewModel.language.localized("Independent Local SQLite Databases"),
                leadingLabel: viewModel.language.localized("Done"),
                leadingAction: { dismiss() }
            )

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    ArcaSectionCard(title: viewModel.language.localized("Your Spaces"), icon: "rectangle.stack.fill") {
                        VStack(spacing: 10) {
                            ForEach(viewModel.spaces) { space in
                                let isActive = space.id == viewModel.currentSpaceId
                                let tint = ArcaTheme.color(fromHex: space.accentHex)

                                HStack(spacing: 12) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(tint.opacity(0.15))
                                            .frame(width: 38, height: 38)
                                        Image(systemName: space.iconName)
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(tint)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(space.name)
                                                .font(.body.weight(.bold))
                                            if isActive {
                                                Text(viewModel.language.localized("ACTIVE"))
                                                    .font(.caption2.weight(.bold))
                                                    .foregroundStyle(.white)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Capsule().fill(ArcaTheme.accent))
                                            }
                                        }
                                        Text(space.storageMode == .arcaSync ? viewModel.language.localized("Arca Sync (E2EE)") : (space.storageMode == .localOnly ? viewModel.language.localized("On This Device Only") : viewModel.language.localized("Personal Cloud Backup")))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    if !isActive {
                                        ArcaPillActionButton(viewModel.language.localized("Switch"), tint: ArcaTheme.accent) {
                                            Task {
                                                await viewModel.selectSpace(space.id)
                                                dismiss()
                                            }
                                        }
                                    }

                                    Menu {
                                        Button(viewModel.language.localized("Rename Space…")) {
                                            renamingSpace = space
                                            renameText = space.name
                                        }
                                        if viewModel.spaces.count > 1 {
                                            Button(viewModel.language.localized("Delete Space"), role: .destructive) {
                                                pendingSpaceDeletion = space
                                            }
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis.circle.fill")
                                            .font(.title3)
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(ArcaTheme.subtleFieldBackground(for: colorScheme))
                                )
                            }
                        }
                    }

                    if let spaceToRename = renamingSpace {
                        ArcaSectionCard(title: viewModel.language.format("Rename “%@”", spaceToRename.name), icon: "pencil") {
                            ArcaStyledTextField(viewModel.language.localized("New Space Name"), text: $renameText, icon: "character.cursor.ibeam")
                            HStack(spacing: 10) {
                                Button(viewModel.language.localized("Cancel")) { renamingSpace = nil }
                                    .buttonStyle(ArcaSecondaryButtonStyle(tint: .secondary))
                                Button(viewModel.language.localized("Save Name")) {
                                    Task {
                                        await viewModel.renameSpace(id: spaceToRename.id, newName: renameText)
                                        renamingSpace = nil
                                    }
                                }
                                .buttonStyle(ArcaPrimaryButtonStyle())
                            }
                        }
                    }

                    ArcaSectionCard(
                        title: viewModel.language.localized("Create New Independent Space"),
                        subtitle: viewModel.language.localized("Each Space is stored in its own isolated SQLite database with independent storage and backup settings."),
                        icon: "plus.rectangle.on.folder.fill"
                    ) {
                        ArcaStyledTextField(viewModel.language.localized("Space Name (e.g., Vacation Cabin, Classic Car)"), text: $newSpaceName, icon: "folder.badge.plus")

                        VStack(alignment: .leading, spacing: 6) {
                            Text(viewModel.language.localized("Storage Mode"))
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)

                            HStack(spacing: 8) {
                                modeChoicePill(.localOnly, label: viewModel.language.localized("Local Only"), icon: "iphone")
                                modeChoicePill(.arcaSync, label: viewModel.language.localized("Arca Sync (E2EE)"), icon: "icloud.fill")
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(viewModel.language.localized("Space Icon"))
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)

                            HStack(spacing: 8) {
                                ForEach(availableIcons, id: \.icon) { item in
                                    let selected = newSpaceIcon == item.icon
                                    Button {
                                        newSpaceIcon = item.icon
                                    } label: {
                                        Image(systemName: item.icon)
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(selected ? .white : .primary)
                                            .frame(width: 44, height: 44)
                                            .background(
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .fill(selected ? ArcaTheme.accent : ArcaTheme.subtleFieldBackground(for: colorScheme))
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(viewModel.language.localized(item.label))
                                    .accessibilityAddTraits(selected ? .isSelected : [])
                                }
                            }
                        }

                        Button(viewModel.language.localized("Create Space")) {
                            let name = newSpaceName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !name.isEmpty else { return }
                            Task {
                                await viewModel.createSpace(name: name, iconName: newSpaceIcon, storageMode: newSpaceMode)
                                newSpaceName = ""
                            }
                        }
                        .buttonStyle(ArcaPrimaryButtonStyle())
                        .disabled(newSpaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(18)
            }
            .background(ArcaTheme.canvasBackground(for: colorScheme))
        }
        .alert(item: $pendingSpaceDeletion) { space in
            Alert(
                title: Text(String(format: ArcaStrings.text("delete.spaceTitle", language: viewModel.language), space.name)),
                message: Text(ArcaStrings.text("delete.spaceBody", language: viewModel.language)),
                primaryButton: .destructive(Text(ArcaStrings.text("common.delete", language: viewModel.language))) {
                    Task { await viewModel.deleteSpace(id: space.id) }
                },
                secondaryButton: .cancel(Text(ArcaStrings.text("common.cancel", language: viewModel.language)))
            )
        }
    }

    private func modeChoicePill(_ mode: SpaceStorageMode, label: String, icon: String) -> some View {
        let selected = newSpaceMode == mode
        return Button {
            newSpaceMode = mode
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.footnote.weight(.semibold))
                Text(label)
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(selected ? .white : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(selected ? ArcaTheme.accent : ArcaTheme.subtleFieldBackground(for: colorScheme))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Screen 7: Template Gallery

@available(macOS 14.0, iOS 17.0, *)
public struct TemplateGallerySheetView: View {
    @Bindable var viewModel: ArcaAppViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @ViewState private var showingMedicalDisclosureAlert = false
    @ViewState private var pendingTemplate: StarterTemplate?
    @ViewState private var isSaving = false
    @ViewState private var saveError: String?

    private func creationText(_ key: String) -> String {
        ArcaStrings.text(key, language: viewModel.language)
    }

    public var body: some View {
        VStack(spacing: 0) {
            ArcaSheetHeaderBar(
                title: creationText("creation.templates"),
                subtitle: creationText("creation.templateSubtitle"),
                leadingLabel: isSaving ? nil : creationText("creation.close"),
                leadingAction: { dismiss() }
            )

            if let saveError {
                Label(saveError, systemImage: "exclamationmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(ArcaTheme.dangerRed)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .accessibilityIdentifier("templateGallery.error")
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    if let status = viewModel.catalogStatus {
                        ArcaSectionCard(title: creationText("creation.templateLibrary"), icon: "rectangle.stack") {
                            Text(viewModel.language.localized(status))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button(creationText("creation.retry")) {
                                Task { await viewModel.refreshSuggestedTemplates() }
                            }
                            .buttonStyle(ArcaSecondaryButtonStyle())
                        }
                    }
                    if viewModel.suggestedTemplates.isEmpty {
                        Text(creationText("creation.noTemplates"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if viewModel.catalogStatus == nil {
                            Button(creationText("creation.retry")) {
                                Task { await viewModel.refreshSuggestedTemplates() }
                            }
                            .buttonStyle(ArcaSecondaryButtonStyle())
                        }
                    }
                    ForEach(viewModel.suggestedTemplates) { template in
                        let tint = ArcaTheme.color(fromHex: template.colorHex)
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(tint)
                                        .frame(width: 42, height: 42)
                                    Image(systemName: template.iconName)
                                        .font(.headline.weight(.semibold))
                                        .foregroundStyle(.white)
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(template.name)
                                            .font(.body.weight(.bold))
                                        if template.sensitivityPosture == .elevatedLocalDefault {
                                            Text(viewModel.language.localized("Sensitive • Local Default"))
                                                .font(.caption2.weight(.bold))
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 3)
                                                .background(Capsule().fill(ArcaTheme.plumSensitive.opacity(0.15)))
                                                .foregroundStyle(ArcaTheme.plumSensitive)
                                        }
                                    }
                                    Text(template.subtitle)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }

                            if let disclosure = template.sensitivityDisclosure {
                                Text(disclosure)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(10)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(ArcaTheme.plumSensitive.opacity(0.08)))
                            }

                            Button {
                                if template.sensitivityPosture == .elevatedLocalDefault && viewModel.currentSpace?.storageMode != .localOnly {
                                    pendingTemplate = template
                                    showingMedicalDisclosureAlert = true
                                } else {
                                    saveTemplate(template, inDedicatedLocalSpace: false)
                                }
                            } label: {
                                if isSaving {
                                    ProgressView().tint(.white)
                                } else {
                                    Text(viewModel.language.format("Add %@", template.name))
                                }
                            }
                            .buttonStyle(ArcaPrimaryButtonStyle(tint: tint))
                            .disabled(isSaving)
                            .accessibilityIdentifier("templateGallery.add.\(template.id)")
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
                .padding(18)
            }
            .background(ArcaTheme.canvasBackground(for: colorScheme))
        }
        .environment(\.layoutDirection, viewModel.language.layoutDirection)
        .environment(\.locale, viewModel.language.locale)
        .interactiveDismissDisabled(isSaving)
        .task { await viewModel.refreshSuggestedTemplates() }
        .alert("Sensitive Collection Storage Choice", isPresented: $showingMedicalDisclosureAlert, presenting: pendingTemplate) { template in
            Button(viewModel.language.localized("Create in New Local-Only Space (Recommended)")) {
                saveTemplate(template, inDedicatedLocalSpace: true)
            }
            Button(viewModel.language.localized("Add to Current Space Anyway")) {
                saveTemplate(template, inDedicatedLocalSpace: false)
            }
            Button(viewModel.language.localized("Cancel"), role: .cancel) {}
        } message: { template in
            Text(template.sensitivityDisclosure ?? "This template is marked sensitive and defaults to Local-Only storage.")
        }
    }

    private func saveTemplate(_ template: StarterTemplate, inDedicatedLocalSpace: Bool) {
        guard !isSaving else { return }
        isSaving = true
        saveError = nil
        Task { @MainActor in
            defer { isSaving = false }
            do {
                try await viewModel.createCollectionFromTemplate(template, createDedicatedLocalSpaceIfSensitive: inDedicatedLocalSpace)
                dismiss()
            } catch {
                saveError = error.localizedDescription
            }
        }
    }

}

// MARK: - Screen 8: Manual Collection Builder

@available(macOS 14.0, iOS 17.0, *)
public struct ManualCollectionBuilderSheetView: View {
    @Bindable var viewModel: ArcaAppViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @ViewState private var name = ""
    @ViewState private var iconName = "list.clipboard"
    @ViewState private var draftFields: [FieldDefinition]

    public init(viewModel: ArcaAppViewModel) {
        self.viewModel = viewModel
        self._draftFields = ViewState(initialValue: [
            FieldDefinition(label: viewModel.language.localized("Title"), type: .shortText, isRequired: true, sortOrder: 0, isPrimaryTitle: true),
            FieldDefinition(label: viewModel.language.localized("Date"), type: .date, sortOrder: 1),
            FieldDefinition(label: viewModel.language.localized("Notes"), type: .longText, sortOrder: 2)
        ])
    }
    @ViewState private var newFieldLabel = ""
    @ViewState private var newFieldType: FieldType = .shortText
    @ViewState private var newFieldRequired = false
    @ViewState private var newSelectOptionsComma = ""

    private let icons = [(symbol: "list.clipboard", label: "Clipboard"), (symbol: "tag.fill", label: "Tag"), (symbol: "heart.fill", label: "Heart"), (symbol: "wrench.and.screwdriver.fill", label: "Tools"), (symbol: "book.fill", label: "Book")]

    public var body: some View {
        VStack(spacing: 0) {
            ArcaSheetHeaderBar(
                title: viewModel.language.localized("Custom Collection"),
                subtitle: viewModel.language.localized("Define Your Own Fields"),
                leadingLabel: viewModel.language.localized("Cancel"),
                leadingAction: { dismiss() },
                trailingLabel: "Create",
                trailingDisabled: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draftFields.isEmpty,
                trailingAction: {
                    Task {
                        await viewModel.createCustomCollection(name: name, iconName: iconName, fields: draftFields)
                        dismiss()
                    }
                }
            )

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    ArcaSectionCard(title: viewModel.language.localized("Collection Identity"), icon: "sparkles") {
                        ArcaStyledTextField(viewModel.language.localized("Collection Name (e.g., Appliances, Hobbies)"), text: $name, icon: "folder.fill")

                        HStack(spacing: 8) {
                            ForEach(icons, id: \.symbol) { item in
                                let ic = item.symbol
                                let selected = iconName == ic
                                Button {
                                    iconName = ic
                                } label: {
                                    Image(systemName: ic)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(selected ? .white : .primary)
                                        .frame(width: 44, height: 44)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(selected ? ArcaTheme.accent : ArcaTheme.subtleFieldBackground(for: colorScheme))
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(viewModel.language.localized(item.label))
                                .accessibilityAddTraits(selected ? .isSelected : [])
                            }
                        }
                    }

                    ArcaSectionCard(title: viewModel.language.localized("Defined Fields"), icon: "list.bullet.rectangle") {
                        VStack(spacing: 8) {
                            ForEach(draftFields) { field in
                                HStack(spacing: 10) {
                                    Image(systemName: field.type.iconName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(ArcaTheme.accent)
                                        .frame(width: 28, height: 28)
                                        .background(Circle().fill(ArcaTheme.accent.opacity(0.12)))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(field.label)
                                            .font(.subheadline.weight(.semibold))
                                        Text(ArcaStrings.text("field.type." + field.type.rawValue, language: viewModel.language) + (field.isRequired ? " • " + viewModel.language.localized("Required") : ""))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    if draftFields.count > 1 {
                                        Button {
                                            draftFields.removeAll { $0.id == field.id }
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.footnote.weight(.semibold))
                                                .foregroundStyle(ArcaTheme.dangerRed)
                                                .frame(minWidth: 44, minHeight: 44)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel(viewModel.language.format("Remove %@", field.label))
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

                    ArcaSectionCard(title: viewModel.language.localized("Add Another Field"), icon: "plus.circle.fill") {
                        ArcaStyledTextField(viewModel.language.localized("Field Label (e.g., Serial Number)"), text: $newFieldLabel, icon: "tag")

                        HStack {
                            Text(viewModel.language.localized("Field Type"))
                                .font(.footnote.weight(.medium))
                            Spacer()
                            Picker(viewModel.language.localized("Field Type"), selection: $newFieldType) {
                                ForEach(FieldType.allCases, id: \.self) { t in
                                    Text(ArcaStrings.text("field.type." + t.rawValue, language: viewModel.language)).tag(t)
                                }
                            }
                            .labelsHidden()
                        }

                        Toggle(viewModel.language.localized("Required Field"), isOn: $newFieldRequired)
                            .font(.footnote.weight(.medium))

                        if newFieldType == .singleSelect || newFieldType == .multiSelect {
                            ArcaStyledTextField(viewModel.language.localized("Choices (comma-separated, e.g., Active, Expired)"), text: $newSelectOptionsComma, icon: "list.bullet")
                        }

                        Button(viewModel.language.localized("Add Field to Collection")) {
                            let trimmed = newFieldLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            let opts: [SelectOption] = newSelectOptionsComma
                                .split(separator: ",")
                                .map { SelectOption(label: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                                .filter { !$0.label.isEmpty }
                            draftFields.append(FieldDefinition(
                                label: trimmed,
                                type: newFieldType,
                                isRequired: newFieldRequired,
                                sortOrder: draftFields.count,
                                options: opts,
                                isPrimaryTitle: draftFields.isEmpty
                            ))
                            newFieldLabel = ""
                            newSelectOptionsComma = ""
                            newFieldRequired = false
                        }
                        .buttonStyle(ArcaSecondaryButtonStyle(isFullWidth: true))
                        .disabled(newFieldLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(18)
            }
            .background(ArcaTheme.canvasBackground(for: colorScheme))
        }
    }
}
