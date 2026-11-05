import SwiftUI
import ArcaCore

// MARK: - Screen 5: Home with Space Switcher, Collections, Recent Records, and Global Search

@available(macOS 14.0, iOS 17.0, *)
public struct HomeScreenView: View {
    @Bindable var viewModel: ArcaAppViewModel

    @ViewState private var showingSpaceManager = false
    @ViewState private var showingSpacePicker = false
    @ViewState private var showingTemplateGallery = false
    @ViewState private var showingAIAssistant = false
    @ViewState private var showingManualBuilder = false
    @ViewState private var activeRecordSheetCollection: CollectionSchema?
    @ViewState private var viewingCollection: CollectionSchema?
    @ViewState private var editingSettingsCollection: CollectionSchema?
    @ViewState private var activeClusterCollectionId: UUID?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.arcaAppAccentColor) private var appAccentColor
    @Environment(\.arcaAppAccentOption) private var appAccentOption

    private var appForegroundTint: Color {
        appAccentOption.foregroundTint(for: colorScheme)
    }

    public init(viewModel: ArcaAppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    // Redesigned Space Header + Quick Space Switcher
                    homeHeaderBar

                    if showingSpacePicker {
                        inlineSpacePickerCard
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Operational state banner (offline, conflict, quota, etc.)
                    OperationalStateBannerView(state: viewModel.bannerState) {
                        viewModel.handleBannerAction()
                    }

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
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture().onEnded {
                        if activeClusterCollectionId != nil {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                                activeClusterCollectionId = nil
                            }
                        }
                    }
                )
            }
            .background(ArcaTheme.canvasBackground(for: colorScheme))
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .navigationDestination(item: $viewingCollection) { col in
                CollectionRecordListView(
                    viewModel: viewModel,
                    schema: viewModel.schema(for: col.id) ?? col
                )
            }
            .navigationDestination(item: $editingSettingsCollection) { col in
                CollectionSettingsView(
                    viewModel: viewModel,
                    schema: viewModel.schema(for: col.id) ?? col
                )
            }
            .sheet(isPresented: $showingSpaceManager) {
                ManageSpacesSheetView(viewModel: viewModel)
                    .arcaApplyAppAccentEnvironment()
                    .frame(minWidth: 370, idealWidth: 400, minHeight: 580, idealHeight: 680)
            }
            .sheet(isPresented: $showingAIAssistant) {
                AICollectionAssistantSheetView(viewModel: viewModel)
                    .arcaApplyAppAccentEnvironment()
                    .frame(minWidth: 370, idealWidth: 400, minHeight: 580, idealHeight: 680)
            }
            .sheet(isPresented: $showingTemplateGallery) {
                TemplateGallerySheetView(viewModel: viewModel)
                    .arcaApplyAppAccentEnvironment()
                    .frame(minWidth: 370, idealWidth: 400, minHeight: 580, idealHeight: 680)
            }
            .sheet(isPresented: $showingManualBuilder) {
                ManualCollectionBuilderSheetView(viewModel: viewModel)
                    .arcaApplyAppAccentEnvironment()
                    .frame(minWidth: 370, idealWidth: 400, minHeight: 580, idealHeight: 680)
            }
            .modifier(
                CollectionAddRecordPresenter(
                    viewModel: viewModel,
                    schema: $activeRecordSheetCollection
                )
            )
            .onChange(of: viewModel.currentSpaceId) { _, _ in
                activeClusterCollectionId = nil
                showingSpacePicker = false
            }
        }
        .arcaApplyAppAccentEnvironment()
    }

    private func creationText(_ key: String) -> String {
        ArcaStrings.text(key, language: viewModel.language)
    }

    private func storageModeSubtitle(for mode: SpaceStorageMode) -> String {
        switch mode {
        case .arcaSync:
            return viewModel.language.localized("Arca Sync (E2EE)")
        case .localOnly:
            return viewModel.language.localized("On This Device Only")
        case .personalCloudBackup:
            return viewModel.language.localized("Personal Cloud Backup")
        }
    }

    private var homeHeaderBar: some View {
        let current = viewModel.currentSpace
        let spaceName = current?.name ?? ArcaStrings.text("app.name", language: viewModel.language)
        let spaceIcon = current?.iconName ?? "house.fill"
        let collectionCountText = viewModel.language.format("count.collections", viewModel.collectionsInCurrentSpace.count)
        let storageText = current.map { storageModeSubtitle(for: $0.storageMode) } ?? ""
        let subtitleText = storageText.isEmpty ? collectionCountText : "\(collectionCountText) · \(storageText)"

        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    spaceHeaderSelectorButton(
                        spaceName: spaceName,
                        spaceIcon: spaceIcon,
                        subtitleText: subtitleText
                    )
                    spacesTrailingButton
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    spaceHeaderSelectorButton(
                        spaceName: spaceName,
                        spaceIcon: spaceIcon,
                        subtitleText: subtitleText
                    )

                    Spacer(minLength: 8)

                    spacesTrailingButton
                }
            }
        }
    }

    private func spaceHeaderSelectorButton(
        spaceName: String,
        spaceIcon: String,
        subtitleText: String
    ) -> some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                activeClusterCollectionId = nil
                showingSpacePicker.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(appAccentColor)
                        .frame(width: 44, height: 44)
                        .shadow(color: appAccentColor.opacity(0.24), radius: 7, x: 0, y: 4)
                    Image(systemName: spaceIcon)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(spaceName)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Image(systemName: showingSpacePicker ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }

                    Text(subtitleText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(spaceName), \(subtitleText)")
        .accessibilityHint(viewModel.language.localized("Switch Space"))
        .accessibilityIdentifier("home.spaceSelector")
    }

    private var spacesTrailingButton: some View {
        Button {
            activeClusterCollectionId = nil
            showingSpacePicker = false
            showingSpaceManager = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.stack")
                    .font(.footnote.weight(.semibold))
                Text(viewModel.language.localized("Spaces"))
                    .font(.footnote.weight(.bold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(minHeight: 40)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(ArcaTheme.cardBackground(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(ArcaTheme.cardBorder(for: colorScheme), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.16 : 0.03), radius: 5, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.spacesButton")
    }

    private var inlineSpacePickerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(viewModel.spaces) { space in
                inlineSpacePickerRow(for: space)
            }

            Divider()
                .padding(.vertical, 4)

            Button {
                showingSpacePicker = false
                showingSpaceManager = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.rectangle.on.folder")
                        .font(.footnote.weight(.semibold))
                    Text(viewModel.language.localized("Manage Spaces…"))
                        .font(.footnote.weight(.bold))
                    Spacer()
                    Image(systemName: "chevron.forward")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(appForegroundTint)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(minHeight: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(ArcaTheme.dropdownBackground(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(ArcaTheme.dropdownBorder(for: colorScheme), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.10), radius: 16, x: 0, y: 8)
    }

    private func inlineSpacePickerRow(for space: SpaceMetadata) -> some View {
        let isSelected = space.id == viewModel.currentSpaceId
        let count = (viewModel.collectionsBySpace[space.id] ?? []).filter { !$0.isDeleted }.count
        let modeLabel = storageModeSubtitle(for: space.storageMode)
        let subtitle = "\(viewModel.language.format("count.collections", count)) · \(modeLabel)"

        return Button {
            Task {
                await viewModel.selectSpace(space.id)
                showingSpacePicker = false
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? appAccentColor : ArcaTheme.subtleFieldBackground(for: colorScheme))
                        .frame(width: 38, height: 38)
                    Image(systemName: space.iconName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? .white : .primary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(space.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Text(viewModel.language.localized("Current"))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(appForegroundTint)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(appAccentColor.opacity(colorScheme == .dark ? 0.24 : 0.12)))
                }
            }
            .padding(10)
            .frame(minHeight: 54)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? appAccentColor.opacity(colorScheme == .dark ? 0.18 : 0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
                    Label(ArcaStrings.text("home.newCollection", language: viewModel.language), systemImage: "plus")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(appForegroundTint)
                }
                .buttonStyle(.plain)
            }

            if viewModel.collectionsInCurrentSpace.isEmpty {
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(appAccentColor.opacity(0.12))
                            .frame(width: 56, height: 56)
                        Image(systemName: "sparkles")
                            .font(.title)
                            .foregroundStyle(appForegroundTint)
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
                    .buttonStyle(ArcaPrimaryButtonStyle(tint: appAccentColor))
                    HStack(spacing: 18) {
                        Button(creationText("creation.templates")) { showingTemplateGallery = true }
                        Button(creationText("creation.manual")) { showingManualBuilder = true }
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(appForegroundTint)
                    .buttonStyle(.plain)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(ArcaTheme.cardBackground(for: colorScheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(ArcaTheme.cardBorder(for: colorScheme), lineWidth: 1)
                )
            } else {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: 12),
                        count: dynamicTypeSize.isAccessibilitySize ? 1 : 2
                    ),
                    spacing: 12
                ) {
                    ForEach(viewModel.collectionsInCurrentSpace) { col in
                        collectionGridCell(col)
                    }

                    newCollectionGridTile
                }
            }
        }
    }

    private func collectionGridCell(_ col: CollectionSchema) -> some View {
        let isClusterOpen = activeClusterCollectionId == col.id
        let count = viewModel.recordCount(for: col.id)
        let fieldCountText = viewModel.language.format("count.fields", col.activeFields.count)

        return ZStack {
            if isClusterOpen {
                collectionCardVisual(col, count: count, fieldCountText: fieldCountText)
                    .accessibilityHidden(true)

                collectionActionClusterOverlay(col)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                        showingSpacePicker = false
                        activeClusterCollectionId = col.id
                    }
                } label: {
                    collectionCardVisual(col, count: count, fieldCountText: fieldCountText)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(col.name), \(count), \(fieldCountText)")
                .accessibilityHint(viewModel.language.localized("Opens Add, View, and Edit actions"))
                .accessibilityAction(named: Text(viewModel.language.format("View %@", col.name))) {
                    viewingCollection = col
                }
                .accessibilityAction(named: Text(viewModel.language.format("Add Record to %@", col.name))) {
                    activeRecordSheetCollection = col
                }
                .accessibilityAction(named: Text(viewModel.language.format("Edit %@", col.name))) {
                    editingSettingsCollection = col
                }
                .accessibilityIdentifier("home.collection.\(col.id.uuidString)")
            }
        }
    }

    private func collectionCardVisual(_ col: CollectionSchema, count: Int, fieldCountText: String) -> some View {
        let tint = ArcaTheme.color(fromHex: col.colorHex)

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                CollectionBadgeView(schema: col, size: 44)

                Spacer()

                Text("\(count)")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(ArcaTheme.subtleFieldBackground(for: colorScheme))
                    )
            }

            Spacer(minLength: 4)

            VStack(alignment: .leading, spacing: 3) {
                Text(col.name)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(fieldCountText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 146, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(ArcaTheme.cardBackground(for: colorScheme))
        )
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 4,
                bottomTrailingRadius: 4,
                topTrailingRadius: 0,
                style: .continuous
            )
            .fill(tint)
            .frame(height: 4)
            .padding(.horizontal, 16)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(ArcaTheme.cardBorder(for: colorScheme), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.20 : 0.03), radius: 8, x: 0, y: 4)
    }

    private func collectionActionClusterOverlay(_ col: CollectionSchema) -> some View {
        let tint = ArcaTheme.color(fromHex: col.colorHex)

        return ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(red: 0.055, green: 0.082, blue: 0.071).opacity(colorScheme == .dark ? 0.92 : 0.86))
                .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .onTapGesture {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                        activeClusterCollectionId = nil
                    }
                }
                .accessibilityHidden(true)

            HStack(spacing: 10) {
                // 1. Add Record Orb
                Button {
                    activeClusterCollectionId = nil
                    activeRecordSheetCollection = col
                } label: {
                    VStack(spacing: 5) {
                        ZStack {
                            Circle()
                                .fill(tint)
                                .frame(width: 44, height: 44)
                                .shadow(color: Color.black.opacity(0.28), radius: 6, x: 0, y: 3)
                            Image(systemName: "plus")
                                .font(.callout.weight(.bold))
                                .foregroundStyle(.white)
                        }
                        Text(viewModel.language.localized("Add"))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .frame(minWidth: 44, minHeight: 62)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(viewModel.language.format("Add Record to %@", col.name))
                .accessibilityIdentifier("home.collection.\(col.id.uuidString).add")

                // 2. View Records Orb
                Button {
                    activeClusterCollectionId = nil
                    viewingCollection = col
                } label: {
                    VStack(spacing: 5) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.14))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Circle().strokeBorder(Color.white.opacity(0.24), lineWidth: 1)
                                )
                            Image(systemName: "arrow.up.forward")
                                .font(.callout.weight(.bold))
                                .foregroundStyle(.white)
                        }
                        Text(viewModel.language.localized("View"))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .frame(minWidth: 44, minHeight: 62)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(viewModel.language.format("View %@", col.name))
                .accessibilityIdentifier("home.collection.\(col.id.uuidString).view")

                // 3. Edit Collection Settings Orb
                Button {
                    activeClusterCollectionId = nil
                    editingSettingsCollection = col
                } label: {
                    VStack(spacing: 5) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.14))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Circle().strokeBorder(Color.white.opacity(0.24), lineWidth: 1)
                                )
                            Image(systemName: "slider.horizontal.3")
                                .font(.callout.weight(.bold))
                                .foregroundStyle(.white)
                        }
                        Text(viewModel.language.localized("Edit"))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .frame(minWidth: 44, minHeight: 62)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(viewModel.language.format("Edit %@", col.name))
                .accessibilityIdentifier("home.collection.\(col.id.uuidString).edit")
            }
            .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity, minHeight: 146)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text(ArcaStrings.text("creation.close", language: viewModel.language))) {
            activeClusterCollectionId = nil
        }
    }

    private var newCollectionGridTile: some View {
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
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(ArcaTheme.subtleFieldBackground(for: colorScheme))
                        .frame(width: 44, height: 44)
                    Image(systemName: "plus")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 3) {
                    Text(ArcaStrings.text("home.newCollection", language: viewModel.language))
                        .font(.callout.weight(.bold))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text(viewModel.language.localized("AI, Starter or Custom"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 146)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                    )
                    .foregroundStyle(ArcaTheme.dropdownBorder(for: colorScheme))
            )
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ArcaStrings.text("home.newCollection", language: viewModel.language)), \(viewModel.language.localized("AI, Starter or Custom"))")
        .accessibilityAction(named: Text(creationText("creation.aiMenu"))) {
            showingAIAssistant = true
        }
        .accessibilityAction(named: Text(creationText("creation.templatesMenu"))) {
            showingTemplateGallery = true
        }
        .accessibilityAction(named: Text(creationText("creation.manualMenu"))) {
            showingManualBuilder = true
        }
        .accessibilityIdentifier("home.newCollectionTile")
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
    @Environment(\.arcaAppAccentOption) private var appAccentOption

    private var appForegroundTint: Color {
        appAccentOption.foregroundTint(for: colorScheme)
    }

    public init(record: RecordItem, schema: CollectionSchema, locale: Locale = .current) {
        self.record = record
        self.schema = schema
        self.locale = locale
    }

    public var body: some View {
        let tint = ArcaTheme.color(fromHex: schema.colorHex)
        HStack(spacing: 13) {
            CollectionBadgeView(schema: schema, size: 40)

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
                            .foregroundStyle(appForegroundTint)
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
    @Environment(\.arcaAppAccentColor) private var appAccentColor
    @Environment(\.arcaAppAccentOption) private var appAccentOption

    private var appForegroundTint: Color {
        appAccentOption.foregroundTint(for: colorScheme)
    }

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
                                manageSpaceRow(for: space)
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
                                                    .fill(selected ? appAccentColor : ArcaTheme.subtleFieldBackground(for: colorScheme))
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
        .arcaApplyAppAccentEnvironment()
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

    private func manageSpaceRow(for space: SpaceMetadata) -> some View {
        let isActive = space.id == viewModel.currentSpaceId
        let count = (viewModel.collectionsBySpace[space.id] ?? []).filter { !$0.isDeleted }.count
        let storageLabel = space.storageMode == .arcaSync
            ? viewModel.language.localized("Arca Sync (E2EE)")
            : (space.storageMode == .localOnly
                ? viewModel.language.localized("On This Device Only")
                : viewModel.language.localized("Personal Cloud Backup"))
        let subtitle = "\(viewModel.language.format("count.collections", count)) · \(storageLabel)"

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isActive ? appAccentColor : ArcaTheme.subtleFieldBackground(for: colorScheme))
                    .frame(width: 38, height: 38)
                Image(systemName: space.iconName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isActive ? .white : .primary)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(space.name)
                        .font(.body.weight(.bold))
                    if isActive {
                        Text(viewModel.language.localized("Current"))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(appAccentColor))
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !isActive {
                ArcaPillActionButton(viewModel.language.localized("Switch"), tint: appAccentColor) {
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
                    .fill(selected ? appAccentColor : ArcaTheme.subtleFieldBackground(for: colorScheme))
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
    @Environment(\.arcaAppAccentColor) private var appAccentColor
    @Environment(\.arcaAppAccentOption) private var appAccentOption

    private var appForegroundTint: Color {
        appAccentOption.foregroundTint(for: colorScheme)
    }

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
                                                .fill(selected ? appAccentColor : ArcaTheme.subtleFieldBackground(for: colorScheme))
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
                                        .foregroundStyle(appForegroundTint)
                                        .frame(width: 28, height: 28)
                                        .background(Circle().fill(appAccentColor.opacity(0.12)))

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
        .arcaApplyAppAccentEnvironment()
    }
}
