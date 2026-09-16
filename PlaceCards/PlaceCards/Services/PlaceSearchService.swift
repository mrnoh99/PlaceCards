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
    /// Whether `id` is an actual Google Places `placeId` — `true` only
    /// for `GooglePlace.toSearchResult()`, `false` for a Naver-verified
    /// result (`NaverLocalItem.toSearchResult()`'s own `id` is just its
    /// share link or a random UUID). Callers use this to decide whether
    /// it's safe to pass `id` to `GooglePlacesService.details(placeId:)`
    /// — doing that with a Naver-origin `id` would just fail (it isn't a
    /// Google place at all), not silently return wrong data, but it's
    /// still wasted network traffic worth skipping outright.
    let isFromGooglePlaces: Bool
    /// Day-label -> hours-text, as shown in the card's 영업시간 list.
    /// Google returns this in the same Text Search response as everything
    /// else above, because `search`'s field mask asks for
    /// `places.regularOpeningHours` — so a card built from a search result
    /// already has its hours and needs no separate Place Details call.
    /// `nil` for a Naver-verified result (`NaverLocalItem.toSearchResult()`
    /// — Naver's local search API has no equivalent field) or when Google
    /// has no hours on file for the place.
    let hoursDetail: [String: String]?
    /// The structured form of `hoursDetail` — see `OpeningPeriod`. Comes
    /// from the same `regularOpeningHours` object, so it costs nothing
    /// extra to carry, and is what makes "지금 영업 중" answerable.
    let openingPeriods: [OpeningPeriod]?
}

struct PlaceDetails {
    var rating: Double?
    var reviewCount: Int?
    var hoursDetail: [String: String]?
    /// The structured form of `hoursDetail` — see `OpeningPeriod`. Comes
    /// from the same `regularOpeningHours` object already being requested,
    /// so it costs nothing extra to carry.
    var openingPeriods: [OpeningPeriod]?
    var amenities: [String]
    var website: String?
    var phone: String?
    /// Usually redundant with what the original search result already
    /// had, but a card that somehow ended up with a `googlePlaceId` and
    /// no coordinates (a decode/migration edge case, say) can still
    /// recover one from here — `EditPlaceCardSheet`'s "Google에서
    /// 새로고침" fills it in the same "only if blank" way as every other
    /// field on this struct.
    var coordinates: Coordinates?
    /// Same resource-name shape as `PlaceSearchResult.photoName` — pass to
    /// `GooglePlacesService.photoData(photoName:)` to fetch the actual
    /// image bytes. `nil` when Google has no photo for this place.
    var photoName: String?
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
/// user's own API key (BYOK).
///
/// Every request identifies the bundle it came from — see
/// `authorize(_:)`, without which a bundle-ID restriction on the key
/// cannot be enforced at all. Google's own guidance is that a proxy
/// server is the safer shape for web-service calls from a mobile client;
/// this is the restriction that is actually available to a direct
/// caller, not a claim that it is equivalent.
final class GooglePlacesService: PlaceSearchService {
    private let apiKey: String
    private let session: URLSession

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    /// Everything a card is built from. `places.rating`, `places.priceLevel`
    /// and `places.regularOpeningHours` are Enterprise-tier fields, so this
    /// whole request bills at the Enterprise rate — the right trade here,
    /// since it's the one call that has to come back with enough to fill a
    /// card. See `geocodeFieldMask` for the case where it isn't.
    private static let searchFieldMask = "places.id,places.displayName,places.formattedAddress,places.location,places.rating,places.userRatingCount,places.internationalPhoneNumber,places.websiteUri,places.primaryTypeDisplayName,places.photos,places.priceLevel,places.regularOpeningHours"

    /// A geocode reads exactly one thing: the coordinate. `places.location`
    /// is an Essentials-tier field, and the field mask is what picks the
    /// SKU, so asking for only this bills the request at Essentials rather
    /// than the Enterprise rate `searchFieldMask` commands.
    ///
    /// The per-call difference is a few percent; the allowance is not.
    /// Essentials SKUs carry a far larger monthly no-cost allowance than
    /// Enterprise ones, so this stops geocodes from spending the same small
    /// Enterprise allowance the real place lookups need — one verification
    /// used to consume two of those, since `resolveGroundTruth` geocodes
    /// the address and then searches for the place.
    private static let geocodeFieldMask = "places.location"

