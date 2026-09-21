import Foundation
import Combine

/// Local, on-device storage for Boards and their PlaceCards, as two JSON
/// files in the app's documents directory. Kept deliberately simple (no
/// CoreData/SwiftData) so the schema can evolve freely while the data model
/// is still settling.
/// 삭제됨에 이만큼 머문 카드는 저절로 지워진다.
///
/// `StorageService`가 `@MainActor`라 그 안에 두면 화면의 평범한 계산
/// 프로퍼티(`TrashView.retentionNotice`)에서 읽는 것이 액터를 넘는 일이
/// 된다. 바꿀 일 없는 숫자 하나일 뿐이므로 클래스 밖에 둔다.
let trashRetention: TimeInterval = 30 * 24 * 60 * 60

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

    /// 보드를 없애고, 그 보드에 들어 있던 카드에서는 이 보드만 뺀다.
    ///
    /// 예전에는 보드 안의 카드를 사진째로 같이 지웠다. 카드가 보드
    /// 하나에만 속하던 때는 그게 "고아를 남기지 않는" 방법이었지만, 이제
    /// 한 카드가 여러 보드에 들어가므로 다른 보드에서 멀쩡히 쓰이는 카드를
    /// 같이 데려가게 된다. 어느 보드에도 안 남게 된 카드는 지워지지 않고
    /// "모든 카드"에 남는다.
    ///
    /// 화면은 여전히 빈 보드에만 삭제를 내주므로(`HomeView`) 이 반복문이
    /// 실제로 도는 일은 드물다.
    func deleteBoard(_ board: Board) {
        for card in placeCards where card.boardIDs.contains(board.id) {
            var updated = card
            updated.boardIDs = updated.boardIDs.filter { $0 != board.id }
            save(updated)
        }
        boards.removeAll { $0.id == board.id }
        persistBoards()
    }

    // MARK: - PlaceCards

    /// 삭제됨에 들어 있지 않은 카드 전부 — "모든 카드"가 세는 것이고,
    /// 갤러리·지도·검색이 보는 것이다. `placeCards`는 삭제된 것까지 들고
    /// 있으므로 화면에서 그대로 쓰면 안 된다.
    var activePlaceCards: [PlaceCard] {
        placeCards.filter { !$0.isDeleted }
    }

    /// 다른 앱이 공유해 준 정보로 만들어진 카드 — 홈의 "가져오기"가
    /// 세고 보여 주는 것. 보드와 달리 소속이 아니라 출신이므로, 이 카드들은
    /// 자기 보드에도 그대로 들어 있다.
    var importedPlaceCards: [PlaceCard] {
        activePlaceCards.filter { $0.isImported == true }
    }

    /// 삭제됨에 들어 있는 카드. 최근에 옮긴 것이 위로 온다.
    var deletedPlaceCards: [PlaceCard] {
        placeCards
            .filter(\.isDeleted)
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    func placeCards(inBoard boardId: String) -> [PlaceCard] {
        placeCards.filter { !$0.isDeleted && $0.boardIDs.contains(boardId) }
    }

    /// 카드를 보드 하나에 더 넣는다. 이미 들어 있으면 아무 일도 없다.
    func addToBoard(_ placeCard: PlaceCard, boardID: String) {
        guard !placeCard.boardIDs.contains(boardID) else { return }
        var card = placeCard
        card.boardIDs = card.boardIDs + [boardID]
        save(card)
    }

    /// "가져오기"에서만 뺀다. 삭제가 아니다 — 카드는 제 보드에 그대로
    /// 남고, 어느 보드에도 없더라도 "모든 카드"에는 남는다.
    ///
    /// 보드와 달리 소속이 아니라 출신이라 `boardIDs`가 아니라 표시를
    /// 지운다. 한 번 빼면 다시 넣을 길은 없다 — 들어온 경로는 만들 때
    /// 한 번만 알 수 있기 때문이다.
    ///
    /// 손으로 빼는 길이 이것이고, `save(_:)`가 장소 확정을 보고 저절로
    /// 빼기도 한다(거기 주석 참고).
    func removeFromImported(_ placeCard: PlaceCard) {
        guard placeCard.isImported == true else { return }
        var card = placeCard
        card.isImported = nil
        save(card)
    }

    /// 보드 하나에서만 뺀다. 삭제가 아니다.
    ///
    /// 마지막 보드였다면 카드는 어느 보드에도 속하지 않게 되지만 그대로
    /// 남아 "모든 카드"에서 보인다 — Lightroom에서 앨범에서 뺀 사진이
    /// 모든 사진에는 남아 있는 것과 같다.
    func removeFromBoard(_ placeCard: PlaceCard, boardID: String) {
        var card = placeCard
        card.boardIDs = card.boardIDs.filter { $0 != boardID }
        save(card)
    }

    func save(_ placeCard: PlaceCard) {
        var card = placeCard
        card.updatedAt = Date()
        if let index = placeCards.firstIndex(where: { $0.id == card.id }) {
            // "가져오기"는 받은 것을 쌓아 두는 곳이지 머무는 곳이 아니다.
            // 장소가 확정되면 그 카드에 대해 할 일이 끝난 것이므로 여기서
            // 내보낸다 — 그러지 않으면 손본 것과 아직 안 본 것이 한데
            // 섞여, 무엇이 남았는지 알아보려면 하나하나 열어 봐야 한다.
            //
            // **확정된 상태가 아니라 확정되는 순간을 본다.** 상태만 보면
            // 확정된 채로 들어오는 카드(이미 검증된 Google 지도 링크
            // 공유)가 "가져오기"에 한 번도 안 보이고 지나간다. 공유로
            // 들어온 것은 전부 거기 모인다는 것이 이 앱의 약속이라
            // 그러면 안 된다. 새 카드(아래 else)를 건드리지 않는 것도
            // 같은 이유다.
            //
            // 저장하는 길이 여럿이라(카드 편집의 Google 새로고침, 검색
            // 결과 고르기, 공유 시트의 자동 확정) 그 하나하나에 붙이는
            // 대신 전부가 지나가는 이 한곳에 둔다.
            if card.isImported == true, card.isPlaceConfirmed, !placeCards[index].isPlaceConfirmed {
                card.isImported = nil
            }
            placeCards[index] = card
        } else {
            placeCards.append(card)
        }
        persistPlaceCards()
    }

    /// 삭제됨으로 옮긴다. 예전에는 이 함수가 사진 파일까지 디스크에서
    /// 지우는 되돌릴 수 없는 삭제였다 — 이제 되돌릴 수 있어야 하므로
    /// 표시만 남기고, 진짜로 지우는 일은 `purge(_:)`가 한다.
    ///
    /// 보드 목록은 건드리지 않는다. 화면들이 `isDeleted`로 걸러내므로
    /// 카드는 모든 보드와 "모든 카드"에서 사라지고, `restore(_:)`가
    /// 표시만 지우면 있던 자리로 돌아온다.
    func delete(_ placeCard: PlaceCard) {
        guard !placeCard.isDeleted else { return }
        var card = placeCard
        card.deletedAt = Date()
        save(card)
    }

    func restore(_ placeCard: PlaceCard) {
        guard placeCard.isDeleted else { return }
        var card = placeCard
        card.deletedAt = nil
        save(card)
    }

    /// 되돌릴 수 없다. 사진 파일까지 디스크에서 지운다 — 예전
    /// `delete(_:)`가 하던 일 그대로다.
    func purge(_ placeCard: PlaceCard) {
        for item in placeCard.media.allItems {
            MediaStore.delete(fileName: item.localPath)
        }
        placeCards.removeAll { $0.id == placeCard.id }
        persistPlaceCards()
    }

    func emptyTrash() {
        // `deletedPlaceCards`는 그때그때 새로 만든 배열이라, 그 안을 돌며
        // `placeCards`를 줄여도 문제되지 않는다.
        for card in deletedPlaceCards {
            purge(card)
        }
    }

    /// 앱이 뜰 때 한 번 돈다(`MainTabView`). 삭제됨을 그냥 두면 사진
    /// 파일이 영원히 남아 저장 공간을 먹는다.
    func purgeExpiredTrash(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-trashRetention)
        for card in placeCards where (card.deletedAt.map { $0 < cutoff } ?? false) {
            purge(card)
        }
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
        // somewhere it can never be seen. 보드가 하나도 없는 카드는
        // 예외다 — 이제 "모든 카드"에서 보이므로 닿을 수 있다.
        let reachableBoardIDs = existingBoardIDs.union(newBoards.map(\.id))
        var indexByID: [String: Int] = [:]
        for (index, card) in placeCards.enumerated() {
            indexByID[card.id] = index
        }

        var addedCount = 0
        var updatedCount = 0
        for card in newPlaceCards where card.boardIDs.isEmpty
            || card.boardIDs.contains(where: reachableBoardIDs.contains) {
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
        // 삭제됨에 있는 카드는 검색에도 안 걸린다.
        activePlaceCards.filter { card in
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
