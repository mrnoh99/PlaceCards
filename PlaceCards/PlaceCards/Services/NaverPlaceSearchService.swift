import Foundation

/// Verifies a place against Naver's own local-business database (검색
/// 오픈API - 지역) instead of Google's — a place found via a Naver Map
/// share should be checked against the same source it came from, and
/// Korean local businesses are often more completely/accurately listed on
/// Naver than on Google.
///
/// This is a *different* credential pair from `naverMapClientId` (that
/// one only renders map tiles in `NaverMapWebView`): a Client ID **and**
/// Secret from a separate Application, issued via NAVER Cloud Platform's
/// "NAVER API HUB" (console.ncloud.com → Menu → All Services →
/// Application Services → NAVER API HUB → register an Application
/// selecting "검색" → that Application's own "인증 정보" popup has the
/// Client ID/Secret).
///
/// The endpoint/headers below are API HUB's own — NOT the legacy
/// `openapi.naver.com` + `X-Naver-Client-Id`/`X-Naver-Client-Secret` pair
/// this file originally used: API HUB fully replaced that old open API
/// platform (new registrations on the old host closed 2026-07-31, and its
/// existing keys stop working 2027-06-30), moving to its own gateway
/// domain (`naverapihub.apigw.ntruss.com`) under a completely different
/// header scheme (`X-NCP-APIGW-API-KEY-ID`/`X-NCP-APIGW-API-KEY`) — an app
/// still calling the old host/headers gets rejected with no usage ever
/// recorded against the new Application at all, which is exactly what
/// calling it with API HUB-issued credentials looked like before this fix.
enum NaverPlaceSearchService {
    /// API HUB's own docs describe `mapx`/`mapy` as already being WGS84 —
    /// still scaled by 10,000,000 same as the legacy endpoint, going by
    /// the response shape unchanged. Sanity-clamped to Korea's own lat/lng
    /// bounds regardless — if that assumption is ever wrong for a given
    /// result, the coordinates are dropped instead of saved as
    /// silently-wrong data.
    private static let koreaLatitudeRange = 33.0...39.5
    private static let koreaLongitudeRange = 124.0...132.0

    static func search(
        query: String,
        clientId: String,
        clientSecret: String,
        session: URLSession = .shared
    ) async throws -> [PlaceSearchResult] {
        guard !clientId.isEmpty, !clientSecret.isEmpty else { throw PlaceCardsError.apiKeyMissing }

        var components = URLComponents(string: "https://naverapihub.apigw.ntruss.com/search/v1/local")!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "display", value: "5"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components.url else {
            throw PlaceCardsError.networkError("잘못된 검색어입니다.".localized)
        }

        var request = URLRequest(url: url)
        request.setValue(clientId, forHTTPHeaderField: "X-NCP-APIGW-API-KEY-ID")
        request.setValue(clientSecret, forHTTPHeaderField: "X-NCP-APIGW-API-KEY")

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
    /// `telephone` is also effectively always empty under API HUB (its own
    /// docs say the field is "kept for compatibility" but returns no
    /// value) — `resolvedPhone` below still checks it rather than dropping
    /// the field outright, in case that ever changes.
    func toSearchResult() -> PlaceSearchResult {
        let name = NaverPlaceSearchService.stripHTML(title).strippingInvisibleFormatCharacters()
        let rawAddress = [roadAddress, address].compactMap { $0 }.first { !$0.isEmpty }
        let resolvedAddress = (rawAddress.map(NaverPlaceSearchService.stripHTML) ?? "").strippingInvisibleFormatCharacters()
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
            category: category?.strippingInvisibleFormatCharacters(),
            photoName: nil
        )
    }
}
