import Foundation
import Combine

@MainActor
final class GalleryViewModel: ObservableObject {
    @Published var searchQuery: String = ""
    @Published var selectedTag: String?
    @Published var categoryFilter: String?
    @Published var statusFilter = PlaceStatusFilter()
    @Published var sortMode: PlaceSortMode = .byCategory
    @Published var distanceReference: DistanceReference?
    @Published var hereCoordinate: Coordinates?
    /// The board the Home tab is currently drilled into
    /// (`AppNavigation.currentHomeBoardID`), synced in by `GalleryView` —
    /// nil (Home at its board list) shows every card, as before; set,
    /// this narrows everything below to that one board, same as opening
    /// it from Home directly would.
    @Published var boardScopeID: String?

    private let storageService: StorageService

    init(storageService: StorageService) {
        self.storageService = storageService
    }

    /// Every card in scope — every board, or just `boardScopeID` — before
    /// any of the filters below narrow it further.
    private var scopedCards: [PlaceCard] {
        guard let boardScopeID else { return storageService.placeCards }
        return storageService.placeCards(inBoard: boardScopeID)
    }

    /// Search/tag-filtered, but before the all/favorite/visited chip —
    /// used both to build the list and to compute each chip's count, so
    /// the counts reflect the other active filters rather than going
    /// stale next to them (mirrors Peragra's `preCategoryFiltered`).
    private var searchFilteredPlaceCards: [PlaceCard] {
        let tags = selectedTag.map { [$0] } ?? []
        var matched = storageService.search(query: searchQuery, tags: tags)
        if let boardScopeID {
            matched = matched.filter { $0.boardId == boardScopeID }
        }
        guard let categoryFilter else { return matched }
        return matched.filter { card in
            guard let category = card.category, !category.isEmpty else { return false }
            return PlaceCategoryIcon.normalizedLabel(for: category) == categoryFilter
        }
    }

    var distanceReferenceCoordinate: Coordinates? {
        switch distanceReference {
        case .here: return hereCoordinate
        case .card(let id): return storageService.placeCard(id: id)?.coordinates
        case nil: return nil
        }
    }

    /// The reference card's own id when distance-sorting from another
    /// saved card (never set for "현재 위치") — pinned to the top of
    /// `filteredPlaceCards` below rather than sorted in as an ordinary
    /// entry.
    private var pinnedReferenceCardID: String? {
        guard case .card(let id) = distanceReference else { return nil }
        return id
    }

    /// Filtered by the status chip, then sorted — the exact set the grid
    /// renders. Mirrors Peragra's `TripDetailView.sortedPlaces`.
    var filteredPlaceCards: [PlaceCard] {
        searchFilteredPlaceCards
            .filter(statusFilter.matches)
            .sorted(by: sortMode, distanceFrom: distanceReferenceCoordinate, pinnedID: pinnedReferenceCardID)
    }

    var totalCount: Int {
        searchFilteredPlaceCards.count
    }

    var favoriteCount: Int {
        searchFilteredPlaceCards.filter(\.isFavorite).count
    }

    var visitedCount: Int {
        searchFilteredPlaceCards.filter(\.isVisited).count
    }

    /// Every card, offered by name as a "Distance from…" reference choice
    /// — not narrowed to ones with a resolved coordinate, since a card
    /// added without one yet should still be pickable by name;
    /// `PlaceCardSorting` already falls back to leaving the list unsorted
    /// if the chosen reference turns out to have none.
    var referenceCandidates: [PlaceCard] {
        scopedCards
    }

    var allTags: [String] {
        Array(Set(scopedCards.flatMap { $0.tags })).sorted()
    }

    var allCategories: [String] {
        let normalized = scopedCards.compactMap { card -> String? in
            guard let category = card.category, !category.isEmpty else { return nil }
            return PlaceCategoryIcon.normalizedLabel(for: category)
        }
        return Array(Set(normalized)).sorted()
    }

    func delete(_ card: PlaceCard) {
        storageService.delete(card)
    }
}
