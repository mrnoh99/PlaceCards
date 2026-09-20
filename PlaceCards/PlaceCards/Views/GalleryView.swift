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

    /// 삭제 대화상자에 곁들이는 "여기서만 빼기"의 이름. 지금 보고 있는
    /// 것이 게시판이나 가져오기일 때만 있다 — "모든 카드"를 보고 있으면
    /// 뺄 "여기"가 없어서 완전 삭제만 남는다.
    private var scopeRemovalTitle: String? {
        switch viewModel.scope {
        case .all:
            return nil
        case .board:
            return scopedBoard == nil ? nil : "이 게시판에서만 제거".localized
        case .imported:
            return "가져오기에서만 제거".localized
        }
    }

    /// 두 갈래가 각각 무엇인지 한 줄로 적는다. "삭제"가 두 가지 다른
    /// 일을 할 수 있게 됐으므로, 어느 쪽을 누르는지 모르고 고르는 일이
    /// 없어야 한다.
    private var deleteChoiceMessage: String {
        let full = "완전 삭제는 삭제됨으로 옮겨지고 거기서 되돌릴 수 있습니다.".localized
        guard scopeRemovalTitle != nil else { return full }
        return "여기서만 빼면 카드는 다른 곳에 그대로 남습니다.".localized + " " + full
    }

    private func removeFromScope(_ cards: [PlaceCard]) {
        switch viewModel.scope {
        case .all:
            break
        case .board(let id):
            for card in cards { storageService.removeFromBoard(card, boardID: id) }
        case .imported:
            for card in cards { storageService.removeFromImported(card) }
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
                if let scopeRemovalTitle {
                    Button(scopeRemovalTitle) {
                        if let card = cardPendingDelete { removeFromScope([card]) }
                        cardPendingDelete = nil
                    }
                }
                Button("완전 삭제".localized, role: .destructive) {
                    if let card = cardPendingDelete {
                        storageService.delete(card)
                    }
                    cardPendingDelete = nil
                }
                Button("취소".localized, role: .cancel) { cardPendingDelete = nil }
            } message: {
                Text(deleteChoiceMessage)
            }
            .confirmationDialog(
                bulkDeleteConfirmationTitle,
                isPresented: $isConfirmingBulkDelete,
                titleVisibility: .visible
            ) {
                if let scopeRemovalTitle {
                    Button(scopeRemovalTitle) {
                        removeFromScope(selectedCards)
                        exitSelection()
                    }
                }
                Button(bulkDeleteConfirmationButtonTitle, role: .destructive) {
                    deleteSelected()
                }
                Button("취소".localized, role: .cancel) {}
            } message: {
                Text(deleteChoiceMessage)
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
        "\(selectedIDs.count)" + "개 완전 삭제".localized
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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
                    ForEach(viewModel.filteredPlaceCards) { card in
                        gridCell(card)
                    }
                }
                .padding()
                CreditFooter()
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
                if let firstItem = card.coverPhoto,
                   let image = MediaStore.loadThumbnail(fileName: firstItem.localPath, maxPixelSize: 500) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        // `scaledToFill`은 준 자리를 채우려고 둘 중 큰
                        // 비율로 키운다. 칸보다 가로로 긴 사진(16:9
                        // 이상)은 그 결과가 칸보다 넓어지고, 그 넓이가
                        // ZStack -> VStack으로 그대로 올라가 아래 글자
                        // 줄까지 칸 밖으로 밀어낸다. `.clipped()`는 그리는
                        // 것만 자를 뿐 크기를 되돌리지 않아 막지 못한다.
                        //
                        // 칸이 넓은 아이패드에서는 칸 비율이 사진 비율보다
                        // 커서 좀처럼 드러나지 않지만, 아이폰처럼 칸이
                        // 좁으면 바로 보인다.
                        //
                        // maxWidth로 너비만 칸에 묶어 둔다. 사진 자체는
                        // 여전히 넘치게 그려지고 아래 clipShape이 자른다.
                        .frame(maxWidth: .infinity)
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
                                .accessibilityLabel(card.isVisited ? "방문 표시 해제".localized : "방문으로 표시".localized)
                                .foregroundStyle(card.isVisited ? .green : .white)
                        }
                        Button(action: toggleFavorite) {
                            Image(systemName: card.isFavorite ? "star.fill" : "star")
                                .accessibilityLabel(card.isFavorite ? "즐겨찾기 해제".localized : "즐겨찾기에 추가".localized)
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
            // 사진 말고 다른 것이 ZStack을 넓히더라도 칸을 넘지 않게
            // 한 번 더 묶는다. 버튼이 아니라 사진 칸 전체에 건 frame이라
            // 별·방문 버튼의 탭 영역과는 무관하다.
            .frame(maxWidth: .infinity)
            .clipped()

            Text(card.name)
                .font(.subheadline.bold())
                .lineLimit(1)
            if card.isPlaceConfirmed {
                Label("장소확정".localized, systemImage: "checkmark.seal.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
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
                                .accessibilityLabel("전화 걸기".localized)
                        }
                    }
                    if card.hasAnyMapLink {
                        MapOpenMenu(card: card) {
                            Image(systemName: "map")
                                .accessibilityLabel("지도에서 열기".localized)
                        }
                    }
                    if let website = card.website, let url = URL(string: website) {
                        Button { openURL(url) } label: {
                            Image(systemName: "link")
                                .accessibilityLabel("웹사이트 열기".localized)
                        }
                    }
                    if let instagramURL = card.instagramURL, let url = URL(string: instagramURL) {
                        Button { openURL(url) } label: {
                            Image(systemName: "camera")
                                .accessibilityLabel("인스타그램 열기".localized)
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
