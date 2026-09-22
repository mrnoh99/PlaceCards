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
