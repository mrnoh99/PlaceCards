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

    static func search(query: String, coordinateHint: Coordinates?) async throws -> [PlaceSearchResult] {
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
                    continuation.resume(
                        throwing: error ?? PlaceCardsError.noResults
                    )
                }
            }
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
