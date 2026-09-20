import Foundation
import SwiftUI

/// Which layout the "갤러리" tab renders its cards in — a segmented
/// toggle in the toolbar, not a Settings option, same reasoning as
/// `PlacesMapView`'s own map-provider picker: it's a per-visit display
/// choice, not something worth burying elsewhere. Persisted via
/// `@AppStorage` purely so it doesn't reset every time the tab is left
/// and revisited — 그리고 범위(보드·모든 카드·가져오기)마다 따로
/// 기억한다. `GalleryView.layoutByScopeRaw`를 볼 것.
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

/// The "장소 추가" flow, as one `.sheet(item:)` rather than two separate
/// `.sheet` modifiers — `MainTabView`'s own doc comment records that piling
/// several `.sheet`s onto one view is a well-known way to get sheets that
/// silently don't present, and `GalleryView` already carries three.
private enum AddCardStep: Identifiable {
    /// More than one board and none currently in scope, so ask first.
    case pickBoard
    /// The board is settled; this is the actual add screen.
    case add(boardID: String)

    var id: String {
        switch self {
        case .pickBoard: return "pick"
        case .add(let boardID): return "add-\(boardID)"
        }
    }
}

struct GalleryView: View {
    @StateObject private var viewModel: GalleryViewModel
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var storageService: StorageService

    /// 범위마다 격자/목록을 따로 기억한다. 사진이 중요한 보드와 주소가
    /// 중요한 보드가 따로 있어서, 전역 설정 하나이던 때는 보드를 옮길
    /// 때마다 다시 바꿔야 했다.
    ///
    /// 사전 하나를 JSON 문자열로 담는다. `@AppStorage`는 키가 고정이라
    /// 범위마다 다른 키를 쓸 수 없고, `UserDefaults`를 직접 읽으면 값이
    /// 바뀌어도 화면이 다시 그려지지 않는다.
    @AppStorage("galleryLayoutByScope") private var layoutByScopeRaw: String = "{}"

    /// 범위별 값이 생기기 전에 쓰던 전역 설정. 아직 지우지 않는다 —
    /// 범위에 저장된 값이 없을 때 기본으로 삼아, 목록으로 보던 사람이
    /// 이 변경 뒤에 갑자기 격자로 되돌아가지 않게 한다.
    @AppStorage("galleryLayout") private var legacyLayoutRaw: String = GalleryLayout.grid.rawValue
    @State private var selectedCard: PlaceCard?
    @State private var cardPendingDelete: PlaceCard?
    @State private var isPresentingFindDuplicates = false
    /// Where the "장소 추가" flow currently is. A new card needs a
    /// `boardId`, which used to mean the button only appeared while scoped
    /// to one board — so from an unscoped gallery ("모든 카드") there was no
    /// way to add a place at all. Now the button is always there and the board
    /// is resolved first: the scoped one, the only one when there's just
    /// one, or whichever the user picks.
    ///
    /// An `Identifiable` item for `.sheet(item:)` rather than a `Bool` plus
    /// `if let` inside the sheet closure — the exact shape
    /// `MainTabView.pendingShare`'s own doc comment documents as producing
    /// a structurally empty sheet.
    @State private var addCardStep: AddCardStep?
    /// Chosen in the picker and consumed in the sheet's `onDismiss`:
    /// presenting the add screen in the same tick as the picker closes is
    /// how a sheet ends up silently not presenting.
    @State private var pendingAddBoardID: String?
    @State private var isShowingNoBoardAlert = false

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
    /// inside `viewModel` via `scope`. nil while scoped to 가져오기 or
    /// to everything — neither is a board.
    private var scopedBoard: Board? {
        guard let boardID = viewModel.scope.boardID else { return nil }
        return storageService.boards.first { $0.id == boardID }
    }

    /// 무엇으로 좁혀져 있는지 제목에 적는다. 좁혀 놓고 제목이 그냥
    /// "갤러리"이면 카드가 왜 몇 장뿐인지 알 길이 없다.
    private var scopeTitle: String {
        switch viewModel.scope {
        case .all:
            return "갤러리".localized
        case .board:
            return scopedBoard.map { "갤러리 · ".localized + $0.name } ?? "갤러리".localized
        case .imported:
            return "갤러리 · ".localized + "가져오기".localized
        }
    }

    private var selectedCards: [PlaceCard] {
        viewModel.filteredPlaceCards.filter { selectedIDs.contains($0.id) }
    }

    /// 범위 하나를 가리키는 열쇠. 보드는 id로 구별하고, 보드가 아닌
    /// 모음은 제 이름을 쓴다.
    private var scopeLayoutKey: String {
        switch viewModel.scope {
        case .all: return "all"
        case .board(let id): return "board:" + id
        case .imported: return "imported"
        }
    }