    /// Stamps the key and the bundle identifier onto a request.
    ///
    /// The bundle header is the half that was missing. An "iOS apps" key
    /// restriction in the Cloud console is defined for the Maps SDK; a
    /// REST call to `places.googleapis.com` is only checked against it
    /// when the request says which bundle it came from, via
    /// `X-Ios-Bundle-Identifier`. Without it, turning that restriction on
    /// either rejects every call or protects nothing — so the key was
    /// effectively unrestricted no matter what the console said.
    ///
    /// Harmless the other way round: a key with no application
    /// restriction ignores the header entirely — which is in fact the
    /// setup this app documents. The "지도" tab's Google map is the Maps
    /// JavaScript API loaded into a `WKWebView` (see `GoogleMapWebView`)
    /// on this same key, and a web page is checked by referer, not by
    /// this header. A key carries only one application restriction, so
    /// turning on "iOS apps" would protect these calls and black out
    /// that map. README and Settings therefore ask for an unrestricted
    /// key held down by per-API daily quotas instead. The header stays
    /// because it costs nothing and is what makes the restriction work
    /// for anyone who does turn it on — with a second key for the map,
    /// or with no use for the Google map at all.
    private func authorize(_ request: inout URLRequest) {
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            request.setValue(bundleIdentifier, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }
    }

    private func searchTextRequest(query: String, coordinates: Coordinates?, fieldMask: String) throws -> URLRequest {
        let url = URL(string: "https://places.googleapis.com/v1/places:searchText")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        authorize(&request)
        request.setValue(fieldMask, forHTTPHeaderField: "X-Goog-FieldMask")
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
        return request
    }

    func search(query: String, coordinates: Coordinates? = nil) async throws -> [PlaceSearchResult] {
        guard !apiKey.isEmpty else { throw PlaceCardsError.apiKeyMissing }

        let request = try searchTextRequest(
            query: query, coordinates: coordinates, fieldMask: Self.searchFieldMask
        )
        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data)

        let decoded = try JSONDecoder().decode(GooglePlacesSearchResponse.self, from: data)
        return (decoded.places ?? []).map { $0.toSearchResult() }
    }

    /// Best-effort coordinates for a plain address string, used to verify
    /// a name-searched place is actually near the address it's supposed
    /// to be at (see `PlaceCardViewModel.search(rowID:)`). Uses Text
    /// Search (`searchText`) with the address itself as the query, taking
    /// its top result's location, rather than calling the separate
    /// Geocoding API — that would need its own API enablement in the
    /// user's Google Cloud project on top of Places, for a lookup Text
    /// Search already resolves well enough for this purpose.
    ///
    /// Sends `geocodeFieldMask` rather than going through `search` — the
    /// full mask would have this billing at the Enterprise rate to read a
    /// latitude and a longitude, decoding a rating, a price level and a
    /// week of opening hours only to throw them away.
    func geocodeAddress(_ address: String) async throws -> Coordinates? {
        guard !apiKey.isEmpty else { throw PlaceCardsError.apiKeyMissing }

        let request = try searchTextRequest(
            query: address, coordinates: nil, fieldMask: Self.geocodeFieldMask
        )
        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data)

