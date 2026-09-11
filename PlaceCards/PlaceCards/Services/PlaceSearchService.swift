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
    /// `nil` for a Naver-verified result (`NaverLocalItem.toSearchResult()`
    /// — Naver's local search API has no equivalent field) or any Google
    /// result Google itself didn't return a price level for.
    let priceLevel: PriceLevel?
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

private extension AppLanguage {
    /// Google Places API (New) `languageCode` for this app language.
    /// Passed explicitly on every request below so a place's returned
    /// `displayName`/`formattedAddress` follow this app's own "앱 언어"
    /// setting — without it, Google falls back to whatever `Accept-Language`
    /// the device's system language produces, which has nothing to do with
    /// this app's own language setting.
    var googlePlacesLanguageCode: String {
        switch self {
        case .korean: return "ko"
        case .english: return "en"
        }
    }
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
            "places.id,places.displayName,places.formattedAddress,places.location,places.rating,places.userRatingCount,places.internationalPhoneNumber,places.websiteUri,places.primaryTypeDisplayName,places.photos,places.priceLevel",
            forHTTPHeaderField: "X-Goog-FieldMask"
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "textQuery": query,
            "languageCode": AppLanguage.current().googlePlacesLanguageCode
        ]
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

    /// Best-effort coordinates for a plain address string, used to verify
    /// a name-searched place is actually near the address it's supposed
    /// to be at (see `PlaceCardViewModel.search(rowID:)`). Reuses Text
    /// Search (`searchText`) with the address itself as the query, taking
    /// its top result's location, rather than calling the separate
    /// Geocoding API — that would need its own API enablement in the
    /// user's Google Cloud project on top of Places, for a lookup Text
    /// Search already resolves well enough for this purpose.
    func geocodeAddress(_ address: String) async throws -> Coordinates? {
        let results = try await search(query: address, coordinates: nil)
        return results.first?.coordinates
    }

    func details(placeId: String) async throws -> PlaceDetails {
        guard !apiKey.isEmpty else { throw PlaceCardsError.apiKeyMissing }

        var components = URLComponents(string: "https://places.googleapis.com/v1/places/\(placeId)")!
        components.queryItems = [
            URLQueryItem(name: "languageCode", value: AppLanguage.current().googlePlacesLanguageCode)
        ]
        var request = URLRequest(url: components.url!)
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
        guard let url = components.url else { throw PlaceCardsError.networkError("잘못된 사진 URL".localized) }

        struct PhotoMediaResponse: Decodable { let photoUri: String }
        let (data, response) = try await session.data(from: url)
        try Self.validate(response: response, data: data)

        let decoded = try JSONDecoder().decode(PhotoMediaResponse.self, from: data)
        guard let photoURL = URL(string: decoded.photoUri) else {
            throw PlaceCardsError.networkError("잘못된 사진 URL".localized)
        }
        let (photoBytes, photoResponse) = try await session.data(from: photoURL)
        try Self.validate(response: photoResponse, data: photoBytes)
        return photoBytes
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "알 수 없는 오류".localized
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
    /// Raw JSON string, e.g. `"PRICE_LEVEL_MODERATE"` — decoded via
    /// `PriceLevel(rawValue:)` below rather than typed as `PriceLevel?`
    /// directly, so an unrecognized/unspecified value (Google's own
    /// `PRICE_LEVEL_UNSPECIFIED`, or any future case this app doesn't
    /// know about yet) fails that lookup and becomes `nil` instead of
    /// failing the whole decode.
    let priceLevel: String?

    // Google Places' response text for a mixed-script (Korean + Latin/
    // numeric) name/address routinely embeds bidi direction-control
    // marks for correct display in a browser — invisible there, but
    // capable of visibly mis-rendering a plain SwiftUI `Text` (see
    // `String.strippingInvisibleFormatCharacters()`'s own comment).
    func toSearchResult() -> PlaceSearchResult {
        PlaceSearchResult(
            id: id,
            name: (displayName?.text ?? "").strippingInvisibleFormatCharacters(),
            address: (formattedAddress ?? "").strippingInvisibleFormatCharacters(),
            coordinates: location.map { Coordinates(latitude: $0.latitude, longitude: $0.longitude) },
            rating: rating,
            reviewCount: userRatingCount,
            phone: internationalPhoneNumber,
            website: websiteUri,
            category: primaryTypeDisplayName?.text.strippingInvisibleFormatCharacters(),
            priceLevel: priceLevel.flatMap(PriceLevel.init(rawValue:)),
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
