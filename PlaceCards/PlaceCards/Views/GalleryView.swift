import SwiftUI

/// Which layout the "갤러리" tab renders its cards in — a segmented
/// toggle in the toolbar, not a Settings option, same reasoning as
/// `PlacesMapView`'s own map-provider picker: it's a per-visit display
/// choice, not something worth burying elsewhere. Persisted via
/// `@AppStorage` purely so it doesn't reset every time the tab is left
/// and revisited.
private enum GalleryLayout: String, CaseIterable, Identifiable {
    case grid, list

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .list: return "list.bullet"
        }
    }
}

struct GalleryView: View {
    @StateObject private var viewModel: GalleryViewModel
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var storageService: StorageService

    @AppStorage("galleryLayout") private var layoutRaw: String = GalleryLayout.grid.rawValue
    @State private var selectedCard: PlaceCard?
    @State private var cardPendingDelete: PlaceCard?
    @State private var isPresentingFindDuplicates = false

    /// Multi-select mode for bulk actions — mirrors `BoardDetailView`'s
    /// own `isSelecting`/`selectedIDs`/bulk action bar exactly, just
    /// scoped to whatever the grid is currently showing instead of one
    /// board's own list.
    @State private var isSelecting = false
    @State private var selectedIDs: Set<String> = []
    @State private var isConfirmingBulkDelete = false
    @State private var isPresentingMergeSelection = false
    @State private var isPresentingCustomCategoryInput = false
    @State private var customCategoryInput = ""

    /// The file `ShareLink`'s "파일로 공유" shares — a privacy-scrubbed
    /// export of whatever the grid currently shows, refreshed whenever
    /// that set changes. See `SharePlaces`.
    @State private var exportPlacesFileURL: URL?

