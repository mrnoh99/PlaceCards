import SwiftUI

/// Shows the place cards inside one board, and is where new place cards
/// actually get created — mirrors Peragra's `TripDetailView` (simplified:
/// no lists/collections/duplicate-merging here).
struct BoardDetailView: View {
    let board: Board
    @EnvironmentObject private var storageService: StorageService
    @EnvironmentObject private var navigation: AppNavigation
    @State private var isPresentingAddCard = false
    @State private var statusFilter = PlaceStatusFilter()
    @State private var sortMode: PlaceSortMode = .byCategory
    @State private var distanceReference: DistanceReference?
    @State private var hereCoordinate: Coordinates?
    @State private var categoryFilter: String?
    @State private var cardPendingDelete: PlaceCard?
    @State private var selectedCard: PlaceCard?
    @State private var isPresentingFindDuplicates = false

    /// Multi-select mode for bulk actions (change category, move board,
    /// delete, merge) — mirrors Peragra's `PlaceListingView`
    /// (`isSelecting`/`selectedIDs`/bulk action bar).
    @State private var isSelecting = false
    @State private var selectedIDs: Set<String> = []
    @State private var isConfirmingBulkDelete = false
    @State private var isPresentingMergeSelection = false
    @State private var isPresentingCustomCategoryInput = false
    @State private var customCategoryInput = ""

    private var allCards: [PlaceCard] {
        storageService.placeCards(inBoard: board.id)
    }

    private var categories: [String] {
        let normalized = allCards.compactMap { card -> String? in
            guard let category = card.category, !category.isEmpty else { return nil }
            return PlaceCategoryIcon.normalizedLabel(for: category)
        }
        return Array(Set(normalized)).sorted()
    }

    private var distanceReferenceCoordinate: Coordinates? {
        switch distanceReference {
        case .here: return hereCoordinate
        case .card(let id): return allCards.first { $0.id == id }?.coordinates
        case nil: return nil
        }
    }

    /// The reference card's own id when distance-sorting from another
    /// saved card (never set for "현재 위치") — pinned to the top of
    /// `cards` below rather than sorted in as an ordinary entry.
    private var pinnedReferenceCardID: String? {
        guard case .card(let id) = distanceReference else { return nil }
        return id
    }

    /// Filtered by the status chip, then sorted — the exact set the list
    /// renders. Mirrors Peragra's `TripDetailView.sortedPlaces`.
    private var cards: [PlaceCard] {
        allCards
            .filter(statusFilter.matches)
            .filter { card in
                guard let categoryFilter else { return true }
                guard let category = card.category, !category.isEmpty else { return false }
                return PlaceCategoryIcon.normalizedLabel(for: category) == categoryFilter
            }
            .sorted(by: sortMode, distanceFrom: distanceReferenceCoordinate, pinnedID: pinnedReferenceCardID)
    }

    /// Every card in this board, offered by name as a "Distance from…"
    /// reference choice — not narrowed to ones with a resolved coordinate,
    /// since a card added without one yet should still be pickable by
    /// name; `PlaceCardSorting` already falls back to leaving the list
    /// unsorted if the chosen reference turns out to have none.
    private var referenceCandidates: [PlaceCard] {
        allCards
    }

    /// Every other board, offered as "move to" choices in the bulk
    /// action bar.
    private var otherBoards: [Board] {
        storageService.boards.filter { $0.id != board.id }
    }

    private var selectedCards: [PlaceCard] {
        cards.filter { selectedIDs.contains($0.id) }
    }

