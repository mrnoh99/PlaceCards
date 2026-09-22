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

    // MARK: - 올리기 (3-b-1)

    /// 올리기 진행 상태. `Status`(연결 확인)와 따로 둔다 — 연결이 됐다고
    /// 올린 적이 있는 건 아니고, 화면에서도 두 줄로 나뉘어 보인다.
    enum PushState: Equatable {
        case idle
        case preparing
        case pushing(done: Int, total: Int)
        case finished(cards: Int, boards: Int)
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .preparing, .pushing: return true
            case .idle, .finished, .failed: return false
            }
        }
    }

    @Published private(set) var pushState: PushState = .idle

    /// 기본 존이 아니라 따로 만든 존에 넣는다. 나중에 "지난번 이후 바뀐
    /// 것만" 받아 오려면(`CKFetchRecordZoneChangesOperation`) 사용자 지정
    /// 존이어야 하고, 기본 존에 부어 두면 그때 통째로 옮겨야 한다.
    private static let zoneName = "PlaceCards"
    private static let cardRecordType = "PlaceCardDoc"
    private static let boardRecordType = "BoardDoc"
    /// CloudKit의 한 번 요청 한도는 400건이다. 절반쯤에서 끊어 여유를 둔다.
    private static let batchSize = 200

    /// 이 기기의 카드·보드를 iCloud로 **올리기만** 한다. 내려받지 않는다.
    ///
    /// 내려받기를 같이 넣지 않은 이유가 있다. 병합은 되돌리기 어렵고,
    /// 여기서는 컴파일조차 확인할 수 없어(CLAUDE.md §1) 한 번에 검증할 수
    /// 있는 크기를 넘긴다. 올리기만 하는 동안에는 `StorageService`를 읽기만
    /// 하므로 이 기기의 자료가 상할 길이 없다 — 최악이라도 클라우드 쪽이
    /// 틀릴 뿐이고, 그건 다음에 다시 올리면 덮인다.
    ///
    /// 레코드 한 장에 카드 하나를 통째로 JSON으로 넣는다. 필드를 하나씩
    /// 펼치지 않는 이유는 `PlaceCard`에 필드가 계속 붙기 때문이다 — 펼쳐
    /// 두면 필드가 늘 때마다 CloudKit 스키마와 짝을 맞춰야 하고, 그걸
    /// 빠뜨리면 그 필드만 조용히 사라진다. 사진은 파일 이름만 들어 있어
    /// (`MediaItem.localPath`) 레코드가 작다. 사진 자체는 다음 단계다.
    ///
    /// 삭제됨으로 옮긴 카드(`deletedAt`이 있는 것)도 같이 올린다. 그게
    /// 카드의 지금 상태이고, 빼 두면 나중에 내려받기를 붙였을 때 되살아난다.
    func pushAll(storageService: StorageService) async {
        guard !pushState.isBusy else { return }
        pushState = .preparing

        if !status.isReady {
            await check()
        }
        guard status.isReady else {
            pushState = .failed("iCloud 연결을 먼저 확인해주세요.".localized)
            return
        }

        let cards = storageService.placeCards
        let boards = storageService.boards

        let database = CKContainer(identifier: Self.containerIdentifier).privateCloudDatabase
        let zone = CKRecordZone(zoneName: Self.zoneName)

        do {
            try await createZoneIfNeeded(zone, in: database)
        } catch {
            pushState = .failed(error.localizedDescription)
            return
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        var records: [CKRecord] = []
        do {
            for board in boards {
                let record = CKRecord(
                    recordType: Self.boardRecordType,
                    recordID: CKRecord.ID(recordName: board.id, zoneID: zone.zoneID)
                )
                let payload = try encoder.encode(board)
                record["payload"] = payload
                record["updatedAt"] = board.createdAt
                records.append(record)
            }
            for card in cards {
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
            pushState = .failed(error.localizedDescription)
            return
        }

        let total = records.count
        guard total > 0 else {
            pushState = .finished(cards: 0, boards: 0)
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
                pushState = .failed(error.localizedDescription)
                return
            }
            sent += slice.count
            index = end
            pushState = .pushing(done: sent, total: total)
        }

        pushState = .finished(cards: cards.count, boards: boards.count)
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