    init(viewModel: GalleryViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    /// The board Home is currently showing, if any — used for the
    /// navigation title only; the actual filtering already happens
    /// inside `viewModel` via `boardScopeID`.
    private var scopedBoard: Board? {
        guard let boardScopeID = viewModel.boardScopeID else { return nil }
        return storageService.boards.first { $0.id == boardScopeID }
    }

    private var selectedCards: [PlaceCard] {
        viewModel.filteredPlaceCards.filter { selectedIDs.contains($0.id) }
    }

    private var layout: GalleryLayout {
        GalleryLayout(rawValue: layoutRaw) ?? .grid
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PlaceStatusFilterBar(
                    sortMode: $viewModel.sortMode,
                    distanceReference: $viewModel.distanceReference,
                    hereCoordinate: $viewModel.hereCoordinate,
                    referenceCandidates: viewModel.referenceCandidates,
                    categoryFilter: $viewModel.categoryFilter,
                    categories: viewModel.allCategories,
                    filter: $viewModel.statusFilter,
                    allCount: viewModel.totalCount,
                    favoriteCount: viewModel.favoriteCount,
                    visitedCount: viewModel.visitedCount
                )
                cardsContent
            }
            .safeAreaInset(edge: .bottom) {
                if isSelecting {
                    bulkActionBar
                }
            }
            .navigationTitle(scopedBoard.map { "갤러리 · ".localized + $0.name } ?? "갤러리".localized)
            // `.always` so search stays visible without a pull-down/
            // scroll — same as Home/BoardDetailView, since the only
            // intended difference between this screen and BoardDetailView
            // is grid vs. list.
            .searchable(text: $viewModel.searchQuery, placement: .navigationBarDrawer(displayMode: .always), prompt: "카드 검색".localized)
            // Home tab's board (if any) is only known once this tab
            // itself becomes visible — synced here rather than read once
            // at init, since the user may navigate around Home first and
            // only then switch to this tab.
            .onAppear { viewModel.boardScopeID = navigation.currentHomeBoardID }
            .onChange(of: navigation.currentHomeBoardID) { _, newValue in
                viewModel.boardScopeID = newValue
            }
            // One-shot: `HomeView`'s "카테고리별 보기" chips set this and
            // switch to this tab; consumed here (via `.onChange`, not
            // `.onAppear`, so merely revisiting this tab afterward doesn't
            // keep reapplying it once the user's cleared the filter) and
            // reset back to nil right away. See `AppNavigation
            // .showInGallery(category:)`.
            .onChange(of: navigation.galleryCategoryFilter) { _, newValue in
                guard let newValue else { return }
                viewModel.categoryFilter = newValue
                navigation.galleryCategoryFilter = nil
            }
            .toolbar { toolbarContent }
            .overlay {
                if viewModel.filteredPlaceCards.isEmpty {
                    ContentUnavailableView.search
                }
            }
            .task { refreshExportPlacesFile() }
            .onChange(of: viewModel.filteredPlaceCards.count) { _, _ in refreshExportPlacesFile() }
            .navigationDestination(item: $selectedCard) { card in
                PlaceCardDetailView(card: card)
            }
            .sheet(isPresented: $isPresentingFindDuplicates) {
                FindDuplicatesSheet(cards: viewModel.scopedCards)
            }
            .sheet(isPresented: $isPresentingMergeSelection, onDismiss: exitSelection) {
                FindDuplicatesSheet(manualGroup: selectedCards)
            }
            .confirmationDialog(
                deleteCardConfirmationTitle,
                isPresented: Binding(
                    get: { cardPendingDelete != nil },
                    set: { if !$0 { cardPendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("삭제".localized, role: .destructive) {
                    if let card = cardPendingDelete {
                        storageService.delete(card)
                    }
                    cardPendingDelete = nil
                }
                Button("취소".localized, role: .cancel) { cardPendingDelete = nil }
            }
            .confirmationDialog(
                bulkDeleteConfirmationTitle,
                isPresented: $isConfirmingBulkDelete,
                titleVisibility: .visible
            ) {
                Button(bulkDeleteConfirmationButtonTitle, role: .destructive) {
                    deleteSelected()
                }
                Button("취소".localized, role: .cancel) {}
            }
            .alert("카테고리 입력".localized, isPresented: $isPresentingCustomCategoryInput) {
                TextField("카테고리".localized, text: $customCategoryInput)
                Button("변경".localized) {
                    applyCategory(customCategoryInput)
                    customCategoryInput = ""
                }
                Button("취소".localized, role: .cancel) { customCategoryInput = "" }
            }
        }
    }

    private var deleteCardConfirmationTitle: String {
        "\"" + (cardPendingDelete?.name ?? "") + "\"을 삭제할까요?".localized
    }

    private var bulkDeleteConfirmationTitle: String {
        "\(selectedIDs.count)" + "개 장소를 삭제할까요?".localized
    }

    private var bulkDeleteConfirmationButtonTitle: String {
        "\(selectedIDs.count)" + "개 삭제".localized
    }

    /// Grid or list, per `layout` — same underlying `viewModel
    /// .filteredPlaceCards`, sort, filters, and selection either way, so
    /// switching layout never changes *what* is showing, only how it's
    /// arranged.
    @ViewBuilder
    private var cardsContent: some View {
        switch layout {
        case .grid:
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
                    ForEach(viewModel.filteredPlaceCards) { card in
                        gridCell(card)
                    }
                }
                .padding()
            }
        case .list:
            List {
                ForEach(viewModel.filteredPlaceCards) { card in
                    listRow(card)
                }
            }
            .listStyle(.plain)
        }
    }

