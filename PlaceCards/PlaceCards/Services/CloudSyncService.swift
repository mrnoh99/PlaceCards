import Foundation
import CloudKit

/// 기기 사이 동기화(CloudKit)의 **첫 단계** — 지금은 연결이 되는지만 본다.
///
/// 카드를 올리지도 내려받지도 않는다. 저장은 여전히 `StorageService`의
/// JSON 파일이 전부이고, 이 타입은 거기에 손대지 않는다. 그래서 여기가
/// 잘못돼도 데이터에는 아무 영향이 없다 — 동기화처럼 되돌리기 어려운
/// 작업을 한 번에 넣지 않고, 먼저 **닿는지부터** 확인하려는 것이다.
///
/// 확인할 것이 셋이다. 셋 다 실패 모양이 다르고, 사용자가 할 수 있는
/// 일도 다르다:
///
/// 1. **컨테이너가 앱에 붙어 있는가** — Xcode에서 iCloud 기능의 CloudKit을
///    켜야 프로비저닝 프로파일에 들어간다. 안 켜면 코드가 맞아도 조용히
///    실패한다(App Group 때와 같은 종류의 설정 단계다).
/// 2. **iCloud 계정이 있는가** — 로그인 안 함/제한됨/일시적 불가가 각각
///    다르다.
/// 3. **실제로 왕복이 되는가** — 위 둘이 통과해도 네트워크나 권한에서
///    막힐 수 있다. 사용자 레코드 id를 한 번 받아 보는 것으로 확인한다.
///    이건 읽기 한 번이고 아무것도 쓰지 않는다.
@MainActor
final class CloudSyncService: ObservableObject {
    /// `PlaceCards.entitlements`에 이미 있던 컨테이너. 새로 만들지 않는다 —
    /// 지금 iCloud 백업(`CloudBackupService`)이 쓰는 바로 그 컨테이너이고,
    /// CloudKit은 같은 컨테이너 안의 다른 저장소를 쓴다.
    static let containerIdentifier = "iCloud.com.mrnoh99.PlaceCards"

    enum Status: Equatable {
        case notChecked
        case checking
        /// 왕복까지 확인됨. 사람이 읽을 것은 아니지만, 두 기기가 **같은**
        /// 계정을 보고 있는지 눈으로 맞춰 볼 수 있어 같이 내보인다.
        case ready(accountTag: String)
        case noAccount
        case restricted
        /// 컨테이너를 못 찾거나 왕복이 실패했다. 사용자에게 보일 이유가
        /// 딸려 온다.
        case unavailable(String)

        var isReady: Bool {
            if case .ready = self { return true }
            return false
        }
    }

    @Published private(set) var status: Status = .notChecked

    func check() async {
        status = .checking
        let container = CKContainer(identifier: Self.containerIdentifier)

        let accountStatus: CKAccountStatus
        do {
            accountStatus = try await fetchAccountStatus(of: container)
        } catch {
            status = .unavailable(error.localizedDescription)
            return
        }

        switch accountStatus {
        case .available:
            break
        case .noAccount:
            status = .noAccount
            return
        case .restricted:
            status = .restricted
            return
        case .couldNotDetermine:
            status = .unavailable("iCloud 상태를 확인하지 못했습니다.".localized)
            return
        case .temporarilyUnavailable:
            status = .unavailable("iCloud를 일시적으로 쓸 수 없습니다.".localized)
            return
        @unknown default:
            // 새 case가 생겨도 "된다"고 단정하지 않는다. 확인이 목적인
            // 화면에서 모르는 상태를 초록으로 칠하면 확인이 아니게 된다.
            status = .unavailable("알 수 없는 iCloud 상태입니다.".localized)
            return
        }

        // 계정이 있다고 왕복이 된다는 뜻은 아니다. 한 번 읽어 본다.
        do {
            let recordID = try await fetchUserRecordID(of: container)
            status = .ready(accountTag: String(recordID.recordName.prefix(8)))
        } catch {
            status = .unavailable(error.localizedDescription)
        }
    }