        let decoded = try JSONDecoder().decode(GeocodeResponse.self, from: data)
        guard let location = decoded.places?.first?.location else { return nil }
        return Coordinates(latitude: location.latitude, longitude: location.longitude)
    }

    func details(placeId: String) async throws -> PlaceDetails {
        guard !apiKey.isEmpty else { throw PlaceCardsError.apiKeyMissing }

        var components = URLComponents(string: "https://places.googleapis.com/v1/places/\(placeId)")!
        components.queryItems = [
            URLQueryItem(name: "languageCode", value: AppLanguage.current().googlePlacesLanguageCode)
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        authorize(&request)
        request.setValue(
            "rating,userRatingCount,regularOpeningHours,websiteUri,internationalPhoneNumber,location,photos",
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
        // The key moves out of the query string and into the header with
        // everything else, so this call carries the bundle identifier too
        // — a `key=` parameter has nowhere to put one.
        components.queryItems = [
            URLQueryItem(name: "maxWidthPx", value: String(maxWidthPx)),
            URLQueryItem(name: "skipHttpRedirect", value: "true")
        ]
        guard let url = components.url else { throw PlaceCardsError.networkError("잘못된 사진 URL".localized) }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        authorize(&request)

        struct PhotoMediaResponse: Decodable { let photoUri: String }
        let (data, response) = try await session.data(for: request)
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

/// The response to a `geocodeFieldMask` request. A separate model rather
/// than reusing `GooglePlace`, whose `id` is non-optional — that mask asks
/// for no id at all, so decoding it as a `GooglePlace` would throw.
private struct GeocodeResponse: Decodable {
    struct Place: Decodable {
        struct Location: Decodable {
            let latitude: Double
            let longitude: Double
        }
        let location: Location?
    }

    let places: [Place]?
}

/// Google's `regularOpeningHours` object, shared by the Text Search and the
/// Place Details response models below — both return the exact same shape,
/// and asking Text Search for it (see `search`'s field mask) is what lets a
/// card be built from a single request instead of a search *and* a details
/// call. `regularOpeningHours` is an Enterprise-SKU field either way, and
/// the search request is already Enterprise for `rating`/`priceLevel`, so
/// adding it there costs nothing while the details call it replaces was a
/// billable request of its own.
private struct GoogleOpeningHours: Decodable {
    /// Google omits `minute` when it's zero, and omits `close`
    /// entirely for a place that never closes.
    struct Point: Decodable {
        let day: Int
        let hour: Int
        let minute: Int?
    }
    struct Period: Decodable {
        let open: Point?
        let close: Point?
    }

    let weekdayDescriptions: [String]?
    let periods: [Period]?

    /// Each `weekdayDescriptions` line is `"<day>: <hours>"` — split on the
    /// first colon only, since the hours half contains colons of its own
    /// ("월요일: 09:00~18:00").
    var hoursDetail: [String: String]? {
        guard let weekdayDescriptions else { return nil }
        var map: [String: String] = [:]
        for line in weekdayDescriptions {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 {
                map[parts[0]] = parts[1]
            }
        }
        return map
    }

    var openingPeriods: [OpeningPeriod]? {
        let mapped: [OpeningPeriod]? = periods?.compactMap { period in
            guard let open = period.open else { return nil }
            return OpeningPeriod(
                openDay: open.day,
                openMinute: open.hour * 60 + (open.minute ?? 0),
                closeDay: period.close?.day,
                closeMinute: period.close.map { $0.hour * 60 + ($0.minute ?? 0) }
            )
        }
        return (mapped?.isEmpty ?? true) ? nil : mapped
    }
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
    let regularOpeningHours: GoogleOpeningHours?

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
            photoName: photos?.first?.name,
            isFromGooglePlaces: true,
            hoursDetail: regularOpeningHours?.hoursDetail,
            openingPeriods: regularOpeningHours?.openingPeriods
        )
    }
}

private struct GooglePlaceDetail: Decodable {
    struct Location: Decodable { let latitude: Double; let longitude: Double }
    struct Photo: Decodable { let name: String }

    let rating: Double?
    let userRatingCount: Int?
    let regularOpeningHours: GoogleOpeningHours?
    let websiteUri: String?
    let internationalPhoneNumber: String?
    let location: Location?
    let photos: [Photo]?

    func toPlaceDetails() -> PlaceDetails {
        PlaceDetails(
            rating: rating,
            reviewCount: userRatingCount,
            hoursDetail: regularOpeningHours?.hoursDetail,
            openingPeriods: regularOpeningHours?.openingPeriods,
            amenities: [],
            website: websiteUri,
            phone: internationalPhoneNumber,
            coordinates: location.map { Coordinates(latitude: $0.latitude, longitude: $0.longitude) },
            photoName: photos?.first?.name
        )
    }
}
