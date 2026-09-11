import Foundation

/// Verifies a place against Naver's own local-business database (검색
/// 오픈API - 지역, `openapi.naver.com/v1/search/local.json`) instead of
/// Google's — a place found via a Naver Map share should be checked
/// against the same source it came from, and Korean local businesses are
/// often more completely/accurately listed on Naver than on Google.
///
/// This is a *different* credential pair from `naverMapClientId` (that
/// one only renders map tiles in `NaverMapWebView`): a Client ID **and**
/// Secret, issued from the Search API section of the Naver Developers
/// console (developers.naver.com/apps) rather than NAVER Cloud Platform.
enum NaverPlaceSearchService {
    /// Naver's own docs describe `mapx`/`mapy` as KATECH (TM128)
    /// coordinates needing a separate geocoding call to convert to
    /// WGS84 — but in current real-world practice the endpoint actually
    /// returns them as plain WGS84 degrees scaled by 10,000,000 (a
    /// well-known mismatch between Naver's documentation and its shipped
    /// behavior). That factor is trusted here, but only after checking
    /// the result actually falls within Korea's own lat/lng bounds — if
    /// that assumption is ever wrong for a given result, the coordinates
    /// are dropped instead of saved as silently-wrong data.
    private static let koreaLatitudeRange = 33.0...39.5
    private static let koreaLongitudeRange = 124.0...132.0

    static func search(
        query: String,
        clientId: String,
        clientSecret: String,
        session: URLSession = .shared
    ) async throws -> [PlaceSearchResult] {
        guard !clientId.isEmpty, !clientSecret.isEmpty else { throw PlaceCardsError.apiKeyMissing }

        var components = URLComponents(string: "https://openapi.naver.com/v1/search/local.json")!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "display", value: "5")
        ]
        guard let url = components.url else {
            throw PlaceCardsError.networkError("잘못된 검색어입니다.".localized)
        }

        var request = URLRequest(url: url)
        request.setValue(clientId, forHTTPHeaderField: "X-Naver-Client-Id")
        request.setValue(clientSecret, forHTTPHeaderField: "X-Naver-Client-Secret")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            if http.statusCode == 401 || http.statusCode == 403 { throw PlaceCardsError.apiKeyInvalid }
            if http.statusCode == 429 { throw PlaceCardsError.rateLimited("Naver") }
            let message = String(data: data, encoding: .utf8) ?? "알 수 없는 오류".localized
            throw PlaceCardsError.apiError(message, statusCode: http.statusCode)
        }

        let decoded = try JSONDecoder().decode(NaverLocalSearchResponse.self, from: data)
        return decoded.items.map { $0.toSearchResult() }
    }

    fileprivate static func coordinates(mapx: String, mapy: String) -> Coordinates? {
        guard let x = Double(mapx), let y = Double(mapy) else { return nil }
        let longitude = x / 10_000_000
        let latitude = y / 10_000_000
        guard koreaLatitudeRange.contains(latitude), koreaLongitudeRange.contains(longitude) else { return nil }
        return Coordinates(latitude: latitude, longitude: longitude)
    }

    /// Naver wraps matched query terms in the result `title`/`address` in
    /// `<b>` tags and HTML-escapes the rest, unlike Google's Places API —
    /// stripped here so the saved name/address are plain text.
    fileprivate static func stripHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}

private struct NaverLocalSearchResponse: Decodable {
    let items: [NaverLocalItem]
}

private struct NaverLocalItem: Decodable {
    let title: String
    let link: String?
    let category: String?
    let telephone: String?
    let address: String?
    let roadAddress: String?
    let mapx: String?
    let mapy: String?

    /// No rating/review count/photo — this API simply doesn't return
    /// them, unlike Google Places. Left `nil` rather than guessed.
    func toSearchResult() -> PlaceSearchResult {
        let name = NaverPlaceSearchService.stripHTML(title)
        let rawAddress = [roadAddress, address].compactMap { $0 }.first { !$0.isEmpty }
        let resolvedAddress = rawAddress.map(NaverPlaceSearchService.stripHTML) ?? ""
        let coordinates: Coordinates? = {
            guard let mapx, let mapy else { return nil }
            return NaverPlaceSearchService.coordinates(mapx: mapx, mapy: mapy)
        }()
        let resolvedPhone = (telephone?.isEmpty == false) ? telephone : nil
        let resolvedLink = (link?.isEmpty == false) ? link : nil

        return PlaceSearchResult(
            id: resolvedLink ?? UUID().uuidString,
            name: name,
            address: resolvedAddress,
            coordinates: coordinates,
            rating: nil,
            reviewCount: nil,
            phone: resolvedPhone,
            website: resolvedLink,
            category: category,
            photoName: nil
        )
    }
}