    /// 완료 핸들러를 받는 쪽만 쓰고 컨티뉴에이션으로 감싼다 — 컴파일
    /// 검증이 CI뿐이라(CLAUDE.md §1) 어느 SDK에서나 확실히 있는 쪽을
    /// 고른다. `PhotoLibraryAlbum`도 같은 이유로 그렇게 돼 있다.
    private func fetchAccountStatus(of container: CKContainer) async throws -> CKAccountStatus {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKAccountStatus, Error>) in
            container.accountStatus { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
    }

    // MARK: - 주고받기 (3-b-1 올리기, 3-b-2 내려받아 병합)

    /// 동기화 진행 상태. `Status`(연결 확인)와 따로 둔다 — 연결이 됐다고
    /// 주고받은 적이 있는 건 아니고, 화면에서도 두 줄로 나뉘어 보인다.
    enum SyncState: Equatable {
        case idle
        case preparing
        case receiving
        case sending(done: Int, total: Int)
        case photos(done: Int, total: Int)
        /// `added`·`updated`는 내려받아 병합한 결과, `uploaded`는 올린 카드
        /// 수다. 셋을 따로 보인다 — `updated`는 이 기기의 카드가 다른 기기
        /// 것으로 **바뀌었다**는 뜻이라, 사용자가 예상과 다르면 바로 알아채야
        /// 한다. 사진은 오간 장수를 따로 센다.
        case finished(
            added: Int, updated: Int, uploaded: Int,
            photosReceived: Int, photosSent: Int
        )
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .preparing, .receiving, .sending, .photos: return true
            case .idle, .finished, .failed: return false
            }
        }
    }

    @Published private(set) var syncState: SyncState = .idle

    /// 기본 존이 아니라 따로 만든 존에 넣는다. 나중에 "지난번 이후 바뀐
    /// 것만" 받아 오려면(`CKFetchRecordZoneChangesOperation`) 사용자 지정
    /// 존이어야 하고, 기본 존에 부어 두면 그때 통째로 옮겨야 한다.
    private static let zoneName = "PlaceCards"
    private static let cardRecordType = "PlaceCardDoc"
    private static let boardRecordType = "BoardDoc"
    /// 사진은 **다른 존**에 둔다. 카드 존은 동기화할 때마다 통째로 받는데,
    /// 사진이 같은 존에 있으면 그때마다 사진까지 전부 내려받는다. 존이
    /// 나뉘어 있으면 사진 쪽은 `desiredKeys = []`로 **이름만** 받아 무엇이
    /// 이미 있는지 보고, 없는 것만 골라 주고받을 수 있다.
    private static let photoZoneName = "PlaceCardsPhotos"
    private static let photoRecordType = "PhotoAsset"
    private static let photoFieldKey = "file"
    /// 사진은 레코드 하나가 수백 KB다. 카드처럼 200개씩 묶으면 한 번에
    /// 오가는 양이 너무 커진다.
    private static let photoBatchSize = 10
    /// CloudKit의 한 번 요청 한도는 400건이다. 절반쯤에서 끊어 여유를 둔다.
    private static let batchSize = 200

    /// **먼저 내려받아 병합하고, 그 다음에 올린다.** 순서가 이 함수의 전부다.
    ///
    /// 올리기는 `savePolicy = .allKeys`, 즉 이 기기 것으로 무조건 덮는다.
    /// 그래서 올리기 전에 다른 기기 것을 받아 병합해 두지 않으면 다른
    /// 기기의 더 나중 수정이 그대로 사라진다. 받아서 병합한 뒤에 올리면
    /// 올라가는 것이 이미 **합쳐진 결과**이므로 덮어도 잃는 것이 없다.
    ///
    /// 같은 이유로 **받기가 실패하면 올리지 않고 멈춘다.** 받기에 실패한
    /// 채로 올리는 것이 이 기능에서 자료를 잃는 유일한 길이다.
    ///
    /// 병합 규칙은 새로 만들지 않고 `StorageService.merge`를 그대로 쓴다 —
    /// 백업 복원이 쓰는 바로 그 규칙이다: 이 기기에 없는 카드는 추가,
    /// `updatedAt`이 더 나중인 카드는 그 내용으로 교체, 클라우드에 없는
    /// 카드는 건드리지 않는다. 보드는 없으면 추가하고 바꾸지는 않는다
    /// (`Board`에는 `updatedAt`이 없어 견줄 것이 없다). 이미 쓰이고 있는
    /// 규칙을 재사용하는 것이, 여기서 컴파일조차 확인할 수 없는(CLAUDE.md §1)
    /// 병합 코드를 새로 쓰는 것보다 안전하다.
    ///
    /// 레코드 한 장에 카드 하나를 통째로 JSON으로 넣는다. 필드를 하나씩
    /// 펼치지 않는 이유는 `PlaceCard`에 필드가 계속 붙기 때문이다 — 펼쳐
    /// 두면 필드가 늘 때마다 CloudKit 스키마와 짝을 맞춰야 하고, 그걸
    /// 빠뜨리면 그 필드만 조용히 사라진다. 사진은 파일 이름만 들어 있어
    /// (`MediaItem.localPath`) 레코드가 작다. 사진 자체는 다음 단계다 —
    /// 그때까지 다른 기기에서 받은 카드의 사진은 이 기기에 파일이 없어
    /// 빈 자리로 보인다(`MediaStore.loadImage`가 nil을 돌려준다).
    ///
    /// 삭제됨으로 옮긴 카드(`deletedAt`이 있는 것)도 같이 주고받는다. 그게
    /// 카드의 지금 상태다. 다만 `purge`로 아주 지운 카드는 배열에서 사라져
    /// 묘비가 남지 않으므로, 다른 기기에 남아 있으면 되살아난다 — 삭제
    /// 전파(3-b-3)에서 풀 문제다.
    func syncNow(storageService: StorageService) async {
        guard !syncState.isBusy else { return }
        syncState = .preparing

        if !status.isReady {
            await check()
        }
        guard status.isReady else {
            syncState = .failed("iCloud 연결을 먼저 확인해주세요.".localized)
            return
        }

        let database = CKContainer(identifier: Self.containerIdentifier).privateCloudDatabase
        let zone = CKRecordZone(zoneName: Self.zoneName)

        do {
            try await createZoneIfNeeded(zone, in: database)
        } catch {
            syncState = .failed(error.localizedDescription)
            return
        }

        // 1) 받아서 병합. 실패하면 여기서 끝이다 — 위 주석 참고.
        syncState = .receiving
        let received: ReceiveResult
        do {
            received = try await receiveAndMerge(from: database, zoneID: zone.zoneID, into: storageService)
        } catch {
            syncState = .failed(error.localizedDescription)
            return
        }

        // 2) 병합이 끝난 **뒤에** 읽는다. 병합 전에 읽어 두면 방금 받은
        //    것이 빠진 채로 올라가고, `.allKeys`가 그걸 서버에 덮는다.
        let cards = storageService.placeCards
        let boards = storageService.boards

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        var records: [CKRecord] = []
        do {
            // 읽지 못한 id는 뺀다. 그 자리는 서버에 있는 그대로 둔다.
            for board in boards where !received.unreadableIDs.contains(board.id) {
                let record = CKRecord(
                    recordType: Self.boardRecordType,
                    recordID: CKRecord.ID(recordName: board.id, zoneID: zone.zoneID)
                )
                let payload = try encoder.encode(board)
                record["payload"] = payload
                record["updatedAt"] = board.createdAt
                records.append(record)
            }
            for card in cards where !received.unreadableIDs.contains(card.id) {
                let record = CKRecord(
                    recordType: Self.cardRecordType,
                    recordID: CKRecord.ID(recordName: card.id, zoneID: zone.zoneID)
                )
                let payload = try encoder.encode(card)
                record["payload"] = payload
                record["updatedAt"] = card.updatedAt
                records.append(record)
            }
        } catch {
            syncState = .failed(error.localizedDescription)
            return
        }

        let total = records.count
        guard total > 0 else {
            await finishWithPhotos(database: database, storageService: storageService,
                                   received: received, uploaded: 0)
            return
        }

        var sent = 0
        var index = 0
        while index < total {
            let end = min(index + Self.batchSize, total)
            let slice = Array(records[index..<end])
            do {
                try await save(slice, in: database)
            } catch {
                syncState = .failed(error.localizedDescription)
                return
            }
            sent += slice.count
            index = end
            syncState = .sending(done: sent, total: total)
        }

        await finishWithPhotos(database: database, storageService: storageService,
                               received: received, uploaded: total)
    }

    /// 카드가 다 오간 뒤 사진을 주고받고 결과를 낸다.
    ///
    /// 사진이 실패해도 **카드는 이미 끝났다.** 병합은 디스크에 쓰였고 올리기도
    /// 됐다. 그래서 사진 실패를 통째로 실패처럼 보이게 하지 않고, 사진 쪽이
    /// 안 됐다고만 말한다 — 다음 동기화 때 이름으로 견주어 다시 대상이 된다.
    private func finishWithPhotos(
        database: CKDatabase,
        storageService: StorageService,
        received: ReceiveResult,
        uploaded: Int
    ) async {
        syncState = .photos(done: 0, total: 0)
        do {
            let photos = try await syncPhotos(in: database, storageService: storageService)
            syncState = .finished(
                added: received.added, updated: received.updated, uploaded: uploaded,
                photosReceived: photos.received, photosSent: photos.sent
            )
        } catch {
            syncState = .failed("사진을 주고받지 못했습니다(장소는 끝났습니다): ".localized
                                + error.localizedDescription)
        }
    }

    /// 존의 레코드를 전부 받아 디코딩한 뒤 `StorageService.merge`에 넘긴다.
    ///
    /// `CKQueryOperation`이 아니라 `CKFetchRecordZoneChangesOperation`을
    /// 쓴다. 질의는 CloudKit 대시보드에서 필드에 **queryable 색인**을 걸어야
    /// 동작하는데, 스키마가 자동 생성될 때는 그 색인이 안 붙는다 — 코드가
    /// 맞아도 "invalid query" 하나로 끝난다. 존 변경 가져오기는 색인이
    /// 필요 없고, 나중에 "지난번 이후 바뀐 것만" 받는 데 쓸 것도 이쪽이다.
    ///
    /// 지금은 토큰을 저장하지 않고 늘 nil부터 시작한다(= 매번 전부 받는다).
    /// 토큰을 들고 있다가 잘못 쓰면 받아야 할 것을 조용히 건너뛰므로,
    /// 두 기기가 실제로 맞는지 확인되기 전에는 느린 쪽을 고른다.
    /// 받은 결과. `unreadableIDs`는 **레코드는 있는데 이 빌드가 읽지 못한**
    /// 것들이다. 이게 왜 필요한지가 이 단계에서 제일 미묘하다:
    ///
    /// 다른 기기가 먼저 새 버전으로 올라가면, 그 기기가 쓴 레코드에 이
    /// 빌드가 모르는 형태가 들어 있어 디코딩이 실패할 수 있다. 그걸 그냥
    /// 건너뛰고 나서 같은 id의 **이 기기 옛 카드**를 `.allKeys`로 올리면,
    /// 읽지 못했을 뿐 멀쩡하던 최신 내용이 옛 것으로 덮인다. 그래서 읽지
    /// 못한 id는 올릴 때 빼 둔다 — 못 읽은 것은 서버에 그대로 남는다.
    private struct ReceiveResult {
        var added: Int
        var updated: Int
        var unreadableIDs: Set<String>
    }

    private func receiveAndMerge(
        from database: CKDatabase,
        zoneID: CKRecordZone.ID,
        into storageService: StorageService
    ) async throws -> ReceiveResult {
        var records: [CKRecord] = []
        var token: CKServerChangeToken?
        // 한 번에 다 안 오면 토큰을 물고 다시 부른다. `moreComing`이 영영
        // true인 서버 쪽 고장에 매달리지 않도록 횟수를 막아 두되, 막혔을
        // 때 **그냥 진행하지 않고 던진다.** 덜 받은 채로 돌아가면 부른
        // 쪽이 그걸 다 받은 줄 알고 `.allKeys`로 올려서 서버에 있던 것을
        // 지운다 — 이 기능에서 자료를 잃는 길이 그것뿐이다.
        var complete = false
        var unreadable: Set<String> = []
        for _ in 0..<50 {
            let page = try await fetchChanges(from: database, zoneID: zoneID, since: token)
            records.append(contentsOf: page.records)
            unreadable.formUnion(page.failedIDs)
            token = page.token
            if !page.moreComing {
                complete = true
                break
            }
        }
        guard complete else {
            throw PlaceCardsError.networkError("iCloud에서 자료를 다 받지 못했습니다.".localized)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var boards: [Board] = []
        var cards: [PlaceCard] = []
        // 한 장이 깨졌다고 나머지를 버리지는 않는다. 대신 그 id를 적어 두고
        // 올릴 때 뺀다(`ReceiveResult` 주석 참고).
        var unreadableIDs = unreadable
        for record in records {
            let recordName = record.recordID.recordName
            guard let payload = record["payload"] as? Data else {
                unreadableIDs.insert(recordName)
                continue
            }
            if record.recordType == Self.boardRecordType {
                if let board = try? decoder.decode(Board.self, from: payload) {
                    boards.append(board)
                } else {
                    unreadableIDs.insert(recordName)
                }
            } else if record.recordType == Self.cardRecordType {
                if let card = try? decoder.decode(PlaceCard.self, from: payload) {
                    cards.append(card)
                } else {
                    unreadableIDs.insert(recordName)
                }
            }
        }

        // 레코드가 돌아오는 순서는 정해져 있지 않다. `merge`는 없는 보드를
        // 뒤에 붙이므로, 만든 순서로 세워 두면 기기마다 같은 차례가 된다.
        boards.sort { $0.createdAt < $1.createdAt }
        cards.sort { $0.createdAt < $1.createdAt }

        let result = storageService.merge(boards: boards, placeCards: cards)
        return ReceiveResult(added: result.added, updated: result.updated, unreadableIDs: unreadableIDs)
    }

    // MARK: - 사진 (3-c)

    /// 카드가 가리키는 사진 파일을 주고받는다. 카드 쪽 동기화가 **끝난
    /// 뒤에** 부른다 — 그래야 방금 받은 카드의 사진도 같이 가져온다.
    ///
    /// 파일 이름(`MediaItem.localPath`, `UUID().jpg`)을 그대로 레코드
    /// 이름으로 쓴다. 이름이 곧 내용의 신원이라 같은 사진이 두 번 올라갈
    /// 수 없고, "서버에 있는 이름"과 "이 기기에 있는 파일"을 견주는 것만으로
    /// 무엇을 주고받을지 정해진다. 그래서 이미 오간 사진은 다시 오가지
    /// 않는다 — 사진은 카드와 달리 한 장이 수백 KB라 이게 중요하다.
    ///
    /// 카드가 안 가리키는 파일은 올리지 않는다. 이 기기에만 남은 찌꺼기를
    /// 남의 기기까지 옮길 이유가 없다.
    private func syncPhotos(
        in database: CKDatabase,
        storageService: StorageService
    ) async throws -> (received: Int, sent: Int) {
        let zone = CKRecordZone(zoneName: Self.photoZoneName)
        try await createZoneIfNeeded(zone, in: database)

        // 병합이 끝난 뒤의 카드에서 뽑는다.
        var referenced: Set<String> = []
        for card in storageService.placeCards {
            for item in card.media.allItems {
                referenced.insert(item.localPath)
            }
        }
        guard !referenced.isEmpty else { return (0, 0) }

        // 이름만 받는다. 사진 본체는 아직 한 장도 안 온다.
        var onServer: Set<String> = []
        var token: CKServerChangeToken?
        var complete = false
        for _ in 0..<50 {
            let page = try await fetchChanges(
                from: database, zoneID: zone.zoneID, since: token, desiredKeys: []
            )
            for record in page.records {
                onServer.insert(record.recordID.recordName)
            }
            token = page.token
            if !page.moreComing {
                complete = true
                break
            }
        }
        guard complete else {
            throw PlaceCardsError.networkError("iCloud에서 자료를 다 받지 못했습니다.".localized)
        }

        let toReceive = referenced.filter { onServer.contains($0) && !MediaStore.exists(fileName: $0) }
        let toSend = referenced.filter { !onServer.contains($0) && MediaStore.exists(fileName: $0) }
        let total = toReceive.count + toSend.count
        guard total > 0 else { return (0, 0) }

        var done = 0
        var received = 0
        var sent = 0

        // 이름 순으로 세워 둔다. `Set`을 그냥 돌면 순서가 실행마다 달라져
        // 중간에 끊겼을 때 무엇까지 됐는지 종잡을 수 없다.
        let receiveList = toReceive.sorted()
        var index = 0
        while index < receiveList.count {
            let end = min(index + Self.photoBatchSize, receiveList.count)
            let ids = receiveList[index..<end].map {
                CKRecord.ID(recordName: $0, zoneID: zone.zoneID)
            }
            received += try await downloadPhotos(ids: ids, from: database)
            done += ids.count
            index = end
            syncState = .photos(done: done, total: total)
        }

        let sendList = toSend.sorted()
        index = 0
        while index < sendList.count {
            let end = min(index + Self.photoBatchSize, sendList.count)
            var records: [CKRecord] = []
            for fileName in sendList[index..<end] {
                let record = CKRecord(
                    recordType: Self.photoRecordType,
                    recordID: CKRecord.ID(recordName: fileName, zoneID: zone.zoneID)
                )
                record[Self.photoFieldKey] = CKAsset(fileURL: MediaStore.fileURL(fileName: fileName))
                records.append(record)
            }
            try await save(records, in: database)
            sent += records.count
            done += records.count
            index = end
            syncState = .photos(done: done, total: total)
        }

        return (received, sent)
    }

    /// 받은 자산을 **블록 안에서 바로 파일로 쓴다.** 두 가지 이유다:
    /// `CKAsset`이 가리키는 임시 파일은 연산이 끝나면 사라지고, 사진 여러
    /// 장을 `Data`로 들고 있다가 나중에 쓰면 그만큼 메모리에 쌓인다.
    private func downloadPhotos(ids: [CKRecord.ID], from database: CKDatabase) async throws -> Int {
        let collector = PhotoCollector()
        // 블록은 CloudKit의 배경 큐에서 돈다. 이 타입이 `@MainActor`라
        // `Self.`로 꺼내는 값도 같이 격리되므로, 블록 밖에서 미리 꺼내 둔다.
        let fieldKey = Self.photoFieldKey
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKFetchRecordsOperation(recordIDs: ids)
            operation.perRecordResultBlock = { recordID, result in
                guard case .success(let record) = result,
                      let asset = record[fieldKey] as? CKAsset,
                      let fileURL = asset.fileURL,
                      let data = try? Data(contentsOf: fileURL) else { return }
                // 한 장이 실패해도 나머지는 받는다. 못 받은 사진은 다음
                // 동기화 때 다시 대상이 된다 — 이름으로 견주기 때문이다.
                if (try? MediaStore.writeData(data, fileName: recordID.recordName)) != nil {
                    collector.written += 1
                }
            }
            operation.fetchRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: ())
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
        return collector.written
    }

    private final class PhotoCollector {
        var written = 0
    }

    private struct ChangePage {
        var records: [CKRecord]
        /// 서버가 있다고는 했는데 가져오지 못한 레코드. 못 받은 것을 이
        /// 기기 것으로 덮지 않으려면 id가 남아 있어야 한다.
        var failedIDs: Set<String>
        var token: CKServerChangeToken?
        var moreComing: Bool
    }

    /// 결과 블록들은 CloudKit의 제 큐에서 불린다. 그 안에서 모은 것을
    /// 밖으로 꺼내려면 참조 타입이 하나 있어야 한다 — `MediaStore`의
    /// `IdentifierBox`와 같은 이유, 같은 모양이다.
    private final class ChangeCollector {
        var records: [CKRecord] = []
        var token: CKServerChangeToken?
        var moreComing = false
        var failedIDs: Set<String> = []
        /// 존 하나가 실패한 것을 여기 담아 두었다가 밖에서 던진다. 이걸
        /// 흘려보내면 못 받은 것이 "받을 게 없었다"와 구별되지 않는다.
        var zoneError: Error?
    }

    /// `desiredKeys`에 빈 배열을 넘기면 **필드를 하나도 안 실어** 보낸다.
    /// 사진 존에서 "무엇이 이미 올라가 있나"만 알아볼 때 쓴다 — 그걸 위해
    /// 사진 본체까지 받아 오면 안 받으려고 확인하는 의미가 없어진다.
    /// nil이면 평소대로 전부 싣는다.
    private func fetchChanges(
        from database: CKDatabase,
        zoneID: CKRecordZone.ID,
        since token: CKServerChangeToken?,
        desiredKeys: [CKRecord.FieldKey]? = nil
    ) async throws -> ChangePage {
        let collector = ChangeCollector()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let configuration = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
            configuration.previousServerChangeToken = token
            configuration.desiredKeys = desiredKeys
            let operation = CKFetchRecordZoneChangesOperation(
                recordZoneIDs: [zoneID],
                configurationsByRecordZoneID: [zoneID: configuration]
            )
            operation.recordWasChangedBlock = { recordID, result in
                switch result {
                case .success(let record):
                    collector.records.append(record)
                case .failure:
                    collector.failedIDs.insert(recordID.recordName)
                }
            }
            operation.recordZoneFetchResultBlock = { _, result in
                switch result {
                case .success(let value):
                    collector.token = value.serverChangeToken
                    collector.moreComing = value.moreComing
                case .failure(let error):
                    collector.zoneError = error
                }
            }
            operation.fetchRecordZoneChangesResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: ())
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
        // 전체는 성공했다고 나와도 존 하나가 실패했을 수 있다. 그 경우를
        // 성공으로 돌려보내면 덜 받은 것을 다 받은 것으로 치게 된다.
        if let zoneError = collector.zoneError {
            throw zoneError
        }
        return ChangePage(
            records: collector.records,
            failedIDs: collector.failedIDs,
            token: collector.token,
            moreComing: collector.moreComing
        )
    }

    /// 이미 있으면 그대로 둔다. `CKModifyRecordZonesOperation`은 같은 존을
    /// 다시 저장해도 오류가 아니므로 "있는지 먼저 보고 없으면 만든다"를
    /// 하지 않는다 — 그 두 단계 사이에 다른 기기가 만들면 어차피 어긋난다.
    private func createZoneIfNeeded(_ zone: CKRecordZone, in database: CKDatabase) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKModifyRecordZonesOperation(
                recordZonesToSave: [zone],
                recordZoneIDsToDelete: nil
            )
            operation.modifyRecordZonesResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: ())
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }

    /// `savePolicy`가 `.allKeys`인 것이 이 단계의 전부다. 기본값
    /// (`.ifServerRecordUnchanged`)이면 서버에 이미 있는 레코드마다
    /// 충돌로 실패한다 — 방금 만든 `CKRecord`에는 서버가 준 변경 태그가
    /// 없기 때문이다. `.allKeys`는 태그를 보지 않고 이 기기 것으로 덮는다.
    /// 지금은 올리기만 하므로 "이 기기가 이긴다"가 맞는 규칙이다. 양쪽을
    /// 주고받기 시작하면 이 규칙부터 다시 봐야 한다.
    private func save(_ records: [CKRecord], in database: CKDatabase) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
            operation.savePolicy = .allKeys
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: ())
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }

    private func fetchUserRecordID(of container: CKContainer) async throws -> CKRecord.ID {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKRecord.ID, Error>) in
            container.fetchUserRecordID { recordID, error in
                if let recordID {
                    continuation.resume(returning: recordID)
                } else {
                    continuation.resume(
                        throwing: error ?? PlaceCardsError.networkError("iCloud 사용자 정보를 받지 못했습니다.".localized)
                    )
                }
            }
        }
    }
}