    private var layoutByScope: [String: String] {
        guard let data = layoutByScopeRaw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return decoded
    }

    private var layout: GalleryLayout {
        if let stored = layoutByScope[scopeLayoutKey],
           let storedLayout = GalleryLayout(rawValue: stored) {
            return storedLayout
        }
        return GalleryLayout(rawValue: legacyLayoutRaw) ?? .grid
    }

    /// 지운 보드의 항목은 사전에 남는다. 짧은 문자열 하나뿐이라 해롭지
    /// 않고, 지우려면 보드 삭제 쪽에 손을 대야 해서 그대로 둔다.
    private func setLayout(_ newLayout: GalleryLayout) {
        var map = layoutByScope
        map[scopeLayoutKey] = newLayout.rawValue
        guard let data = try? JSONEncoder().encode(map),
              let text = String(data: data, encoding: .utf8) else { return }
        layoutByScopeRaw = text
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
            .navigationTitle(scopeTitle)
            // `.always` so search stays visible without a pull-down/
            // scroll — same as Home/BoardDetailView, since the only
            // intended difference between this screen and BoardDetailView
            // is grid vs. list.
            .searchable(text: $viewModel.searchQuery, placement: .navigationBarDrawer(displayMode: .always), prompt: "카드 검색".localized)
            // Home tab's board (if any) is only known once this tab
            // itself becomes visible — synced here rather than read once
            // at init, since the user may navigate around Home first and
            // only then switch to this tab.
            .onAppear {
                viewModel.scope = navigation.galleryScope
                consumePendingDetailCardID()
            }
            .onChange(of: navigation.galleryScope) { _, newValue in
                viewModel.scope = newValue
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
            // One-shot, same shape as `galleryCategoryFilter` above — a
            // card just created from shared-in info (`AddPlaceCardView`)
            // pushes straight to its detail view once, then clears itself
            // so switching back to this tab later doesn't reopen it. Also
            // handled in `.onAppear` above (see `consumePendingDetailCardID`)
            // for the *first* share of a session: `AddPlaceCardView` sets
            // this and switches to this tab together, and if this view
            // hasn't been visited yet this session, switching tabs is what
            // actually mounts/reveals it — `.onChange` alone can miss a
            // value that was already set before that happened, showing the
            // plain card list instead of pushing straight to the detail.
            .onChange(of: navigation.pendingDetailCardID) { _, _ in
                consumePendingDetailCardID()
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
            .sheet(item: $addCardStep, onDismiss: consumePendingAddBoard) { step in
                switch step {
                case .pickBoard:
                    addBoardPickerSheet
                case .add(let boardID):
                    AddPlaceCardView(viewModel: PlaceCardViewModel(storageService: storageService, boardId: boardID))
                        .environmentObject(navigation)
                }
            }
            .alert("게시판이 먼저 필요합니다".localized, isPresented: $isShowingNoBoardAlert) {
                Button("확인".localized, role: .cancel) {}
            } message: {
                Text("장소 카드는 게시판 안에 담깁니다. 홈 탭에서 게시판을 먼저 만들어주세요.".localized)
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
            } message: {
                Text("삭제됨으로 옮겨집니다. 거기서 되돌릴 수 있습니다.".localized)
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
            } message: {
                Text("삭제됨으로 옮겨집니다. 거기서 되돌릴 수 있습니다.".localized)
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

    /// Shared by `.onAppear` and `.onChange(of: navigation.pendingDetailCardID)`
    /// — see either call site's comment for why both are needed. Safe to
    /// call redundantly (a no-op once the value's already been cleared).
    private func consumePendingDetailCardID() {
        guard let pendingID = navigation.pendingDetailCardID else { return }
        navigation.pendingDetailCardID = nil
        if let card = storageService.placeCard(id: pendingID) {
            selectedCard = card
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
        // The credit line goes at the end of both layouts, inside the
        // scrolling content — this screen has no other bottom, and
        // `safeAreaInset` is already spoken for by the bulk-action bar.
        switch layout {
        case .grid:
            ScrollView {
                // 칸 사이 2pt에 바깥 padding은 없다 — 사진이 화면
                // 가장자리까지 닿아야 벽처럼 이어진다. minimum도 160에서
                // 내려 한 줄에 더 들어가게 했다. 칸이 정사각형이 되면서
                // 예전만큼 넓지 않아도 사진이 제대로 보인다.
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 110), spacing: Theme.gridGutter)],
                    spacing: Theme.gridGutter
                ) {
                    ForEach(viewModel.filteredPlaceCards) { card in
                        gridCell(card)
                    }
                }
                CreditFooter()
                    .padding(.top, 16)
                    .padding(.bottom, 16)
            }
            .background(Theme.canvas)
        case .list:
            List {
                ForEach(viewModel.filteredPlaceCards) { card in
                    listRow(card)
                }
                Section {
                    CreditFooter()
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.panel)
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
                            .accessibilityLabel(selectedIDs.contains(card.id) ? "선택 해제".localized : "선택".localized)
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
                        .accessibilityLabel(selectedIDs.contains(card.id) ? "선택 해제".localized : "선택".localized)
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
        // 좁혀진 것을 푸는 "전체 보기" 버튼이 여기 있었다. 홈의 "모든
        // 카드"가 같은 일을 하고, 홈은 탭이라 어디서든 한 번에 닿는다 —
        // 화면마다 빠져나오는 길을 따로 두지 않는다. 지금 무엇으로
        // 좁혀져 있는지는 `scopeTitle`이 제목에 적는다.
        if !isSelecting {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    startAddingCard()
                } label: {
                    Label("장소 추가".localized, systemImage: "plus")
                }
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                setLayout(layout == .grid ? .list : .grid)
            } label: {
                Image(systemName: layout == .grid ? GalleryLayout.list.systemImage : GalleryLayout.grid.systemImage)
                    .accessibilityLabel(layout == .grid ? "목록으로 보기".localized : "격자로 보기".localized)
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

        // 지금 보고 있는 게시판에서만 뺀다. 삭제가 아니므로 카드는 다른
        // 게시판과 "모든 카드"에 그대로 남는다. 게시판 하나로 좁혀 보고
        // 있을 때만 뜬다 — 전체를 보고 있으면 어느 게시판에서 뺄지가
        // 정해지지 않는다.
        if let scopedBoard {
            Button {
                removeSelectedFromScopedBoard(scopedBoard)
            } label: {
                Label("게시판에서 제거".localized, systemImage: "minus.circle")
                    .font(.subheadline.weight(.medium))
            }
            .disabled(selectedIDs.isEmpty)
        }

        if !storageService.boards.isEmpty {
            Menu {
                ForEach(storageService.boards) { board in
                    Button {
                        addSelected(to: board)
                    } label: {
                        Label(board.name, systemImage: board.coverIcon)
                    }
                }
            } label: {
                Label("게시판에 추가".localized, systemImage: "plus.rectangle.on.folder")
                    .font(.subheadline.weight(.medium))
            }
            .disabled(selectedIDs.isEmpty)

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

    /// Resolves which board the new card belongs to before opening the add
    /// sheet: the board being viewed, the only board there is, or one the
    /// user picks. With no boards at all there is nothing to add into, so
    /// this says so rather than opening a sheet that couldn't save.
    private func startAddingCard() {
        if let scopedBoard {
            addCardStep = .add(boardID: scopedBoard.id)
        } else if storageService.boards.count == 1, let only = storageService.boards.first {
            addCardStep = .add(boardID: only.id)
        } else if storageService.boards.isEmpty {
            isShowingNoBoardAlert = true
        } else {
            addCardStep = .pickBoard
        }
    }

    private func consumePendingAddBoard() {
        guard let pendingAddBoardID else { return }
        self.pendingAddBoardID = nil
        addCardStep = .add(boardID: pendingAddBoardID)
    }

    private var addBoardPickerSheet: some View {
        NavigationStack {
            List(storageService.boards) { board in
                Button {
                    pendingAddBoardID = board.id
                    addCardStep = nil
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(board.name)
                                .foregroundStyle(.primary)
                            Text("\(storageService.placeCards(inBoard: board.id).count)" + "개 장소".localized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
            }
            .navigationTitle("어느 게시판에 담을까요?".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소".localized) { addCardStep = nil }
                }
            }
        }
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

    /// 고른 카드를 게시판에 하나 더 넣는다. "이동"과 달리 원래 있던
    /// 게시판에서 빠지지 않는다 — 한 카드가 여러 게시판에 들어갈 수
    /// 있다는 것이 이 화면에서 처음 드러나는 곳이다.
    private func addSelected(to board: Board) {
        for id in selectedIDs {
            guard let card = storageService.placeCard(id: id) else { continue }
            storageService.addToBoard(card, boardID: board.id)
        }
        exitSelection()
    }

    private func removeSelectedFromScopedBoard(_ board: Board) {
        for id in selectedIDs {
            guard let card = storageService.placeCard(id: id) else { continue }
            storageService.removeFromBoard(card, boardID: board.id)
        }
        exitSelection()
    }

    private func moveSelected(to newBoard: Board) {
        for id in selectedIDs {
            guard var card = storageService.placeCard(id: id) else { continue }
            // "이동"이므로 소속을 갈아치운다. 보드를 하나 더하는 것은
            // `StorageService.addToBoard(_:boardID:)` 쪽이다.
            card.boardIDs = [newBoard.id]
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
/// second tap meaning) — the visited/favorite controls stay their own
/// `.plain`-styled buttons, which still claim their own taps ahead of
/// that surrounding gesture. Favorite/visited mirror Peragra's
/// `PlaceRowView`, including being toggleable right from here.
///
/// 전화·지도·웹사이트·인스타그램 버튼은 정사각형 칸으로 바꾸면서
/// 뺐다. 넷 다 목록 레이아웃(`GalleryView.listRow`)과 카드 상세에
/// 그대로 있다.
struct PlaceCardGridCell: View {
    let card: PlaceCard
    /// Set only while the grid is sorted by distance from a chosen
    /// reference — shown as a "250m"/"1.3km" label next to the address.
    var referenceCoordinate: Coordinates? = nil

    @EnvironmentObject private var storageService: StorageService

    var body: some View {
        // 정사각형이 이 격자의 전부다. 칸마다 높이가 다르면 아무리
        // 촘촘히 붙여도 아래가 들쭉날쭉해져서 사진이 벽처럼 이어지지
        // 않는다. 예전 셀은 사진 아래에 이름·장소확정·주소·거리·액션
        // 버튼 줄을 세로로 쌓았고, 그 줄들이 카드마다 있고 없고 해서
        // 높이가 제각각이었다.
        //
        // 그래서 글자는 사진 위에 얹는다.
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { photo }
            .overlay(alignment: .top) { topRow }
            .overlay(alignment: .bottomLeading) { caption }
            .clipped()
    }

    @ViewBuilder
    private var photo: some View {
        if let firstItem = card.coverPhoto,
           let image = MediaStore.loadThumbnail(fileName: firstItem.localPath, maxPixelSize: 500) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Theme.tile
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    /// 카테고리와 방문·즐겨찾기. 예전과 같은 자리, 그리고 예전과 같이
    /// `.overlay(alignment:)`다 — ZStack 형제로 두고 frame으로 구석에
    /// 밀면 그 frame이 버튼 자신의 탭 영역이 되어 셀 전체를 덮는다
    /// (00_UI개편_기초.md §2.4).
    private var topRow: some View {
        HStack(alignment: .top) {
            if let category = card.category, !category.isEmpty {
                Label {
                    Text(PlaceCategoryIcon.normalizedLabel(for: category))
                } icon: {
                    Image(systemName: PlaceCategoryIcon.symbolName(for: category))
                }
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
            }
            Spacer()
            HStack(spacing: 10) {
                Button(action: toggleVisited) {
                    Image(systemName: card.isVisited ? "checkmark.circle.fill" : "checkmark.circle")
                        .accessibilityLabel(card.isVisited ? "방문 표시 해제".localized : "방문으로 표시".localized)
                }
                Button(action: toggleFavorite) {
                    Image(systemName: card.isFavorite ? "star.fill" : "star")
                        .accessibilityLabel(card.isFavorite ? "즐겨찾기 해제".localized : "즐겨찾기에 추가".localized)
                }
            }
            .buttonStyle(.plain)
            .font(.callout)
        }
        // 켜짐/꺼짐을 초록·노랑이 아니라 채운 아이콘과 빈 아이콘으로
        // 구별한다. 화면의 유채색은 강조 파랑 하나뿐이라는 규칙 때문이고,
        // 채움 여부는 흑백으로도 읽힌다.
        .foregroundStyle(Theme.primaryText)
        .shadow(radius: Theme.overlayTextShadow)
        .padding(6)
    }

    /// 사진 아래가 아니라 사진 위 왼쪽 아래 — Lightroom이 날짜·크기·
    /// 파일명을 얹는 그 자리다. 액션 버튼(전화·지도·웹사이트·인스타)은
    /// 여기 없다. 정사각형을 유지하면서 버튼 넷을 더 넣을 자리가 없고,
    /// 넷 다 목록 레이아웃과 카드 상세에 그대로 있어서 없어지지 않는다.
    private var caption: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                if card.isPlaceConfirmed {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption2)
                        .accessibilityLabel("장소확정".localized)
                }
                Text(card.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            Text(card.address)
                .font(.caption2)
                .lineLimit(1)
            if let distanceText = Coordinates.distanceText(from: referenceCoordinate, to: card.coordinates) {
                Text(distanceText)
                    .font(.caption2)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(Theme.primaryText)
        // 스크림 대신 그림자다. 격자가 촘촘해서 칸마다 어두운 띠를
        // 깔면 화면 전체가 탁해진다.
        .shadow(radius: Theme.overlayTextShadow)
        .padding(6)
        // `lineLimit(1)`이 잘라 주려면 너비가 정해져 있어야 한다. 없으면
        // 긴 주소가 칸 밖으로 나가고 `.clipped()`가 글자 중간을 자른다.
        // 버튼이 아니라 글자 묶음에 건 frame이라 탭 영역과는 무관하다.
        .frame(maxWidth: .infinity, alignment: .leading)
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