    var body: some View {
        Group {
            if allCards.isEmpty {
                ContentUnavailableView {
                    Label("장소가 없습니다", systemImage: "mappin.slash")
                } description: {
                    Text("오른쪽 위 + 버튼으로 이 게시판에 첫 장소를 추가해보세요.")
                }
            } else {
                VStack(spacing: 0) {
                    PlaceStatusFilterBar(
                        sortMode: $sortMode,
                        distanceReference: $distanceReference,
                        hereCoordinate: $hereCoordinate,
                        referenceCandidates: referenceCandidates,
                        categoryFilter: $categoryFilter,
                        categories: categories,
                        filter: $statusFilter,
                        allCount: allCards.count,
                        favoriteCount: allCards.filter(\.isFavorite).count,
                        visitedCount: allCards.filter(\.isVisited).count
                    )
                    if cards.isEmpty {
                        ContentUnavailableView {
                            Label("해당하는 장소가 없습니다", systemImage: "line.3.horizontal.decrease.circle")
                        } description: {
                            Text("다른 필터를 선택해보세요.")
                        }
                    } else {
                        List {
                            ForEach(cards) { card in
                                // No NavigationLink/Button wraps the row —
                                // in a List, either one claims the whole
                                // row as its own tap target and swallows
                                // taps on PlaceCardListRow's own favorite/
                                // visited buttons before they ever fire
                                // (confirmed broken; Peragra's own
                                // PlaceRowView/PlaceListingView sidesteps
                                // this the same way, with no NavigationLink
                                // around its row at all). A plain
                                // .onTapGesture on the row instead only
                                // fires for points the row's own Buttons
                                // don't already claim, so both work.
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
                                    PlaceCardListRow(card: card, referenceCoordinate: distanceReferenceCoordinate)
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
                                            Label("삭제", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                        .listStyle(.plain)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                bulkActionBar
            }
        }
        // Fires whenever this view becomes topmost — the initial push
        // from Home, and again on popping back to it from a deeper push
        // (e.g. PlaceCardDetailView) — so Gallery/Map (via
        // `AppNavigation.currentHomeBoardID`) stay scoped to this board
        // for as long as Home is anywhere inside it, not just while this
        // exact screen is on top.
        .onAppear { navigation.currentHomeBoardID = board.id }
        .navigationTitle(board.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isSelecting {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPresentingAddCard = true
                    } label: {
                        Label("장소 추가", systemImage: "plus")
                    }
                }
                if allCards.count > 1 {
                    ToolbarItem(placement: .secondaryAction) {
                        Button {
                            isPresentingFindDuplicates = true
                        } label: {
                            Label("중복 찾기", systemImage: "arrow.triangle.merge")
                        }
                    }
                }
            }
            if !allCards.isEmpty {
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        isSelecting.toggle()
                        if !isSelecting { selectedIDs.removeAll() }
                    } label: {
                        Text(isSelecting ? "취소" : "선택")
                    }
                }
            }
        }
        .sheet(isPresented: $isPresentingAddCard) {
            AddPlaceCardView(viewModel: PlaceCardViewModel(storageService: storageService, boardId: board.id))
        }
        .sheet(isPresented: $isPresentingFindDuplicates) {
            FindDuplicatesSheet(cards: allCards)
        }
        .sheet(isPresented: $isPresentingMergeSelection, onDismiss: exitSelection) {
            FindDuplicatesSheet(manualGroup: selectedCards)
        }
        .navigationDestination(item: $selectedCard) { card in
            PlaceCardDetailView(card: card)
        }
        .confirmationDialog(
            "\"\(cardPendingDelete?.name ?? "")\"을 삭제할까요?",
            isPresented: Binding(
                get: { cardPendingDelete != nil },
                set: { if !$0 { cardPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive) {
                if let card = cardPendingDelete {
                    storageService.delete(card)
                }
                cardPendingDelete = nil
            }
            Button("취소", role: .cancel) { cardPendingDelete = nil }
        }
        .confirmationDialog(
            "\(selectedIDs.count)개 장소를 삭제할까요?",
            isPresented: $isConfirmingBulkDelete,
            titleVisibility: .visible
        ) {
            Button("\(selectedIDs.count)개 삭제", role: .destructive) {
                deleteSelected()
            }
            Button("취소", role: .cancel) {}
        }
        .alert("카테고리 입력", isPresented: $isPresentingCustomCategoryInput) {
            TextField("카테고리", text: $customCategoryInput)
            Button("변경") {
                applyCategory(customCategoryInput)
                customCategoryInput = ""
            }
            Button("취소", role: .cancel) { customCategoryInput = "" }
        }
    }

    /// The bulk action bar shown above the tab bar while `isSelecting` —
    /// mirrors Peragra's `PlaceListingView.bulkActionBar`.
    private var bulkActionBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(selectedIDs.isEmpty ? "수정할 장소를 선택하세요" : "\(selectedIDs.count)개 선택됨")
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
            Text(selectedIDs.count == cards.count ? "전체 해제" : "전체 선택")
                .font(.subheadline.weight(.medium))
        }
        .disabled(cards.isEmpty)

        Button(role: .destructive) {
            isConfirmingBulkDelete = true
        } label: {
            Label("삭제", systemImage: "trash")
                .font(.subheadline.weight(.medium))
        }
        .disabled(selectedIDs.isEmpty)

        Menu {
            ForEach(categories, id: \.self) { category in
                Button(category) { applyCategory(category) }
            }
            Button("직접 입력…") { isPresentingCustomCategoryInput = true }
        } label: {
            Label("카테고리 변경", systemImage: "tag")
                .font(.subheadline.weight(.medium))
        }
        .disabled(selectedIDs.isEmpty)

        if !otherBoards.isEmpty {
            Menu {
                ForEach(otherBoards) { otherBoard in
                    Button {
                        moveSelected(to: otherBoard)
                    } label: {
                        Label(otherBoard.name, systemImage: otherBoard.coverIcon)
                    }
                }
            } label: {
                Label("게시판 이동", systemImage: "arrow.right.square")
                    .font(.subheadline.weight(.medium))
            }
            .disabled(selectedIDs.isEmpty)
        }

        Button {
            navigation.showOnMap(selectedIDs)
            exitSelection()
        } label: {
            Label("지도에서 보기", systemImage: "map")
                .font(.subheadline.weight(.medium))
        }
        .disabled(selectedIDs.isEmpty)

        Button {
            isPresentingMergeSelection = true
        } label: {
            Label("병합", systemImage: "arrow.triangle.merge")
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
    /// — respects whatever's already narrowing `cards`.
    private func toggleSelectAll() {
        if selectedIDs.count == cards.count {
            selectedIDs.removeAll()
        } else {
            selectedIDs = Set(cards.map(\.id))
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

#Preview {
    NavigationStack {
        BoardDetailView(board: Board(name: "도쿄 봄 여행", subtitle: "2026년 4월", coverIcon: "airplane"))
            .environmentObject(StorageService())
            .environmentObject(AppNavigation())
    }
}
