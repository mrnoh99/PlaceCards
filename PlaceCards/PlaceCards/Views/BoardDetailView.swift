import SwiftUI

/// Shows the place cards inside one board, and is where new place cards
/// actually get created — mirrors Peragra's `TripDetailView` (simplified:
/// no lists/collections/duplicate-merging here).
struct BoardDetailView: View {
    let board: Board
    @EnvironmentObject private var storageService: StorageService
    @State private var isPresentingAddCard = false
    @State private var statusFilter: PlaceStatusFilter = .all
    @State private var sortMode: PlaceSortMode = .byCategory
    @State private var distanceReference: DistanceReference?
    @State private var hereCoordinate: Coordinates?
    @State private var categoryFilter: String?
    @State private var cardPendingDelete: PlaceCard?

    private var allCards: [PlaceCard] {
        storageService.placeCards(inBoard: board.id)
    }

    private var categories: [String] {
        Array(Set(allCards.compactMap { $0.category?.isEmpty == false ? $0.category : nil })).sorted()
    }

    private var distanceReferenceCoordinate: Coordinates? {
        switch distanceReference {
        case .here: return hereCoordinate
        case .card(let id): return allCards.first { $0.id == id }?.coordinates
        case nil: return nil
        }
    }

    /// Filtered by the status chip, then sorted — the exact set the list
    /// renders. Mirrors Peragra's `TripDetailView.sortedPlaces`.
    private var cards: [PlaceCard] {
        allCards
            .filter(statusFilter.matches)
            .filter { categoryFilter == nil || $0.category == categoryFilter }
            .sorted(by: sortMode, distanceFrom: distanceReferenceCoordinate)
    }

    /// Every card in this board, offered by name as a "Distance from…"
    /// reference choice — not narrowed to ones with a resolved coordinate,
    /// since a card added without one yet should still be pickable by
    /// name; `PlaceCardSorting` already falls back to leaving the list
    /// unsorted if the chosen reference turns out to have none.
    private var referenceCandidates: [PlaceCard] {
        allCards
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
                                // A `NavigationLink { } label: { PlaceCardListRow(...) }`
                                // here would make the *whole row* the link's
                                // tap target inside a List, swallowing taps
                                // on PlaceCardListRow's own favorite/visited
                                // buttons before they ever fire. Using an
                                // invisible NavigationLink alongside the real
                                // (visible, interactive) row content instead
                                // still gives the row its disclosure chevron
                                // and "tap anywhere else to open detail"
                                // behavior, but lets the row's own buttons
                                // take priority over it.
                                ZStack {
                                    NavigationLink {
                                        PlaceCardDetailView(card: card)
                                    } label: {
                                        EmptyView()
                                    }
                                    .opacity(0)

                                    PlaceCardListRow(card: card)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        cardPendingDelete = card
                                    } label: {
                                        Label("삭제", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .listStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle(board.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isPresentingAddCard = true
                } label: {
                    Label("장소 추가", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isPresentingAddCard) {
            AddPlaceCardView(viewModel: PlaceCardViewModel(storageService: storageService, boardId: board.id))
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
    }
}

#Preview {
    NavigationStack {
        BoardDetailView(board: Board(name: "도쿄 봄 여행", subtitle: "2026년 4월", coverEmoji: "✈️"))
            .environmentObject(StorageService())
    }
}
