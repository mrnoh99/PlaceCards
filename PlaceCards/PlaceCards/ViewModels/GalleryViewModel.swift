import Foundation
import Combine

@MainActor
final class GalleryViewModel: ObservableObject {
    @Published var searchQuery: String = ""
    @Published var selectedTag: String?

    private let storageService: StorageService

    init(storageService: StorageService) {
        self.storageService = storageService
    }

    var filteredPlaceCards: [PlaceCard] {
        let tags = selectedTag.map { [$0] } ?? []
        return storageService.search(query: searchQuery, tags: tags)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var allTags: [String] {
        Array(Set(storageService.placeCards.flatMap { $0.tags })).sorted()
    }

    func delete(_ card: PlaceCard) {
        storageService.delete(card)
    }
}
