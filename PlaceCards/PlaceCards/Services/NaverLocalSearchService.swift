import Foundation

struct NaverSearchResult: Identifiable {
    let id: String
    let name: String
    let address: String
    let coordinates: Coordinates?
    let phone: String?
    let category: String?
}

/// Naver Developers' Local Search API (openapi.naver.com), called directly
/// from the device with the user's own Client ID/Secret (BYOK) — the same
/// approach Peragra uses for Naver's Maps Geocoding API (see
/// `NaverGeocodingService`): a native `URLSession` request isn't subject to
/// CORS the way a web app's request is, so there's no need for a backend
/// proxy to hide the secret behind. The secret is the user's own key,
/// entered by them, kept in this device's Keychain only.
final class NaverLocalSearchService {
    private let clientId: String
    private let clientSecret: String
    private let session: URLSession

    init(clientId: String, clientSecret: String, session: URLSession = .shared) {
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.session = session
    }

    func search(query: String, display: Int = 10) async throws -> [NaverSearchResult] {
        guard !clientId.isEmpty, !clientSecret.isEmpty else { throw PlaceCardsError.apiKeyMissing }

        var components = URLComponents(string: "https://openapi.naver.com/v1/search/local.json")
        components?.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "display", value: String(display)),
        ]
        guard let url = components?.url else {
            throw PlaceCardsError.networkError("Naver 검색 URL을 만들 수 없습니다.")
        }

        var request = URLRequest(url: url)
        request.setValue(clientId, forHTTPHeaderField: "X-Naver-Client-Id")
        request.setValue(clientSecret, forHTTPHeaderField: "X-Naver-Client-Secret")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PlaceCardsError.networkError("Naver 검색에 실패했습니다.")
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw PlaceCardsError.apiKeyInvalid }
            if http.statusCode == 429 { throw PlaceCardsError.rateLimited("Naver 검색") }
            let message = String(data: data, encoding: .utf8) ?? "알 수 없는 오류"
            throw PlaceCardsError.apiError(message, statusCode: http.statusCode)
        }

        let decoded = try JSONDecoder().decode(NaverLocalSearchResponse.self, from: data)
        return decoded.items.map { $0.toResult() }
    }
}

private struct NaverLocalSearchResponse: Decodable {
    let items: [NaverLocalSearchItem]
}

private struct NaverLocalSearchItem: Decodable {
    let title: String
    let address: String?
    let roadAddress: String?
    let mapx: String?
    let mapy: String?
    let telephone: String?
    let category: String?

    func toResult() -> NaverSearchResult {
        let plainTitle = title
            .replacingOccurrences(of: "<b>", with: "")
            .replacingOccurrences(of: "</b>", with: "")

        // NOTE: mapx/mapy's scale/coordinate system has changed across
        // versions of this API in the past (plain WGS84*10^7 vs. KATEC),
        // so treat this as a best-effort fallback — `NaverGeocodingService`
        // (Naver's dedicated, documented Geocoding API) is the more
        // reliable source for coordinates when precision matters.
        var coordinates: Coordinates?
        if let mapx, let mapy, let x = Double(mapx), let y = Double(mapy) {
            coordinates = Coordinates(latitude: y / 10_000_000, longitude: x / 10_000_000)
        }

        return NaverSearchResult(
            id: "\(mapx ?? "")_\(mapy ?? "")",
            name: plainTitle,
            address: roadAddress ?? address ?? "",
            coordinates: coordinates,
            phone: telephone,
            category: category
        )
    }
}
