import Foundation
import Combine

@MainActor
final class GalleryViewModel: ObservableObject {
    @Published var searchQuery: String = ""
    @Published var selectedTag: String?
    @Published var categoryFilter: String?
    @Published var statusFilter: PlaceStatusFilter = .all
    @Published var sortMode: PlaceSortMode = .byCategory
    @Published var distanceReference: DistanceReference?
    @Published var hereCoordinate: Coordinates?

    private let storageService: StorageService

    init(storageService: StorageService) {
        self.storageService = storageService
    }

    /// Search/tag-filtered, but before the all/favorite/visited chip —
    /// used both to build the list and to compute each chip's count, so
    /// the counts reflect the other active filters rather than going
    /// stale next to them (mirrors Peragra's `preCategoryFiltered`).
    private var searchFilteredPlaceCards: [PlaceCard] {
        let tags = selectedTag.map { [$0] } ?? []
        let matched = storageService.search(query: searchQuery, tags: tags)
        guard let categoryFilter else { return matched }
        return matched.filter { $0.category == categoryFilter }
    }

    private var distanceReferenceCoordinate: Coordinates? {
        switch distanceReference {
        case .here: return hereCoordinate
        case .card(let id): return storageService.placeCard(id: id)?.coordinates
        case nil: return nil
        }
    }

    /// Filtered by the status chip, then sorted — the exact set the grid
    /// renders. Mirrors Peragra's `TripDetailView.sortedPlaces`.
    var filteredPlaceCards: [PlaceCard] {
        searchFilteredPlaceCards.filter(statusFilter.matches).sorted(by: sortMode, distanceFrom: distanceReferenceCoordinate)
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

    var locatableCards: [PlaceCard] {
        storageService.placeCards.filter { $0.coordinates != nil }
    }

    var allTags: [String] {
        Array(Set(storageService.placeCards.flatMap { $0.tags })).sorted()
    }

    var allCategories: [String] {
        Array(Set(storageService.placeCards.compactMap { $0.category?.isEmpty == false ? $0.category : nil })).sorted()
    }

    func delete(_ card: PlaceCard) {
        storageService.delete(card)
    }
}
