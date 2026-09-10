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

    /// Filtered by the status chip, then sorted — the exact set the grid
    /// renders. Mirrors Peragra's `TripDetailView.sortedPlaces`.
    private var cards: [PlaceCard] {
        allCards
            .filter(statusFilter.matches)
            .filter { categoryFilter == nil || $0.category == categoryFilter }
            .sorted(by: sortMode, distanceFrom: distanceReferenceCoordinate)
    }

    private var locatableCards: [PlaceCard] {
        allCards.filter { $0.coordinates != nil }
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
                        locatableCards: locatableCards,
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
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
                                ForEach(cards) { card in
                                    NavigationLink {
                                        PlaceCardDetailView(card: card)
                                    } label: {
                                        PlaceCardGridCell(card: card)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding()
                        }
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
    }
}

#Preview {
    NavigationStack {
        BoardDetailView(board: Board(name: "도쿄 봄 여행", subtitle: "2026년 4월", coverEmoji: "✈️"))
            .environmentObject(StorageService())
    }
}
