import Foundation

struct PlaceSearchResult: Identifiable {
    let id: String
    let name: String
    let address: String
    let coordinates: Coordinates?
    let rating: Double?
    let reviewCount: Int?
    let phone: String?
    let website: String?
    let category: String?
    /// The resource name of this place's first Google Places photo, if it
    /// has one (e.g. `"places/ChIJ.../photos/AUy1..."`) — pass to
    /// `GooglePlacesService.photoData(photoName:)` to fetch the actual
    /// image bytes. `nil` when Google has no photo for this place.
    let photoName: String?
}

struct PlaceDetails {
    var rating: Double?
    var reviewCount: Int?
    var hoursDetail: [String: String]?
    var amenities: [String]
    var website: String?
    var phone: String?
}

protocol PlaceSearchService {
    func search(query: String, coordinates: Coordinates?) async throws -> [PlaceSearchResult]
    func details(placeId: String) async throws -> PlaceDetails
}

/// Talks to the Google Places API (New) directly from the app, using the
/// user's own API key (BYOK). Google's terms allow direct client calls when
/// the key is restricted to the app's bundle ID.
final class GooglePlacesService: PlaceSearchService {
    private let apiKey: String
    private let session: URLSession

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func search(query: String, coordinates: Coordinates? = nil) async throws -> [PlaceSearchResult] {
        guard !apiKey.isEmpty else { throw PlaceCardsError.apiKeyMissing }

        let url = URL(string: "https://places.googleapis.com/v1/places:searchText")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(
            "places.id,places.displayName,places.formattedAddress,places.location,places.rating,places.userRatingCount,places.internationalPhoneNumber,places.websiteUri,places.primaryTypeDisplayName,places.photos",
            forHTTPHeaderField: "X-Goog-FieldMask"
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = ["textQuery": query]
        if let coordinates {
            body["locationBias"] = [
                "circle": [
                    "center": ["latitude": coordinates.latitude, "longitude": coordinates.longitude],
                    "radius": 5000
                ]
            ]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data)

        let decoded = try JSONDecoder().decode(GooglePlacesSearchResponse.self, from: data)
        return (decoded.places ?? []).map { $0.toSearchResult() }
    }

    func details(placeId: String) async throws -> PlaceDetails {
        guard !apiKey.isEmpty else { throw PlaceCardsError.apiKeyMissing }

        let url = URL(string: "https://places.googleapis.com/v1/places/\(placeId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(
            "rating,userRatingCount,regularOpeningHours,websiteUri,internationalPhoneNumber",
            forHTTPHeaderField: "X-Goog-FieldMask"
        )

        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data)

        let decoded = try JSONDecoder().decode(GooglePlaceDetail.self, from: data)
        return decoded.toPlaceDetails()
    }

    /// Fetches the actual image bytes for a photo named in a search
    /// result's `photoName`, via the Photo Media sub-resource. Used to pull
    /// Google's own photo for a place into the card's `officialPhotos`
    /// when the user hasn't supplied one of their own.
    func photoData(photoName: String, maxWidthPx: Int = 800) async throws -> Data {
        guard !apiKey.isEmpty else { throw PlaceCardsError.apiKeyMissing }

        var components = URLComponents(string: "https://places.googleapis.com/v1/\(photoName)/media")!
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "maxWidthPx", value: String(maxWidthPx)),
            URLQueryItem(name: "skipHttpRedirect", value: "true")
        ]
        guard let url = components.url else { throw PlaceCardsError.networkError("잘못된 사진 URL") }

        struct PhotoMediaResponse: Decodable { let photoUri: String }
        let (data, response) = try await session.data(from: url)
        try Self.validate(response: response, data: data)

        let decoded = try JSONDecoder().decode(PhotoMediaResponse.self, from: data)
        guard let photoURL = URL(string: decoded.photoUri) else {
            throw PlaceCardsError.networkError("잘못된 사진 URL")
        }
        let (photoBytes, photoResponse) = try await session.data(from: photoURL)
        try Self.validate(response: photoResponse, data: photoBytes)
        return photoBytes
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "알 수 없는 오류"
            throw PlaceCardsError.apiError(message, statusCode: http.statusCode)
        }
    }
}

// MARK: - Google Places API (New) response models

private struct GooglePlacesSearchResponse: Decodable {
    let places: [GooglePlace]?
}

private struct GooglePlace: Decodable {
    struct DisplayName: Decodable { let text: String }
    struct Location: Decodable { let latitude: Double; let longitude: Double }
    struct Photo: Decodable { let name: String }

    let id: String
    let displayName: DisplayName?
    let formattedAddress: String?
    let location: Location?
    let rating: Double?
    let userRatingCount: Int?
    let internationalPhoneNumber: String?
    let websiteUri: String?
    let primaryTypeDisplayName: DisplayName?
    let photos: [Photo]?

    func toSearchResult() -> PlaceSearchResult {
        PlaceSearchResult(
            id: id,
            name: displayName?.text ?? "",
            address: formattedAddress ?? "",
            coordinates: location.map { Coordinates(latitude: $0.latitude, longitude: $0.longitude) },
            rating: rating,
            reviewCount: userRatingCount,
            phone: internationalPhoneNumber,
            website: websiteUri,
            category: primaryTypeDisplayName?.text,
            photoName: photos?.first?.name
        )
    }
}

private struct GooglePlaceDetail: Decodable {
    struct OpeningHours: Decodable {
        let weekdayDescriptions: [String]?
    }

    let rating: Double?
    let userRatingCount: Int?
    let regularOpeningHours: OpeningHours?
    let websiteUri: String?
    let internationalPhoneNumber: String?

    func toPlaceDetails() -> PlaceDetails {
        var hours: [String: String]?
        if let descriptions = regularOpeningHours?.weekdayDescriptions {
            var map: [String: String] = [:]
            for line in descriptions {
                let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 2 {
                    map[parts[0]] = parts[1]
                }
            }
            hours = map
        }
        return PlaceDetails(
            rating: rating,
            reviewCount: userRatingCount,
            hoursDetail: hours,
            amenities: [],
            website: websiteUri,
            phone: internationalPhoneNumber
        )
    }
}
