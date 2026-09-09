import Foundation

/// Geocoding via NAVER Cloud Platform's Maps Geocoding REST API
/// (naveropenapi.apigw.ntruss.com), for people who've entered their own NCP
/// Client ID/Secret in Settings — the most accurate geocoder for Korean
/// addresses, since Apple's CLGeocoder and Google's Geocoding API both have
/// comparatively weak Korean road-name/lot-number coverage.
///
/// This is a *different* Naver credential pair from `NaverLocalSearchService`
/// (openapi.naver.com's Local Search, a separate developer console) — ported
/// from Peragra, which uses this exact API the same way. A native
/// `URLSession` request isn't subject to CORS, so this calls the REST
/// endpoint directly from the device with the user's own key; no backend
/// proxy needed.
///
/// Used as a best-effort way to fill in coordinates for a place that only
/// has an address and no reliable lat/lng yet (a manually-entered place, or
/// a Naver Local Search result whose mapx/mapy conversion is in doubt —
/// see the note in `NaverLocalSearchService`). Callers should treat a `nil`
/// result as "couldn't geocode this," not an error worth interrupting the
/// user over.
///
/// NOTE: implemented against NAVER Cloud Platform's documented REST
/// endpoints without a live NCP key to test against in this environment —
/// if geocoding fails outright (not just "no result"), check the surfaced
/// error message first; NCP has moved this product's API gateway domain
/// before, so a 404 most likely means the endpoint moved again.
enum NaverGeocodingService {
    struct Result {
        let latitude: Double
        let longitude: Double
    }

    private static let geocodeURL = URL(string: "https://naveropenapi.apigw.ntruss.com/map-geocode/v2/geocode")!

    static func geocode(query: String, clientId: String, clientSecret: String) async -> Result? {
        guard !clientId.isEmpty, !clientSecret.isEmpty else { return nil }

        var components = URLComponents(url: geocodeURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "query", value: query)]
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue(clientId, forHTTPHeaderField: "x-ncp-apigw-api-key-id")
        request.setValue(clientSecret, forHTTPHeaderField: "x-ncp-apigw-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                print("Naver geocoding failed: unexpected HTTP status")
                return nil
            }
            let decoded = try JSONDecoder().decode(GeocodeResponse.self, from: data)
            guard let first = decoded.addresses?.first,
                  let latitude = Double(first.y), let longitude = Double(first.x) else {
                return nil
            }
            return Result(latitude: latitude, longitude: longitude)
        } catch {
            print("Naver geocoding request failed: \(error)")
            return nil
        }
    }

    private struct GeocodeResponse: Decodable {
        let addresses: [GeocodeAddress]?
    }

    private struct GeocodeAddress: Decodable {
        let x: String
        let y: String
    }
}
