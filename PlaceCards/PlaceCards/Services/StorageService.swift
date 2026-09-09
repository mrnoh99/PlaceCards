import Foundation
import Combine

/// Local, on-device storage for PlaceCards as a JSON file in the app's
/// documents directory. Kept deliberately simple (no CoreData/SwiftData)
/// so the schema can evolve freely while the data model is still settling.
@MainActor
final class StorageService: ObservableObject {
    @Published private(set) var placeCards: [PlaceCard] = []

    private let fileURL: URL

    init(fileName: String = "placecards.json") {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = directory.appendingPathComponent(fileName)
        load()
    }

    func save(_ placeCard: PlaceCard) {
        var card = placeCard
        card.updatedAt = Date()
        if let index = placeCards.firstIndex(where: { $0.id == card.id }) {
            placeCards[index] = card
        } else {
            placeCards.append(card)
        }
        persist()
    }

    func delete(_ placeCard: PlaceCard) {
        placeCards.removeAll { $0.id == placeCard.id }
        persist()
    }

    func placeCard(id: String) -> PlaceCard? {
        placeCards.first { $0.id == id }
    }

    func search(query: String, tags: [String] = []) -> [PlaceCard] {
        placeCards.filter { card in
            let matchesQuery = query.isEmpty
                || card.name.localizedCaseInsensitiveContains(query)
                || card.address.localizedCaseInsensitiveContains(query)
            let matchesTags = tags.isEmpty || !Set(tags).isDisjoint(with: Set(card.tags))
            return matchesQuery && matchesTags
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([PlaceCard].self, from: data) {
            placeCards = decoded
        }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(placeCards) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