    // Same reasoning as `BoardDetailView.cardRow(_:)`: no NavigationLink
    // wraps the cell — it would claim the whole cell as its tap target
    // and swallow taps on `PlaceCardGridCell`'s own favorite/visited/
    // call/map/website buttons. A plain `.onTapGesture` instead only
    // fires for points the cell's own buttons don't already claim.
    @ViewBuilder
    private func gridCell(_ card: PlaceCard) -> some View {
        PlaceCardGridCell(card: card, referenceCoordinate: viewModel.distanceReferenceCoordinate)
            .overlay(alignment: .topLeading) {
                if isSelecting {
                    Button {
                        toggleSelection(card)
                    } label: {
                        Image(systemName: selectedIDs.contains(card.id) ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(selectedIDs.contains(card.id) ? Color.accentColor : .white)
                            .shadow(radius: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if isSelecting {
                    toggleSelection(card)
                } else {
                    selectedCard = card
                }
            }
    }

    /// List-layout counterpart of `gridCell(_:)` — identical to
    /// `BoardDetailView.cardRow(_:)` (same left checkmark button while
    /// selecting, same tap/swipe handling), since list layout here is
    /// meant to be that exact same list, just reachable from this tab
    /// too.
    @ViewBuilder
    private func listRow(_ card: PlaceCard) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if isSelecting {
                Button {
                    toggleSelection(card)
                } label: {
                    Image(systemName: selectedIDs.contains(card.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selectedIDs.contains(card.id) ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
            PlaceCardListRow(card: card, referenceCoordinate: viewModel.distanceReferenceCoordinate)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelecting {
                toggleSelection(card)
            } else {
                selectedCard = card
            }
        }
        .swipeActions(edge: .trailing) {
            if !isSelecting {
                Button(role: .destructive) {
                    cardPendingDelete = card
                } label: {
                    Label("삭제".localized, systemImage: "trash")
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                layoutRaw = (layout == .grid ? GalleryLayout.list : .grid).rawValue
            } label: {
                Image(systemName: layout == .grid ? GalleryLayout.list.systemImage : GalleryLayout.grid.systemImage)
            }
        }
        if !isSelecting {
            if viewModel.scopedCards.count > 1 {
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        isPresentingFindDuplicates = true
                    } label: {
                        Label("중복 찾기".localized, systemImage: "arrow.triangle.merge")
                    }
                }
            }
            if !viewModel.filteredPlaceCards.isEmpty {
                ToolbarItem(placement: .secondaryAction) {
                    exportPlacesMenu
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("전체".localized) { viewModel.selectedTag = nil }
                    ForEach(viewModel.allTags, id: \.self) { tag in
                        Button(tag) { viewModel.selectedTag = tag }
                    }
                } label: {
                    Label("태그".localized, systemImage: "tag")
                }
            }
        }
        if !viewModel.scopedCards.isEmpty {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isSelecting.toggle()
                    if !isSelecting { selectedIDs.removeAll() }
                } label: {
                    Text(isSelecting ? "취소".localized : "선택".localized)
                }
            }
        }
    }

    /// "내보내기" — a privacy-scrubbed share of whatever the grid
    /// currently shows (see `SharePlaces`), matching `BoardDetailView`'s
    /// own toolbar Export menu exactly.
    @ViewBuilder
    private var exportPlacesMenu: some View {
        Menu {
            Button {
                copyPlacesAsText()
            } label: {
                Label("텍스트로 복사".localized, systemImage: "doc.on.doc")
            }
            if let exportPlacesFileURL {
                ShareLink(item: exportPlacesFileURL) {
                    Label("파일로 공유".localized, systemImage: "square.and.arrow.up")
                }
            }
        } label: {
            Label("내보내기".localized, systemImage: "square.and.arrow.up")
        }
    }

    private func refreshExportPlacesFile() {
        exportPlacesFileURL = SharePlaces.writeTempFile(SharePlaces.buildPayload(from: viewModel.filteredPlaceCards))
    }

    private func copyPlacesAsText() {
        guard let text = try? SharePlaces.toText(SharePlaces.buildPayload(from: viewModel.filteredPlaceCards)) else { return }
        UIPasteboard.general.string = text
    }

    /// The bulk action bar shown above the tab bar while `isSelecting` —
    /// identical set of actions to `BoardDetailView.bulkActionBarControls`,
    /// just against whatever the grid is currently showing rather than
    /// one board's own list ("게시판 이동" offers every board, since
    /// selected cards here aren't necessarily all from the same one).
    private var bulkActionBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(selectedIDs.isEmpty ? "수정할 장소를 선택하세요".localized : "\(selectedIDs.count)" + "개 선택됨".localized)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    bulkActionBarControls
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ViewBuilder
    private var bulkActionBarControls: some View {
        Button {
            toggleSelectAll()
        } label: {
            Text(selectedIDs.count == viewModel.filteredPlaceCards.count ? "전체 해제".localized : "전체 선택".localized)
                .font(.subheadline.weight(.medium))
        }
        .disabled(viewModel.filteredPlaceCards.isEmpty)

        Button(role: .destructive) {
            isConfirmingBulkDelete = true
        } label: {
            Label("삭제".localized, systemImage: "trash")
                .font(.subheadline.weight(.medium))
        }
        .disabled(selectedIDs.isEmpty)

        Menu {
            ForEach(viewModel.allCategories, id: \.self) { category in
                Button(category) { applyCategory(category) }
            }
            Button("직접 입력…".localized) { isPresentingCustomCategoryInput = true }
        } label: {
            Label("카테고리 변경".localized, systemImage: "tag")
                .font(.subheadline.weight(.medium))
        }
        .disabled(selectedIDs.isEmpty)

        if !storageService.boards.isEmpty {
            Menu {
                ForEach(storageService.boards) { board in
                    Button {
                        moveSelected(to: board)
                    } label: {
                        Label(board.name, systemImage: board.coverIcon)
                    }
                }
            } label: {
                Label("게시판 이동".localized, systemImage: "arrow.right.square")
                    .font(.subheadline.weight(.medium))
            }
            .disabled(selectedIDs.isEmpty)
        }

        Button {
            navigation.showOnMap(selectedIDs)
            exitSelection()
        } label: {
            Label("지도에서 보기".localized, systemImage: "map")
                .font(.subheadline.weight(.medium))
        }
        .disabled(selectedIDs.isEmpty)

        Button {
            isPresentingMergeSelection = true
        } label: {
            Label("병합".localized, systemImage: "arrow.triangle.merge")
                .font(.subheadline.weight(.medium))
        }
        .disabled(selectedIDs.count < 2)
    }

    private func toggleSelection(_ card: PlaceCard) {
        if selectedIDs.contains(card.id) {
            selectedIDs.remove(card.id)
        } else {
            selectedIDs.insert(card.id)
        }
    }

    /// Selects (or deselects) every card the current filters/search show
    /// — respects whatever's already narrowing `filteredPlaceCards`.
    private func toggleSelectAll() {
        if selectedIDs.count == viewModel.filteredPlaceCards.count {
            selectedIDs.removeAll()
        } else {
            selectedIDs = Set(viewModel.filteredPlaceCards.map(\.id))
        }
    }

    private func exitSelection() {
        selectedIDs.removeAll()
        isSelecting = false
    }

    private func applyCategory(_ category: String) {
        let trimmed = category.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        for id in selectedIDs {
            guard var card = storageService.placeCard(id: id) else { continue }
            card.category = trimmed
            storageService.save(card)
        }
        exitSelection()
    }

    private func moveSelected(to newBoard: Board) {
        for id in selectedIDs {
            guard var card = storageService.placeCard(id: id) else { continue }
            card.boardId = newBoard.id
            storageService.save(card)
        }
        exitSelection()
    }

    private func deleteSelected() {
        for id in selectedIDs {
            guard let card = storageService.placeCard(id: id) else { continue }
            storageService.delete(card)
        }
        exitSelection()
    }
}

/// Used only by the "갤러리" tab now — a board's own place list is a plain
/// `List` of `PlaceCardListRow`, not this grid (see `BoardDetailView`).
/// `GalleryView.gridCell(_:)` wraps this in a plain `.onTapGesture` rather
/// than a `NavigationLink`/`Button` (needed once selection mode added a
/// second tap meaning) — the star/visited/call/map/website/Instagram
/// controls below stay their own `.plain`-styled buttons, which still
/// claim their own taps ahead of that surrounding gesture. Favorite/
/// visited mirror Peragra's `PlaceRowView`, including being toggleable
/// right from here.
struct PlaceCardGridCell: View {
    let card: PlaceCard
    /// Set only while the grid is sorted by distance from a chosen
    /// reference — shown as a "250m"/"1.3km" label next to the address.
    var referenceCoordinate: Coordinates? = nil

    @EnvironmentObject private var storageService: StorageService
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.15))
                if let firstItem = card.media.officialPhotos.first ?? card.media.allItems.first,
                   let image = MediaStore.loadImage(fileName: firstItem.localPath) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                HStack(alignment: .top) {
                    if let category = card.category, !category.isEmpty {
                        Label {
                            Text(PlaceCategoryIcon.normalizedLabel(for: category))
                        } icon: {
                            Image(systemName: PlaceCategoryIcon.symbolName(for: category))
                        }
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.thinMaterial, in: Capsule())
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        Button(action: toggleVisited) {
                            Image(systemName: card.isVisited ? "checkmark.circle.fill" : "checkmark.circle")
                                .foregroundStyle(card.isVisited ? .green : .white)
                        }
                        Button(action: toggleFavorite) {
                            Image(systemName: card.isFavorite ? "star.fill" : "star")
                                .foregroundStyle(card.isFavorite ? .yellow : .white)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.callout)
                    .shadow(radius: 2)
                }
                .padding(6)
            }
            .frame(height: 120)
            .clipped()

