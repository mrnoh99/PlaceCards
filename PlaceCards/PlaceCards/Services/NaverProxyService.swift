import Foundation

struct NaverSearchResult: Identifiable {
    let id: String
    let name: String
    let address: String
    let coordinates: Coordinates?
    let phone: String?
    let category: String?
}

/// Naver's Client Secret must never ship inside the app, so this talks to a
/// small backend proxy (see the project's backend plan) that holds the
/// secret and forwards the request to the real Naver Local Search API.
/// The proxy's base URL is configured by the user in Settings.
final class NaverProxyService {
    private let proxyBaseURL: URL
    private let session: URLSession

    init(proxyBaseURL: URL, session: URLSession = .shared) {
        self.proxyBaseURL = proxyBaseURL
        self.session = session
    }

    func search(query: String, display: Int = 10) async throws -> [NaverSearchResult] {
        let url = proxyBaseURL.appendingPathComponent("api/naver/search")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "display": display])

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "알 수 없는 오류"
            throw PlaceCardsError.apiError(message, statusCode: http.statusCode)
        }

        let decoded = try JSONDecoder().decode(NaverProxyResponse.self, from: data)
        return decoded.items.map { $0.toResult() }
    }
}

private struct NaverProxyResponse: Decodable {
    let items: [NaverProxyItem]
}

private struct NaverProxyItem: Decodable {
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

        // NOTE: Naver's Local Search API has returned coordinates in a couple
        // of different scales/systems across API versions. Verify this
        // conversion against the deployed proxy before relying on it.
        var coordinates: Coordinates?
        if let mapx, let mapy, let x = Double(mapx), let y = Double(mapy) {
            coordinates = Coordinates(latitude: y / 1_000_000, longitude: x / 1_000_000)
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
