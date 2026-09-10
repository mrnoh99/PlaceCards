import Foundation
import Combine

@MainActor
final class GalleryViewModel: ObservableObject {
    @Published var searchQuery: String = ""
    @Published var selectedTag: String?
    @Published var statusFilter: PlaceStatusFilter = .all

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
        return storageService.search(query: searchQuery, tags: tags)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var filteredPlaceCards: [PlaceCard] {
        searchFilteredPlaceCards.filter(statusFilter.matches)
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

    var allTags: [String] {
        Array(Set(storageService.placeCards.flatMap { $0.tags })).sorted()
    }

    func delete(_ card: PlaceCard) {
        storageService.delete(card)
    }
}