            Text(card.name)
                .font(.subheadline.bold())
                .lineLimit(1)
            Text(card.address)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let distanceText = Coordinates.distanceText(from: referenceCoordinate, to: card.coordinates) {
                Text(distanceText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if card.hasAnyAction {
                HStack(spacing: 12) {
                    if let callURL = card.callURL {
                        Button { openURL(callURL) } label: {
                            Image(systemName: "phone")
                        }
                    }
                    if card.hasAnyMapLink {
                        Menu {
                            if GoogleMapsOpener.url(for: card) != nil {
                                Button("Google Maps") {
                                    MapOpenContext.recordMapOpen(cardID: card.id)
                                    GoogleMapsOpener.open(for: card, using: openURL)
                                }
                            }
                            if card.coordinates != nil {
                                Button("Apple 지도".localized) {
                                    MapOpenContext.recordMapOpen(cardID: card.id)
                                    AppleMapsOpener.open(for: card)
                                }
                            }
                            if let url = NaverMapOpener.url(for: card) {
                                Button("Naver Map") {
                                    MapOpenContext.recordMapOpen(cardID: card.id)
                                    openURL(url)
                                }
                            }
                            if let url = KakaoMapOpener.url(for: card) {
                                Button("Kakao Map") {
                                    MapOpenContext.recordMapOpen(cardID: card.id)
                                    openURL(url)
                                }
                            }
                            if let url = TmapOpener.url(for: card) {
                                Button("Tmap") {
                                    MapOpenContext.recordMapOpen(cardID: card.id)
                                    openURL(url)
                                }
                            }
                        } label: {
                            Image(systemName: "map")
                        }
                    }
                    if let website = card.website, let url = URL(string: website) {
                        Button { openURL(url) } label: {
                            Image(systemName: "link")
                        }
                    }
                    if let instagramURL = card.instagramURL, let url = URL(string: instagramURL) {
                        Button { openURL(url) } label: {
                            Image(systemName: "camera")
                                .foregroundStyle(.pink)
                        }
                    }
                }
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(Color.accentColor)
            }
        }
    }

    private func toggleFavorite() {
        var updated = card
        updated.isFavorite.toggle()
        storageService.save(updated)
    }

    private func toggleVisited() {
        var updated = card
        updated.isVisited.toggle()
        storageService.save(updated)
    }
}

#Preview {
    let storageService = StorageService()
    GalleryView(viewModel: GalleryViewModel(storageService: storageService))
        .environmentObject(storageService)
        .environmentObject(AppNavigation())
}
