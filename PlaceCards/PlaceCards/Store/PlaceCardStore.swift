import Foundation
import Combine

final class PlaceCardStore: ObservableObject {
    @Published private(set) var cards: [PlaceCard] = []

    private let storageURL: URL

    init(storageURL: URL? = nil) {
        if let storageURL {
            self.storageURL = storageURL
        } else {
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.storageURL = directory.appendingPathComponent("placecards.json")
        }
        load()
    }

    func addCard(_ card: PlaceCard) {
        cards.append(card)
        save()
    }

    func updateCard(_ card: PlaceCard) {
        guard let index = cards.firstIndex(where: { $0.id == card.id }) else { return }
        cards[index] = card
        save()
    }

    func deleteCards(at offsets: IndexSet) {
        cards.remove(atOffsets: offsets)
        save()
    }

    func moveCards(from source: IndexSet, to destination: Int) {
        cards.move(fromOffsets: source, toOffset: destination)
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([PlaceCard].self, from: data) else {
            return
        }
        cards = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(cards) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}
