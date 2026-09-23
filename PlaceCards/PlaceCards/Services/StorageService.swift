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
    /// 디스크의 사진 파일이 바뀐 횟수.
    ///
    /// **화면을 다시 그리게 하려고만 있다.** 사진은 `boards`·`placeCards`가
    /// 아니라 파일로 사는데, 그 파일이 나중에 도착하는 경우가 있다 —
    /// 동기화는 카드·게시판을 **먼저** 병합하고 사진을 **그 뒤에** 받아
    /// 오고(`CloudSyncService.finishWithPhotos`), 백업 복원도 병합이 끝난
    /// 뒤에 사진을 쓴다(`BackupService.restore(bundleAt:)`).
    ///
    /// 그 사이 모델은 이미 바뀌어 화면이 한 번 그려졌으므로, 사진이 도착해도
    /// 다시 그릴 이유가 없다. 그래서 표지 사진이 **앱을 닫았다 열어야**
    /// 나타났다(사용자 신고).
    @Published private(set) var mediaGeneration: Int = 0

    /// 사진 파일이 디스크에서 바뀌었다고 알린다. 모델은 안 건드린다.
    func mediaDidChange() {
        mediaGeneration &+= 1
    }

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
        loadPurgedIDs()
    }

    func acknowledgeLoadFailure() {
        loadFailureMessage = nil
    }

    // MARK: - 지운 기록(묘비)

    /// 아주 지운 카드의 id와 지운 시각.
    ///
    /// `purge`가 배열에서 카드를 통째로 없애므로, 동기화 쪽에서 보면 "지웠다"는
    /// 사실이 **어디에도 남지 않는다.** 그러면 클라우드에 남아 있는 그 카드가
    /// 다음에 받을 때 "이 기기에 없는 카드"로 보여 그대로 되살아난다. 실제로
    /// 지우는 길 넷이 전부 그렇게 되돌려진다 — 휴지통의 영구 삭제, 휴지통
    /// 비우기, 기한 지난 것 자동 정리(`purgeExpiredTrash`, 앱이 뜰 때마다
    /// 돈다), 그리고 중복 카드 합치기.
    ///
    /// 라이브러리 파일이 아니라 `UserDefaults`에 둔다. 이건 사용자 자료가
    /// 아니라 동기화 장부이고, 세대 번호로 순서를 지키는 파일 쓰기 경로
    /// (`LibraryFileWriter`)를 하나 더 늘리지 않는 편이 안전하다. 잃어버려도
    /// 최악이 "지운 카드가 한 번 돌아온다"이다.
    ///
    /// 지우지 않고 쌓아 둔다. 한 건이 수십 바이트라 자랄 걱정보다, 잘못
    /// 지워서 카드가 되살아나는 쪽이 훨씬 나쁘다.
    private static let purgedCardIDsKey = "placecards.purgedCardIDs"
    /// 게시판 묘비. 카드와 **따로** 둔다 — 한 통에 섞으면 id만 보고는
    /// 어느 쪽을 지우라는 것인지 알 수 없다.
    private static let purgedBoardIDsKey = "placecards.purgedBoardIDs"

    @Published private(set) var purgedCardIDs: [String: Date] = [:]
    @Published private(set) var purgedBoardIDs: [String: Date] = [:]

    /// 날짜를 `Double`로 눕혀 둔다. `UserDefaults`가 확실히 받아 주는
    /// 모양이고, 읽을 때 형이 안 맞으면 빈 것으로 시작한다.
    private static func loadTombstones(key: String) -> [String: Date] {
        let raw = UserDefaults.standard.dictionary(forKey: key) as? [String: Double]
        return (raw ?? [:]).mapValues { Date(timeIntervalSince1970: $0) }
    }

    private static func persistTombstones(_ tombstones: [String: Date], key: String) {
        UserDefaults.standard.set(
            tombstones.mapValues { $0.timeIntervalSince1970 },
            forKey: key
        )
    }

    private func loadPurgedIDs() {
        purgedCardIDs = Self.loadTombstones(key: Self.purgedCardIDsKey)
        purgedBoardIDs = Self.loadTombstones(key: Self.purgedBoardIDsKey)
    }

    /// 이미 적힌 것은 시각을 덮지 않는다. 다른 기기에서 받은 "언제 지웠나"가
    /// 이쪽에서 따라 지운 시각으로 바뀌면 안 된다.
    private func recordPurge(_ id: String, at date: Date = Date()) {
        guard purgedCardIDs[id] == nil else { return }
        purgedCardIDs[id] = date
        Self.persistTombstones(purgedCardIDs, key: Self.purgedCardIDsKey)
    }

    private func recordBoardPurge(_ id: String, at date: Date = Date()) {
        guard purgedBoardIDs[id] == nil else { return }
        purgedBoardIDs[id] = date
        Self.persistTombstones(purgedBoardIDs, key: Self.purgedBoardIDsKey)
    }

    /// 다른 기기에서 아주 지운 것을 이 기기에도 적용한다. 아직 여기 남아
    /// 있으면 사진 파일까지 같이 지운다(`purge`가 한다).
    ///
    /// 돌려주는 수는 **실제로 이 기기에서 없앤 카드 수**다. 이미 없던 것은
    /// 세지 않는다 — 화면에 "지움 3"이라고 떴는데 사라진 게 없으면 사용자가
    /// 무슨 일이 난 건지 알 수 없다.
    @discardableResult
    func applyPurges(_ incoming: [String: Date]) -> Int {
        var removed = 0
        for (id, purgedAt) in incoming {
            recordPurge(id, at: purgedAt)
            if let card = placeCards.first(where: { $0.id == id }) {
                purge(card)
                removed += 1
            }
        }
        return removed
    }

    /// 게시판 쪽도 같다. 아직 여기 남아 있으면 `deleteBoard`를 그대로
    /// 태우므로, 그 게시판에 들어 있던 카드에서 이 게시판만 빠지는 처리까지
    /// 똑같이 일어난다 — 카드는 안 지워진다.
    @discardableResult
    func applyBoardPurges(_ incoming: [String: Date]) -> Int {
        var removed = 0
        for (id, purgedAt) in incoming {
            recordBoardPurge(id, at: purgedAt)
            if let board = boards.first(where: { $0.id == id }) {
                deleteBoard(board)
                removed += 1
            }
        }
        return removed
    }

    // MARK: - Boards

    /// `save(_ placeCard:)`가 카드에 하는 것과 같이 시각을 찍는다. 이걸
    /// 안 찍으면 이름을 바꿔도 다른 기기가 그게 더 나중 것인 줄 모른다.
    func saveBoard(_ board: Board) {
        var board = board
        board.updatedAt = Date()
        var replacedCover: String?
        if let index = boards.firstIndex(where: { $0.id == board.id }) {
            if boards[index].coverPhotoPath != board.coverPhotoPath {
                replacedCover = boards[index].coverPhotoPath
            }
            boards[index] = board
        } else {
            boards.append(board)
        }
        sortBoards()
        persistBoards()
        // 갈아치운 표지 사진은 **아무도 안 가리킬 때만** 지운다. 배열을 고친
        // 뒤에 부르는 것이 중요하다 — 그래야 새 표지가 참조로 잡힌다.
        if let replacedCover {
            deleteMediaIfUnreferenced([replacedCover], excluding: "")
        }
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
        // 표지 사진은 **아무도 안 가리킬 때만** 지운다. 카드가 쓰는 사진을
        // 표지로 골랐을 수도 있고, 다른 게시판이 같은 것을 쓸 수도 있다.
        //
        // 위에서 이 게시판을 먼저 뺀 뒤에 부르는 것이 중요하다 — 안 그러면
        // 제 표지가 제 참조로 잡혀 영영 안 지워진다.
        if let path = board.coverPhotoPath {
            deleteMediaIfUnreferenced([path], excluding: "")
        }
        // 묘비를 안 남기면 다음 동기화가 이 게시판을 그대로 되살린다 —
        // 카드 `purge`와 똑같은 이야기다.
        recordBoardPurge(board.id)
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
    /// 손으로 빼는 길이 이것이고, `save(_:)`가 보드로 보내는 것을 보고
    /// 저절로 빼기도 한다(거기 주석 참고).
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
            // 거기 있는 카드가 할 일은 **사용자 보드로 가는 것**이고,
            // 가고 나면 더 있을 이유가 없다 — 그러지 않으면 보낸 것과
            // 아직 안 보낸 것이 한데 섞여, 무엇이 남았는지 알아보려면
            // 하나하나 열어 봐야 한다.
            //
            // **속한 상태가 아니라 새로 속하는 순간을 본다.** 상태만 보면
            // 보드를 달고 들어오는 카드(파일로 들여온 게시판, Google
            // Takeout)가 "가져오기"에 한 번도 안 보이고 지나간다. 바깥에서
            // 받은 것은 전부 거기 모인다는 것이 이 앱의 약속이라 그러면
            // 안 된다. 새 카드(아래 else)를 건드리지 않는 것도 같은
            // 이유다.
            //
            // 보내는 길이 여럿이라(카드 화면의 "보드에 추가", 일괄 작업의
            // 추가와 이동) 그 하나하나에 붙이는 대신 전부가 지나가는 이
            // 한곳에 둔다.
            if card.isImported == true,
               card.boardIDs.contains(where: { !placeCards[index].boardIDs.contains($0) }) {
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

    /// **다른 카드가 아직 가리키고 있으면 사진 파일을 지우지 않는다.**
    ///
    /// 게시판 가져오기(`BackupService.importBoard`)는 카드 id만 새로 매기고
    /// **사진 이름(`MediaItem.localPath`)은 그대로 둔다** — 사진이 그 이름으로
    /// 저장돼 있어야 카드가 찾기 때문이다. 그래서 가져온 카드와 원본이 **같은
    /// 파일**을 가리킨다. 그 상태에서 한쪽을 지우며 파일까지 지우면 **남은
    /// 쪽의 사진이 사라진다** — 사용자 신고로 드러난 실제 데이터 손실이다.
    ///
    /// 삭제됨(휴지통)에 있는 카드도 센다. 되돌릴 수 있는 카드가 가리키는
    /// 사진을 지우면 되돌렸을 때 빈 카드가 된다.
    func deleteMediaIfUnreferenced(_ fileNames: [String], excluding cardID: String) {
        guard !fileNames.isEmpty else { return }
        var stillUsed: Set<String> = []
        for card in placeCards where card.id != cardID {
            for item in card.media.allItems {
                stillUsed.insert(item.localPath)
            }
        }
        // 게시판 표지 사진도 같은 폴더에 산다. 안 세면 카드를 지우다가
        // 표지로 쓰이는 사진을 같이 지울 수 있다.
        for board in boards {
            if let path = board.coverPhotoPath {
                stillUsed.insert(path)
            }
        }
        for fileName in fileNames where !stillUsed.contains(fileName) {
            MediaStore.delete(fileName: fileName)
        }
    }

    /// 되돌릴 수 없다. 사진 파일까지 디스크에서 지운다 — 단, **다른 카드가
    /// 안 가리키는 것만**(`deleteMediaIfUnreferenced`).
    func purge(_ placeCard: PlaceCard) {
        placeCards.removeAll { $0.id == placeCard.id }
        deleteMediaIfUnreferenced(
            placeCard.media.allItems.map(\.localPath), excluding: placeCard.id
        )
        // 묘비를 남기지 않으면 다음 동기화가 이걸 그대로 되돌린다.
        recordPurge(placeCard.id)
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
        // 사진 파일은 살아남은 카드가 가져갔으므로 안 지우지만, 이 카드가
        // 없어졌다는 사실은 `purge`와 똑같이 남겨야 한다 — 안 그러면 합친
        // 중복이 다음 동기화에 되살아난다.
        recordPurge(placeCard.id)
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
    /// 게시판도 카드와 같은 규칙이다 — 없으면 더하고, `changedAt`이 더
    /// 나중이면 그 내용으로 바꾼다. 예전에는 더하기만 했는데 `Board`에
    /// 견줄 시각이 없어서였고, 그 탓에 한 기기에서 바꾼 이름이 다른
    /// 기기로 가지 못했다.
    ///
    /// 끝에 `sortBoards()`로 다시 세운다. 차례는 이제 배열의 자리가 아니라
    /// `Board.sortIndex`에 있고, 그 값은 받아 온 게시판에 실려 온다.
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

        // 이미 있는 게시판은 **더 나중에 고친 쪽**으로 바꾼다. 카드에 쓰는
        // 규칙과 같다. 예전에는 더하기만 하고 여기를 그냥 지나쳤는데,
        // 그때는 `Board`에 견줄 시각이 없었기 때문이다 — 그래서 한 기기에서
        // 이름을 바꿔도 다른 기기에는 옛 이름이 그대로 남았다.
        //
        // 시각이 같으면 넘어간다. 그래야 같은 백업을 두 번 복원해도 두 번째는
        // 아무 일도 안 일어난다.
        for board in newBoards {
            guard let index = boards.firstIndex(where: { $0.id == board.id }) else { continue }
            guard board.changedAt > boards[index].changedAt else { continue }
            boards[index] = board
        }
        // 받아 온 것에 실린 `sortIndex`가 자리를 정한다. 안 세우면 더해진
        // 게시판이 배열 끝에 붙은 채로 남아 기기마다 차례가 달라진다.
        sortBoards()

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
        sortBoards()
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

    /// 왼쪽 목록의 보드 순서를 바꾼다.
    ///
    /// 순서를 적는 필드를 따로 두지 않는다 — **배열 그 자체가 순서다.**
    /// `persistBoards()`가 배열 순서대로 쓰고 읽을 때 그대로 돌아오므로,
    /// 새 필드를 더해 저장 포맷을 건드릴 이유가 없다(백업도 같은 순서로
    /// 오간다).
    /// 차례를 **값으로 굳힌다.** 배열의 자리는 이 기기에만 있는 것이라
    /// 다른 기기로 건너가지 못한다 — 그래서 예전에는 여기서 옮겨 놓아도
    /// 다른 기기의 차례는 그대로였다.
    func moveBoards(fromOffsets source: IndexSet, toOffset destination: Int) {
        boards.move(fromOffsets: source, toOffset: destination)
        let now = Date()
        for index in boards.indices where boards[index].sortIndex != index {
            boards[index].sortIndex = index
            // **바뀐 것에만** 시각을 찍는다. 전부 찍으면 자리를 그대로 지킨
            // 게시판까지 "방금 고친 것"이 되어, 그사이 다른 기기에서 바꾼
            // 이름을 덮는다.
            boards[index].updatedAt = now
        }
        persistBoards()
    }

    /// `Board.orderedBefore`로 세운다. 배열의 자리가 곧 차례이던 때에는
    /// 필요 없었지만, 이제 차례가 `sortIndex`에 있으므로 배열을 거기 맞춰
    /// 둬야 한다 — 화면들은 `boards`를 그냥 위에서부터 그린다.
    private func sortBoards() {
        boards.sort(by: Board.orderedBefore)
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
