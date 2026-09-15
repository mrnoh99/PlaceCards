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

    /// Set when a file on disk existed but could not be decoded — see
    /// `decodeOrQuarantine`. Surfaced by `MainTabView` as an alert: silently
    /// starting empty is the one outcome this must never have, since the
    /// very next `save()` would persist that empty state over everything.
    @Published private(set) var loadFailureMessage: String?

    private let boardsFileURL: URL
    private let placeCardsFileURL: URL

    init(boardsFileName: String = "boards.json", placeCardsFileName: String = "placecards.json") {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        boardsFileURL = directory.appendingPathComponent(boardsFileName)
        placeCardsFileURL = directory.appendingPathComponent(placeCardsFileName)
        loadBoards()
        loadPlaceCards()
    }

    func acknowledgeLoadFailure() {
        loadFailureMessage = nil
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

    /// Removes a card that's just been merged into another one
    /// (`PlaceCard.merge(with:)`) — unlike `delete(_:)`, this does NOT
    /// delete its media files, since `merge` already copied those
    /// `MediaItem` entries onto the surviving card, which now owns them.
    func removeMergedDuplicate(_ placeCard: PlaceCard) {
        placeCards.removeAll { $0.id == placeCard.id }
        persistPlaceCards()
    }

    func placeCard(id: String) -> PlaceCard? {
        placeCards.first { $0.id == id }
    }

    /// Wholesale-replaces every board and place card — used only by
    /// `BackupService.restore(from:storageService:)`. Only deletes media
    /// files no card in the *restored* set still references, rather than
    /// unconditionally wiping every current card's media first: a backup
    /// never contains the actual image bytes (see `BackupService`'s own
    /// doc comment), so on a same-device restore the files a restored
    /// card still points at are still sitting on disk untouched, and
    /// blindly deleting them before the swap would silently break photos
    /// a lossless restore should have kept.
    func replaceAll(boards newBoards: [Board], placeCards newPlaceCards: [PlaceCard]) {
        let keptFileNames = Set(newPlaceCards.flatMap { $0.media.allItems.map(\.localPath) })
        for item in placeCards.flatMap({ $0.media.allItems }) where !keptFileNames.contains(item.localPath) {
            MediaStore.delete(fileName: item.localPath)
        }
        boards = newBoards
        placeCards = newPlaceCards
        persistBoards()
        persistPlaceCards()
    }

    func search(query: String, tags: [String] = []) -> [PlaceCard] {
        placeCards.filter { card in
            let matchesTags = tags.isEmpty || !Set(tags).isDisjoint(with: Set(card.tags))
            return card.matchesSearch(query) && matchesTags
        }
    }

    // MARK: - Persistence

    private func loadBoards() {
        guard let data = try? Data(contentsOf: boardsFileURL) else { return }
        guard let decoded = decodeOrQuarantine([Board].self, from: data, at: boardsFileURL) else { return }
        boards = decoded
    }

    /// Decodes a storage file, or — when the file exists but won't decode —
    /// moves it aside and reports it, rather than the old `try?` that left
    /// the in-memory array empty and carried on. That silence was the
    /// dangerous part: an empty array is indistinguishable from a genuine
    /// first run, so the very next `save()` would `persist…()` it straight
    /// over a file whose data was still perfectly intact — one unreadable
    /// field turning into total, unrecoverable loss. Keeping the original
    /// bytes under a timestamped name means the data is still there to
    /// recover from, and leaving `loadFailureMessage` set means the user
    /// finds out now (`MainTabView`'s alert) instead of discovering an
    /// empty library on their own. `SourceType.unsplashSearch`'s own doc
    /// comment describes exactly this failure mode.
    private func decodeOrQuarantine<T: Decodable>(_ type: T.Type, from data: Data, at url: URL) -> T? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode(type, from: data) { return decoded }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let quarantineURL = url
            .deletingLastPathComponent()
            .appendingPathComponent("\(url.deletingPathExtension().lastPathComponent)-corrupt-\(formatter.string(from: Date())).json")
        try? FileManager.default.moveItem(at: url, to: quarantineURL)
        loadFailureMessage = "저장된 데이터 일부를 읽지 못했습니다. 원본 파일은 \"".localized
            + quarantineURL.lastPathComponent
            + "\"(으)로 보관해 두었으니 덮어쓰지 않았습니다. 백업에서 복원하거나 지원에 문의해주세요.".localized
        return nil
    }

    private func persistBoards() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(boards) else { return }
        try? data.write(to: boardsFileURL, options: .atomic)
    }

    /// Every loaded card is re-sanitized for invisible Unicode format
    /// characters (`PlaceCard.strippingInvisibleFormatCharacters()`) — the
    /// only way an already-saved card that predates that stripping (or
    /// came through a source path that missed a field) ever actually gets
    /// fixed, since nothing else re-touches a card's text once it's saved.
    ///
    /// The cleaned result is only written back when there was actually
    /// something to clean. This used to re-encode and re-write the entire
    /// library on every single launch, including the overwhelmingly common
    /// case where nothing changed at all — pure launch-time cost for a
    /// byte-identical file. Whether anything needs stripping is decided by
    /// scanning the raw JSON for a format-category scalar, which is far
    /// cheaper than the encode it avoids (and `PlaceCard: Equatable`
    /// compares ids only, so comparing the cards themselves would never
    /// have detected it).
    private func loadPlaceCards() {
        guard let data = try? Data(contentsOf: placeCardsFileURL) else { return }
        guard let decoded = decodeOrQuarantine([PlaceCard].self, from: data, at: placeCardsFileURL) else { return }
        guard Self.containsInvisibleFormatCharacters(data) else {
            placeCards = decoded
            return
        }
        placeCards = decoded.map { $0.strippingInvisibleFormatCharacters() }
        persistPlaceCards()
    }

    private static func containsInvisibleFormatCharacters(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8) else { return false }
        return text.unicodeScalars.contains { $0.properties.generalCategory == .format }
    }

    private func persistPlaceCards() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(placeCards) else { return }
        try? data.write(to: placeCardsFileURL, options: .atomic)
    }
}
