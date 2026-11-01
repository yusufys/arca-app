import SwiftUI
import ArcaCore

// MARK: - Screen 5: Home with Space Switcher, Collections, Recent Records, and Global Search

@available(macOS 14.0, iOS 17.0, *)
public struct HomeScreenView: View {
    @Bindable var viewModel: ArcaAppViewModel

    @ViewState private var showingSpaceManager = false
    @ViewState private var showingTemplateGallery = false
    @ViewState private var showingManualBuilder = false
    @ViewState private var activeRecordSheetCollection: CollectionSchema?
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

    private var homeHeaderBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                if let current = viewModel.currentSpace {
                    storageModePill(for: current.storageMode)
                }
                Text(viewModel.currentSpace?.name ?? ArcaStrings.text("app.name", language: viewModel.language))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
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
                                .font(.system(size: 12, weight: .bold))
                            Text(ArcaStrings.text("home.quickAddRecord", language: viewModel.language))
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
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
                        showingTemplateGallery = true
                    } label: {
                        Label("New Collection from Template…", systemImage: "sparkles.rectangle.stack")
                    }
                    Button {
                        showingManualBuilder = true
                    } label: {
                        Label("Build Custom Collection…", systemImage: "slider.horizontal.3")
                    }
                    Divider()
                    Button {
                        showingSpaceManager = true
                    } label: {
                        Label("Manage Spaces…", systemImage: "rectangle.stack.fill")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.system(size: 24))
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
                                .font(.system(size: 12, weight: .semibold))
                            Text(space.name)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                            if space.storageMode == .localOnly {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 10))
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
                            .font(.system(size: 11, weight: .semibold))
                        Text("Spaces")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
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
                .font(.system(size: 10, weight: .bold))
            Text(mode == .arcaSync ? "ARCA SYNC • E2EE" : (isLocal ? "ON THIS DEVICE ONLY" : "PERSONAL CLOUD BACKUP"))
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.4)
        }
        .foregroundStyle(tint)
    }

    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(ArcaStrings.text("home.collections", language: viewModel.language).uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 10) {
                    Button {
                        showingTemplateGallery = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                            Text("Templates")
                        }
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(ArcaTheme.accent)
                    }
                    .buttonStyle(.plain)

                    Button {
                        showingManualBuilder = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                            Text("Custom")
                        }
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(ArcaTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            if viewModel.collectionsInCurrentSpace.isEmpty {
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(ArcaTheme.accent.opacity(0.10))
                            .frame(width: 56, height: 56)
                        Image(systemName: "tray.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(ArcaTheme.accent)
                    }
                    Text("No Collections in This Space Yet")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("Start with a ready-made template for Vehicle Maintenance, Warranties, Home Inventory, or Medical Visits—or build custom fields.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 10) {
                        Button("Use a Template") { showingTemplateGallery = true }
                            .buttonStyle(ArcaPrimaryButtonStyle(isFullWidth: false))
                        Button("Build Custom") { showingManualBuilder = true }
                            .buttonStyle(ArcaSecondaryButtonStyle())
                    }
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
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
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
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }

                Spacer()

                Text("\(count)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(tint.opacity(0.12)))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(col.name)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("\(col.activeFields.count) fields • v\(col.schemaVersion)")
                    .font(.system(size: 11, weight: .medium))
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
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(ArcaTheme.warmAmber)
                Text(ArcaStrings.text("home.favorites", language: viewModel.language).uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
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
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(.secondary)

            if viewModel.recentRecordsInCurrentSpace.isEmpty {
                Text("Saved records will appear here for instant retrieval.")
                    .font(.system(size: 13))
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
            Text("SEARCH RESULTS (\(matches.count))")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(.secondary)

            if matches.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("No matching records found for “\(viewModel.globalSearchText)”")
                        .font(.system(size: 14, weight: .medium))
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
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(record.title(using: schema))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if record.isFavorite {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(ArcaTheme.warmAmber)
                    }
                    if !record.allAttachments.isEmpty {
                        Image(systemName: "paperclip")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ArcaTheme.accent)
                    }
                }

                let sub = record.subtitle(using: schema, locale: locale)
                HStack(spacing: 6) {
                    Text(schema.name)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(tint.opacity(0.10)))

                    if !sub.isEmpty {
                        Text(sub)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.forward")
                .font(.system(size: 12, weight: .bold))
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

    private let availableIcons: [(label: String, icon: String)] = [
        ("Folder", "folder.fill"),
        ("Home", "house.fill"),
        ("Vehicle", "car.fill"),
        ("Health", "cross.case.fill"),
        ("Work", "briefcase.fill")
    ]

    public var body: some View {
        VStack(spacing: 0) {
            ArcaSheetHeaderBar(
                title: "Spaces",
                subtitle: "Independent Local SQLite Databases",
                leadingLabel: "Done",
                leadingAction: { dismiss() }
            )

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    ArcaSectionCard(title: "Your Spaces (\(viewModel.spaces.count))", icon: "rectangle.stack.fill") {
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
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(tint)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(space.name)
                                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                            if isActive {
                                                Text("ACTIVE")
                                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                                    .foregroundStyle(.white)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Capsule().fill(ArcaTheme.accent))
                                            }
                                        }
                                        Text(space.storageMode == .arcaSync ? "Arca Sync (E2EE)" : (space.storageMode == .localOnly ? "On This Device Only" : "Personal Cloud Backup"))
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    if !isActive {
                                        ArcaPillActionButton("Switch", tint: ArcaTheme.accent) {
                                            Task {
                                                await viewModel.selectSpace(space.id)
                                                dismiss()
                                            }
                                        }
                                    }

                                    Menu {
                                        Button("Rename Space…") {
                                            renamingSpace = space
                                            renameText = space.name
                                        }
                                        if viewModel.spaces.count > 1 {
                                            Button("Delete Space", role: .destructive) {
                                                Task { await viewModel.deleteSpace(id: space.id) }
                                            }
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis.circle.fill")
                                            .font(.system(size: 20))
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
                        ArcaSectionCard(title: "Rename “\(spaceToRename.name)”", icon: "pencil") {
                            ArcaStyledTextField("New Space Name", text: $renameText, icon: "character.cursor.ibeam")
                            HStack(spacing: 10) {
                                Button("Cancel") { renamingSpace = nil }
                                    .buttonStyle(ArcaSecondaryButtonStyle(tint: .secondary))
                                Button("Save Name") {
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
                        title: "Create New Independent Space",
                        subtitle: "Each Space is stored in its own isolated SQLite database with independent storage and backup settings.",
                        icon: "plus.rectangle.on.folder.fill"
                    ) {
                        ArcaStyledTextField("Space Name (e.g., Vacation Cabin, Classic Car)", text: $newSpaceName, icon: "folder.badge.plus")

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Storage Mode")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)

                            HStack(spacing: 8) {
                                modeChoicePill(.localOnly, label: "Local Only", icon: "iphone")
                                modeChoicePill(.arcaSync, label: "Arca Sync (E2EE)", icon: "icloud.fill")
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Space Icon")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)

                            HStack(spacing: 8) {
                                ForEach(availableIcons, id: \.icon) { item in
                                    let selected = newSpaceIcon == item.icon
                                    Button {
                                        newSpaceIcon = item.icon
                                    } label: {
                                        Image(systemName: item.icon)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(selected ? .white : .primary)
                                            .frame(width: 40, height: 38)
                                            .background(
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .fill(selected ? ArcaTheme.accent : ArcaTheme.subtleFieldBackground(for: colorScheme))
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        Button("Create Space") {
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
    }

    private func modeChoicePill(_ mode: SpaceStorageMode, label: String, icon: String) -> some View {
        let selected = newSpaceMode == mode
        return Button {
            newSpaceMode = mode
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
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
    @ViewState private var showingChatGPTImport = false
    @ViewState private var pastedJSON = ""
    @ViewState private var importError: String?

    public var body: some View {
        VStack(spacing: 0) {
            ArcaSheetHeaderBar(
                title: "Starter Templates",
                subtitle: "Ready-Made Collections",
                leadingLabel: "Close",
                leadingAction: { dismiss() }
            )

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(StarterTemplateCatalog.all) { template in
                        let tint = ArcaTheme.color(fromHex: template.colorHex)
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(tint)
                                        .frame(width: 42, height: 42)
                                    Image(systemName: template.iconName)
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(.white)
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(template.name)
                                            .font(.system(size: 16, weight: .bold, design: .rounded))
                                        if template.sensitivityPosture == .elevatedLocalDefault {
                                            Text("Sensitive • Local Default")
                                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 3)
                                                .background(Capsule().fill(ArcaTheme.plumSensitive.opacity(0.15)))
                                                .foregroundStyle(ArcaTheme.plumSensitive)
                                        }
                                    }
                                    Text(template.subtitle)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }

                            if let disclosure = template.sensitivityDisclosure {
                                Text(disclosure)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .padding(10)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(ArcaTheme.plumSensitive.opacity(0.08)))
                            }

                            Button {
                                if template.sensitivityPosture == .elevatedLocalDefault && viewModel.currentSpace?.storageMode != .localOnly {
                                    pendingTemplate = template
                                    showingMedicalDisclosureAlert = true
                                } else {
                                    Task {
                                        await viewModel.createCollectionFromTemplate(template, createDedicatedLocalSpaceIfSensitive: false)
                                        dismiss()
                                    }
                                }
                            } label: {
                                Text("Add \(template.name)")
                            }
                            .buttonStyle(ArcaPrimaryButtonStyle(tint: tint))
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

                    // Optional capability: ChatGPT-assisted schema prompt + validated JSON import
                    ArcaSectionCard(
                        title: "AI-Assisted Schema Import",
                        subtitle: "Copy a structured prompt for ChatGPT/Claude, then paste the returned JSON below. Arca validates every field before creating the collection.",
                        icon: "sparkles"
                    ) {
                        Button {
                            withAnimation { showingChatGPTImport.toggle() }
                        } label: {
                            HStack {
                                Text(showingChatGPTImport ? "Hide JSON Schema Importer" : "Open Prompt & JSON Importer")
                                Spacer()
                                Image(systemName: showingChatGPTImport ? "chevron.up" : "chevron.down")
                            }
                        }
                        .buttonStyle(ArcaSecondaryButtonStyle(isFullWidth: true))

                        if showingChatGPTImport {
                            Text(OptionalCapabilityEngine.chatGPTSchemaPrompt(forTopic: "Home Wine Cellar"))
                                .font(.system(size: 11, design: .monospaced))
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 10).fill(ArcaTheme.subtleFieldBackground(for: colorScheme)))

                            TextEditor(text: $pastedJSON)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(height: 90)
                                .padding(6)
                                .background(RoundedRectangle(cornerRadius: 10).fill(ArcaTheme.subtleFieldBackground(for: colorScheme)))

                            if let importError {
                                Text(importError)
                                    .font(.caption)
                                    .foregroundStyle(ArcaTheme.dangerRed)
                            }

                            Button("Validate & Import Schema") {
                                do {
                                    try viewModel.importCollectionSchemaFromJSON(pastedJSON)
                                    dismiss()
                                } catch {
                                    importError = error.localizedDescription
                                }
                            }
                            .buttonStyle(ArcaPrimaryButtonStyle())
                        }
                    }
                }
                .padding(18)
            }
            .background(ArcaTheme.canvasBackground(for: colorScheme))
        }
        .alert("Sensitive Collection Storage Choice", isPresented: $showingMedicalDisclosureAlert, presenting: pendingTemplate) { template in
            Button("Create in New Local-Only Space (Recommended)") {
                Task {
                    await viewModel.createCollectionFromTemplate(template, createDedicatedLocalSpaceIfSensitive: true)
                    dismiss()
                }
            }
            Button("Add to Current Space Anyway") {
                Task {
                    await viewModel.createCollectionFromTemplate(template, createDedicatedLocalSpaceIfSensitive: false)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { template in
            Text(template.sensitivityDisclosure ?? "This template is marked sensitive and defaults to Local-Only storage.")
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
    @ViewState private var draftFields: [FieldDefinition] = [
        FieldDefinition(label: "Title", type: .shortText, isRequired: true, sortOrder: 0, isPrimaryTitle: true),
        FieldDefinition(label: "Date", type: .date, isRequired: false, sortOrder: 1),
        FieldDefinition(label: "Notes", type: .longText, isRequired: false, sortOrder: 2)
    ]
    @ViewState private var newFieldLabel = ""
    @ViewState private var newFieldType: FieldType = .shortText
    @ViewState private var newFieldRequired = false
    @ViewState private var newSelectOptionsComma = ""

    private let icons = ["list.clipboard", "tag.fill", "heart.fill", "wrench.and.screwdriver.fill", "book.fill"]

    public var body: some View {
        VStack(spacing: 0) {
            ArcaSheetHeaderBar(
                title: "Custom Collection",
                subtitle: "Define Your Own Fields",
                leadingLabel: "Cancel",
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
                    ArcaSectionCard(title: "Collection Identity", icon: "sparkles") {
                        ArcaStyledTextField("Collection Name (e.g., Pet Vet Records, Appliances)", text: $name, icon: "folder.fill")

                        HStack(spacing: 8) {
                            ForEach(icons, id: \.self) { ic in
                                let selected = iconName == ic
                                Button {
                                    iconName = ic
                                } label: {
                                    Image(systemName: ic)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(selected ? .white : .primary)
                                        .frame(width: 40, height: 38)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(selected ? ArcaTheme.accent : ArcaTheme.subtleFieldBackground(for: colorScheme))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    ArcaSectionCard(title: "Defined Fields (\(draftFields.count))", icon: "list.bullet.rectangle") {
                        VStack(spacing: 8) {
                            ForEach(draftFields) { field in
                                HStack(spacing: 10) {
                                    Image(systemName: field.type.iconName)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(ArcaTheme.accent)
                                        .frame(width: 28, height: 28)
                                        .background(Circle().fill(ArcaTheme.accent.opacity(0.12)))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(field.label)
                                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        Text("\(field.type.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)\(field.isRequired ? " • Required" : "")")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    if draftFields.count > 1 {
                                        Button {
                                            draftFields.removeAll { $0.id == field.id }
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundStyle(ArcaTheme.dangerRed)
                                                .padding(6)
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

                    ArcaSectionCard(title: "Add Another Field", icon: "plus.circle.fill") {
                        ArcaStyledTextField("Field Label (e.g., Serial Number, Vet Clinic)", text: $newFieldLabel, icon: "tag")

                        HStack {
                            Text("Field Type")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Picker("Field Type", selection: $newFieldType) {
                                ForEach(FieldType.allCases, id: \.self) { t in
                                    Text(t.rawValue.replacingOccurrences(of: "_", with: " ").capitalized).tag(t)
                                }
                            }
                            .labelsHidden()
                        }

                        Toggle("Required Field", isOn: $newFieldRequired)
                            .font(.system(size: 13, weight: .medium))

                        if newFieldType == .singleSelect || newFieldType == .multiSelect {
                            ArcaStyledTextField("Choices (comma-separated, e.g., Active, Expired)", text: $newSelectOptionsComma, icon: "list.bullet")
                        }

                        Button("Add Field to Collection") {
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
