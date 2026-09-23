import Foundation
import MapKit

/// "Google/Naver/Apple에서 장소 확정"에 세 번째 자리를 더한다 — 애플 자체
/// `MKLocalSearch`.구글·네이버와 달리 API 키가 필요 없다(애플 기기에
/// 내장된 프레임워크).
///
/// `MKLocalSearch`가 주는 것은 이름·주소·좌표·전화번호·웹사이트까지다.
/// 평점·리뷰 수·영업시간·사진은 없다 — `PlaceSearchResult`의 그 필드들은
/// 이미 Naver 쪽에서도 전부 `nil`/빈 배열로 두는 선례가 있어(자기 자리에
/// 없는 정보를 억지로 채우지 않는다) 그대로 따른다.
enum AppleLocalSearchService {
    /// 좌표가 있으면 그 언저리로 검색을 좁힌다 — 이름만으로 전국을 뒤지면
    /// 엉뚱한 동네의 같은 이름 가게가 앞자리를 차지할 수 있다. 좌표가
    /// 없으면(아직 아무 단서가 없는 카드) 힌트 없이 그냥 이름으로 찾는다.
    private static let regionRadiusMeters: CLLocationDistance = 5_000

    /// `query`로 먼저 찾고, 빈 손이면 `fallbackQuery`로 한 번 더 찾는다.
    ///
    /// 둘로 나뉘는 이유: 호출부는 "이름 + 주소"를 한 줄로 이어 넘기는데
    /// (`EditPlaceCardSheet.confirmPlace`), `MKLocalSearch`는 그걸 구글처럼
    /// 너그럽게 받아 주지 않는다. `naturalLanguageQuery`는 글자 그대로
    /// 맞춰 보는 쪽에 가까워서 "애드라인 터프팅 스튜디오 경기 수원시
    /// 팔달구 세지로234번길 5 1층"처럼 층수까지 붙은 줄은 통째로 어긋난다 —
    /// 실제로 사용자가 이 조합에서 결과 0을 신고했다. 이름만으로 다시
    /// 물으면 대개 찾힌다. `coordinateHint`가 그때 엉뚱한 동네를 걸러 준다.
    static func search(
        query: String, fallbackQuery: String? = nil, coordinateHint: Coordinates?
    ) async throws -> [PlaceSearchResult] {
        let first = try await run(query: query, coordinateHint: coordinateHint)
        guard first.isEmpty, let fallbackQuery, fallbackQuery != query else { return first }
        return try await run(query: fallbackQuery, coordinateHint: coordinateHint)
    }

    /// 못 찾은 것은 **빈 결과로 돌려준다.** `MKLocalSearch`는 결과가 없을
    /// 때도 오류를 던지는데(`MKError.placemarkNotFound`), 그걸 그대로
    /// 올려 보내면 두 가지가 한꺼번에 어긋난다: 위의 두 번째 시도까지
    /// 가지 못하고, 화면에는 애플이 만든 영어 문장이 그대로 뜬다 —
    /// 사용자가 본 것이 정확히 그것이다("The operation couldn't be
    /// completed. (MKErrorDomain error 4.)"). 서버 실패 같은 진짜 오류는
    /// 그대로 던진다.
    private static func run(query: String, coordinateHint: Coordinates?) async throws -> [PlaceSearchResult] {
        do {
            return try await performSearch(query: query, coordinateHint: coordinateHint)
        } catch let error as MKError where error.code == .placemarkNotFound {
            return []
        }
    }

    private static func performSearch(query: String, coordinateHint: Coordinates?) async throws -> [PlaceSearchResult] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let coordinateHint {
            request.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: coordinateHint.latitude, longitude: coordinateHint.longitude
                ),
                latitudinalMeters: regionRadiusMeters,
                longitudinalMeters: regionRadiusMeters
            )
        }
        let response = try await start(MKLocalSearch(request: request))
        return response.mapItems.map(\.asSearchResult)
    }

    /// 완료 핸들러를 받는 쪽만 쓰고 컨티뉴에이션으로 감싼다 — 이 앱의 다른
    /// 서비스(`LocationService`, `MediaStore.PhotoLibraryAlbum`,
    /// `CloudSyncService`)와 같은 이유다: 여기서는 컴파일 검증이 CI뿐이라
    /// (CLAUDE.md §1) 어느 SDK에서나 확실히 있는 쪽을 고른다.
    private static func start(_ search: MKLocalSearch) async throws -> MKLocalSearch.Response {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<MKLocalSearch.Response, Error>) in
            search.start { response, error in
                if let response {
                    continuation.resume(returning: response)
                } else {
                    continuation.resume(throwing: error ?? PlaceCardsError.noResults)
                }
            }
        }
    }

    /// 여기까지 올라온 오류를 사람이 읽을 수 있는 한 줄로 바꾼다. 애플이
    /// 만든 `localizedDescription`은 한국어 화면에 영어로 뜨는 데다
    /// ("The operation couldn't be completed. (MKErrorDomain error 4.)")
    /// 무엇을 하라는 말인지도 없다. 모르는 오류면 `nil`을 돌려 호출부가
    /// 제 일반 문구를 쓰게 한다.
    ///
    /// `placemarkNotFound`는 여기 오지 않는다 — `run`이 빈 결과로 삼킨다.
    static func message(for error: Error) -> String? {
        guard let code = (error as? MKError)?.code else { return nil }
        switch code {
        case .serverFailure:
            return "애플 지도 서버에 연결하지 못했습니다.".localized
        case .loadingThrottled:
            return "애플 지도 요청이 너무 잦습니다. 잠시 뒤 다시 시도해주세요.".localized
        default:
            return nil
        }
    }
}

private extension MKMapItem {
    var asSearchResult: PlaceSearchResult {
        PlaceSearchResult(
            // `MKMapItem`은 안정적인 장소 id를 안 준다 — Naver가
            // `resolvedLink ?? UUID()`로 하는 것과 같은 이유로 새로
            // 만든다. `provider != .google`이라 어차피
            // `GooglePlacesService.details(placeId:)`에 쓰일 일이 없다.
            id: UUID().uuidString,
            name: (name ?? "").strippingInvisibleFormatCharacters(),
            // `MKPlacemark.title`이 애플 자신이 조립하는 사람이 읽을 수
            // 있는 전체 주소다("공식 문서로 확인된 것만" 규칙에 맞게
            // 애플이 제공하는 계산 프로퍼티를 그대로 쓴다).
            address: (placemark.title ?? "").strippingInvisibleFormatCharacters(),
            coordinates: Coordinates(
                latitude: placemark.coordinate.latitude, longitude: placemark.coordinate.longitude
            ),
            rating: nil,
            reviewCount: nil,
            phone: phoneNumber,
            website: url?.absoluteString,
            category: nil,
            priceLevel: nil,
            photoNames: [],
            provider: .apple,
            hoursDetail: nil,
            openingPeriods: nil
        )
    }
}
