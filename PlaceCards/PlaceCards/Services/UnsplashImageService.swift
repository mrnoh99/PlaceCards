import Foundation

/// Best-effort fallback photo search via Unsplash — used only when a place
/// has no photo at all (no user upload, no Google Places photo), so the
/// card list/gallery thumbnail isn't left blank. Ported the idea from a
/// reference starter project's `ImageSearchService.searchImageUnsplash`,
/// simplified to "search by name, download the first hit" — no caching,
/// since `MediaStore` already persists the result to disk once found.
struct UnsplashImageService {
    private let accessKey: String
    private let session: URLSession

    init(accessKey: String, session: URLSession = .shared) {
        self.accessKey = accessKey
        self.session = session
    }

    /// Searches Unsplash for `query` and downloads the first result's image
    /// bytes, or `nil` when Unsplash has nothing for it, the key is
    /// invalid, or the request fails — this is a fallback, so any failure
    /// here should be silent rather than surfaced to the user.
    func searchPhotoData(query: String) async -> Data? {
        guard !accessKey.isEmpty else { return nil }

        var components = URLComponents(string: "https://api.unsplash.com/search/photos")!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "per_page", value: "1")
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Client-ID \(accessKey)", forHTTPHeaderField: "Authorization")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(SearchResponse.self, from: data),
              let imageURLString = decoded.results.first?.urls.regular,
              let imageURL = URL(string: imageURLString) else {
            return nil
        }

        guard let (imageData, imageResponse) = try? await session.data(from: imageURL),
              let imageHTTP = imageResponse as? HTTPURLResponse, (200..<300).contains(imageHTTP.statusCode) else {
            return nil
        }
        return imageData
    }

    private struct SearchResponse: Decodable {
        struct Result: Decodable {
            struct URLs: Decodable { let regular: String }
            let urls: URLs
        }
        let results: [Result]
    }
}
