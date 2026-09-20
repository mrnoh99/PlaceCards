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

    /// Does the encoding and the file write, off this main actor — see
    /// `LibraryFileWriter`.
    private let writer = LibraryFileWriter()
    /// Handed to the writer with every snapshot so it can tell a stale one
    /// from a current one. `Task { }` gives no ordering guarantee between
    /// two tasks created back to back, so without this an older snapshot
    /// could reach the writer after a newer one and overwrite it.
    private var boardsGeneration = 0
    private var placeCardsGeneration = 0

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

    /// Brings a backup's contents in without ever discarding anything the
    /// backup doesn't mention — used only by
    /// `BackupService.restore(from:storageService:)`.
    ///
    /// Per card, by `id`:
    /// - not here → added.
    /// - here, and the backup's copy has a **later `updatedAt`** → replaced
    ///   by the backup's copy.
    /// - here, and the backup's copy is the same age or older → left alone.
    ///
    /// This used to be `replaceAll`: the restored set became the library,
    /// wholesale, and anything added since that backup was written was
    /// gone. That made restoring an all-or-nothing gamble — recovering one
    /// card you deleted by mistake cost you every card added since. A card
    /// this backup simply doesn't contain is still never touched, so there
    /// is no destructive path here.
    ///
    /// The `updatedAt` comparison rests on that field being maintained
    /// honestly: `save(_:)` stamps it on every edit, and the merge below
    /// deliberately doesn't (a restored card keeps the timestamp it was
    /// saved with, which is what makes restoring the same file twice a
    /// no-op the second time). Its weak spot is clock skew between
    /// devices — a card edited on a device whose clock runs behind can
    /// lose to an older copy. There is no way around that with
    /// timestamps, and it is the same trade every sync of this shape makes.
    ///
    /// Boards are added when missing but never replaced: `Board` has no
    /// `updatedAt`, so there is nothing to compare, and a board is little
    /// more than a name.
    ///
    /// Nothing is deleted from disk, unlike the old `replaceAll`. A photo
    /// belonging only to a card that just got replaced is left where it
    /// is — wasted space is recoverable and visible in Settings; deleting
    /// a file something still needs is not.
    @discardableResult
    func merge(
        boards newBoards: [Board], placeCards newPlaceCards: [PlaceCard]
    ) -> (boards: Int, added: Int, updated: Int) {
        let existingBoardIDs = Set(boards.map(\.id))
        let addedBoards = newBoards.filter { !existingBoardIDs.contains($0.id) }
        boards.append(contentsOf: addedBoards)

        // A card whose board exists neither here nor in the backup would
        // be unreachable in the UI, so it is left out rather than saved
        // somewhere it can never be seen.
        let reachableBoardIDs = existingBoardIDs.union(newBoards.map(\.id))
        var indexByID: [String: Int] = [:]
        for (index, card) in placeCards.enumerated() {
            indexByID[card.id] = index
        }

        var addedCount = 0
        var updatedCount = 0
        for card in newPlaceCards where reachableBoardIDs.contains(card.boardId) {
            guard let index = indexByID[card.id] else {
                indexByID[card.id] = placeCards.count
                // Appended as-is, not through `save(_:)` — that stamps
                // `updatedAt` with now, which would relabel every restored
                // card as freshly edited and break the comparison above on
                // the next restore.
                placeCards.append(card)
                addedCount += 1
                continue
            }
            guard card.updatedAt > placeCards[index].updatedAt else { continue }
            placeCards[index] = card
            updatedCount += 1
        }

        // Written straight through rather than queued. Restoring a backup
        // is rare, user-initiated and high-stakes — the one write worth
        // blocking on, since losing it would mean the user watched a
        // restore succeed and then found their library unchanged.
        persistNow()
        return (addedBoards.count, addedCount, updatedCount)
    }

    /// Writes both files immediately, on this actor, bypassing the queue.
    /// Used for a backup restore (above) and when the app leaves the
    /// foreground: a queued write is the one that might not get to run
    /// before the process is suspended or killed, and the in-memory arrays
    /// are already the newest state, so nothing is needed from the queue
    /// to write them.
    func persistNow() {
        encodeAndWriteJSON(boards, to: boardsFileURL)
        encodeAndWriteJSON(placeCards, to: placeCardsFileURL)
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
        boardsGeneration += 1
        let generation = boardsGeneration
        let snapshot = boards
        let url = boardsFileURL
        Task { await writer.writeBoards(snapshot, generation: generation, to: url) }
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
        placeCardsGeneration += 1
        let generation = placeCardsGeneration
        let snapshot = placeCards
        let url = placeCardsFileURL
        Task { await writer.writePlaceCards(snapshot, generation: generation, to: url) }
    }
}

/// Encoding and writing one storage file. Kept at file scope so both the
/// background writer and `StorageService.persistNow()` can call it without
/// either having to reach into the other's isolation.
private func encodeAndWriteJSON<Value: Encodable>(_ value: Value, to url: URL) {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    guard let data = try? encoder.encode(value) else { return }
    try? data.write(to: url, options: .atomic)
}

/// Where a save actually hits the disk, away from the main actor.
///
/// A save used to encode the *entire* library and rewrite the whole file
/// synchronously, on the main actor, and `save(_:)` is called from 29
/// places — ten of them in the detail screen alone, on things as ordinary
/// as toggling "✓ 방문". With a thousand cards of forty-odd fields each
/// that is a megabyte or more of JSON encoded on the main thread for one
/// tap, and a twenty-five card import did the whole thing twenty-five
/// times over. None of that work belongs on the thread drawing the UI.
///
/// Being an actor also serializes the writes, so two saves can never be
/// interleaved mid-file. What it deliberately does not do is delay
/// anything: there is no debounce window during which a termination would
/// lose the last edit. Instead each snapshot carries a generation, and one
/// that arrives after a newer one has already been written is dropped —
/// which keeps the file correct under `Task`'s unordered scheduling and,
/// as a side effect, skips the encode entirely for snapshots a burst has
/// already superseded.
private actor LibraryFileWriter {
    private var newestBoardsGeneration = 0
    private var newestPlaceCardsGeneration = 0

    func writeBoards(_ boards: [Board], generation: Int, to url: URL) {
        guard generation > newestBoardsGeneration else { return }
        newestBoardsGeneration = generation
        encodeAndWriteJSON(boards, to: url)
    }

    func writePlaceCards(_ placeCards: [PlaceCard], generation: Int, to url: URL) {
        guard generation > newestPlaceCardsGeneration else { return }
        newestPlaceCardsGeneration = generation
        encodeAndWriteJSON(placeCards, to: url)
    }
}
