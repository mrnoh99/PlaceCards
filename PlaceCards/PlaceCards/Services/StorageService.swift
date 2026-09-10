import Foundation
import Combine

/// Local, on-device storage for Boards and their PlaceCards, as two JSON
/// files in the app's documents directory. Kept deliberately simple (no
/// CoreData/SwiftData) so the schema can evolve freely while the data model
/// is still settling.
@MainActor
final class StorageService: ObservableObject {
    @Published private(set) var boards: [Board] = []
    @Published private(set) var placeCards: [PlaceCard] = []

    private let boardsFileURL: URL
    private let placeCardsFileURL: URL

    init(boardsFileName: String = "boards.json", placeCardsFileName: String = "placecards.json") {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        boardsFileURL = directory.appendingPathComponent(boardsFileName)
        placeCardsFileURL = directory.appendingPathComponent(placeCardsFileName)
        loadBoards()
        loadPlaceCards()
    }

    // MARK: - Boards

    func saveBoard(_ board: Board) {
        if let index = boards.firstIndex(where: { $0.id == board.id }) {
            boards[index] = board
        } else {
            boards.append(board)
        }
        persistBoards()
    }

    /// Deletes the board and every PlaceCard inside it (and each of their
    /// photos on disk), so nothing is left orphaned. Callers that want
    /// Peragra's stricter "only an empty board can be deleted" rule should
    /// check `placeCards(inBoard:).isEmpty` themselves before calling this.
    func deleteBoard(_ board: Board) {
        for card in placeCards(inBoard: board.id) {
            delete(card)
        }
        boards.removeAll { $0.id == board.id }
        persistBoards()
    }

    // MARK: - PlaceCards

    func placeCards(inBoard boardId: String) -> [PlaceCard] {
        placeCards.filter { $0.boardId == boardId }
    }

    func save(_ placeCard: PlaceCard) {
        var card = placeCard
        card.updatedAt = Date()
        if let index = placeCards.firstIndex(where: { $0.id == card.id }) {
            placeCards[index] = card
        } else {
            placeCards.append(card)
        }
        persistPlaceCards()
    }

    func delete(_ placeCard: PlaceCard) {
        for item in placeCard.media.allItems {
            MediaStore.delete(fileName: item.localPath)
        }
        placeCards.removeAll { $0.id == placeCard.id }
        persistPlaceCards()
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

    // MARK: - Persistence

    private func loadBoards() {
        guard let data = try? Data(contentsOf: boardsFileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([Board].self, from: data) {
            boards = decoded
        }
    }

    private func persistBoards() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(boards) else { return }
        try? data.write(to: boardsFileURL, options: .atomic)
    }

    private func loadPlaceCards() {
        guard let data = try? Data(contentsOf: placeCardsFileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([PlaceCard].self, from: data) {
            placeCards = decoded
        }
    }

    private func persistPlaceCards() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(placeCards) else { return }
        try? data.write(to: placeCardsFileURL, options: .atomic)
    }
}
