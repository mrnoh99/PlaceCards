import Foundation
import SwiftUI
import MapKit

/// A rough bounding box for South Korea (including Jeju and the east-sea
/// islands). Naver Map, Kakao Map, and Tmap have essentially no useful data
/// outside Korea, unlike Google Maps, so their "open in..." links only make
/// sense for a place actually located here. Ported from Peragra's
/// `KoreaRegion`.
enum KoreaRegion {
    static func contains(latitude: Double, longitude: Double) -> Bool {
        (33.0...38.9).contains(latitude) && (124.5...132.0).contains(longitude)
    }
}

/// Builds a Google Maps link that opens the native app on devices where
/// it's installed, or maps.google.com otherwise. Searches by "name,
/// address" when both are known, falling back to the name alone, or the
/// raw coordinate when there's no usable name at all. Ported from
/// Peragra's `GoogleMapsOpener` (simplified: PlaceCards has no geocoding
/// status to distinguish a confidently-located address from a guessed one).
enum GoogleMapsOpener {
    static func url(for card: PlaceCard) -> URL? {
        url(query: query(for: card))
    }

    /// The saved-card-independent counterpart to `url(for:)` — for a
    /// place that isn't (or isn't yet) a `PlaceCard` at all, like an
    /// `AddPlaceCardView` candidate row a user wants to eyeball in the
    /// real Google Maps app before verifying it against Google Places.
    static func url(name: String, address: String) -> URL? {
        url(query: query(name: name, address: address))
    }

    /// Centers the map on an exact coordinate directly — no name/address
    /// text search involved at all, unlike every other `url(...)` above.
    /// Google Maps' own search box already recognizes a bare "lat,lng"
    /// query string as a coordinate rather than search text (well-
    /// established, stable behavior of its URL API — not something that
    /// needed separate verification the way a less-common scheme like
    /// Naver's did) and drops a pin there. Meant for a photo's own EXIF
    /// GPS: better evidence of the real place than trusting whatever name
    /// AI guessed off the photo, since the user can see the actual pin
    /// and every nearby business themselves.
    static func url(coordinates: Coordinates) -> URL? {
        url(query: "\(coordinates.latitude),\(coordinates.longitude)")
    }

    private static func url(query: String?) -> URL? {
        guard let query else { return nil }
        var components = URLComponents(string: "https://www.google.com/maps/search/")
        components?.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "query", value: query),
        ]
        return components?.url
    }

    /// The Google Maps app's own `comgooglemaps://` URL scheme — tried
    /// first, ahead of the universal `https://www.google.com/maps` link
    /// above. In practice, opening that universal link directly (via
    /// `openURL`) has been observed handing an iOS user with no Google
    /// Maps app installed off to Apple's own Maps instead of Google's web
    /// map — the opposite of what picking "Google Maps" should do. Going
    /// through the app's own scheme first, and falling back to the
    /// universal link only when nothing answers it (see `open(for:using:)`),
    /// avoids that path entirely whenever the app is actually installed.
    static func appSchemeURL(for card: PlaceCard) -> URL? {
        appSchemeURL(query: query(for: card))
    }

    static func appSchemeURL(name: String, address: String) -> URL? {
        appSchemeURL(query: query(name: name, address: address))
    }

    static func appSchemeURL(coordinates: Coordinates) -> URL? {
        appSchemeURL(query: "\(coordinates.latitude),\(coordinates.longitude)")
    }

    private static func appSchemeURL(query: String?) -> URL? {
        guard let query, let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: "comgooglemaps://?q=\(encoded)")
    }

    /// Opens Google Maps for this card the reliable way: the app itself
    /// via its own URL scheme when it's installed, falling back to the
    /// universal web link only if nothing accepted that (`completion`'s
    /// `accepted == false`) — every call site that used to hand
    /// `url(for:)` straight to `openURL` should use this instead. See
    /// `appSchemeURL(for:)` for why.
    static func open(for card: PlaceCard, using openURL: OpenURLAction) {
        open(appURL: appSchemeURL(for: card), webURL: url(for: card), using: openURL)
    }

    /// The saved-card-independent counterpart to `open(for:using:)`.
    static func open(name: String, address: String, using openURL: OpenURLAction) {
        open(appURL: appSchemeURL(name: name, address: address), webURL: url(name: name, address: address), using: openURL)
    }

    /// The coordinate-only counterpart to `open(for:using:)`/`open(name:
    /// address:using:)` — see `url(coordinates:)`.
    static func open(coordinates: Coordinates, using openURL: OpenURLAction) {
        open(appURL: appSchemeURL(coordinates: coordinates), webURL: url(coordinates: coordinates), using: openURL)
    }

    private static func open(appURL: URL?, webURL: URL?, using openURL: OpenURLAction) {
        if let appURL {
            openURL(appURL) { accepted in
                guard !accepted, let webURL else { return }
                openURL(webURL)
            }
        } else if let webURL {
            openURL(webURL)
        }
    }

    private static func query(for card: PlaceCard) -> String? {
        query(name: card.name, address: card.address, coordinates: card.coordinates)
    }

    private static func query(name: String, address: String) -> String? {
        query(name: name, address: address, coordinates: nil)
    }

    private static func query(name: String, address: String, coordinates: Coordinates?) -> String? {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            guard let coordinates else { return nil }
            return "\(coordinates.latitude),\(coordinates.longitude)"
        }
        let trimmedAddress = address.trimmingCharacters(in: .whitespaces)
        return trimmedAddress.isEmpty ? trimmedName : "\(trimmedName), \(trimmedAddress)"
    }
}

/// Opens Apple's own Maps app. Prefers `MKMapItem` when the card has a
/// coordinate (it pins the exact point, and lets the launch options below
/// force Maps to actually jump there), and falls back to Apple's own
/// `maps.apple.com/?q=` text-search URL when it doesn't — the same thing
/// `GoogleMapsOpener` does with its own query URL. Before that fallback
/// existed, a card with no coordinate yet (created by hand, or shared from
/// a link that carried only a name) offered Google Maps but not Apple's,
/// which read as Apple Maps simply being broken: reported as "구글지도는
/// 이름만으로도 보낼 수 있는데 애플지도는 안 된다".
enum AppleMapsOpener {
    /// Roughly street level — same target `NaverMapOpener.mapURL`'s own
    /// `zoom: Int = 17` aims for, just expressed as MapKit's degrees-wide
    /// span instead of Naver's zoom-level integer.
    private static let defaultSpan = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)

    /// Whether this card can be opened in Apple Maps at all — a coordinate
    /// to pin, or at least a name to search for.
    static func canOpen(_ card: PlaceCard) -> Bool {
        card.coordinates != nil || !card.name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Apple's documented Maps URL scheme: `ll` pins an exact point and
    /// `q` labels it, and `q` alone is a plain search term — so unlike
    /// `MKMapItem` below this works with or without a coordinate.
    ///
    /// Needed as a *URL* (rather than the `MKMapItem` call) by the two
    /// web-based map tabs, whose marker balloons are HTML and can only
    /// offer a link.
    static func webURL(for card: PlaceCard) -> URL? {
        if let coordinates = card.coordinates {
            return webURL(coordinates: coordinates, label: card.name)
        }
        return webURL(name: card.name, address: card.address)
    }

    /// 이름/주소만으로 애플 지도 검색을 연다 — **카드가 아직 없는 자리**용
    /// (`AddPlaceCardView`의 후보 줄). `GoogleMapsOpener.url(name:address:)`의
    /// 애플 짝이다.
    ///
    /// 좌표가 없으니 `MKMapItem`은 쓸 수 없다. 애플이 문서로 정한 `?q=`
    /// 검색 URL을 쓴다 — 좌표 없는 카드에 하던 것과 같은 일이라, 그 몸통을
    /// 여기로 빼 `webURL(for:)`와 나눠 쓴다. 두 벌로 갈라 두면 한쪽만 고치게
    /// 된다.
    static func webURL(name: String, address: String) -> URL? {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return nil }
        let trimmedAddress = address.trimmingCharacters(in: .whitespaces)
        let query = trimmedAddress.isEmpty ? trimmedName : "\(trimmedName), \(trimmedAddress)"
        return url(queryItems: [URLQueryItem(name: "q", value: query)])
    }

    private static func webURL(coordinates: Coordinates, label: String) -> URL? {
        var queryItems = [
            URLQueryItem(name: "ll", value: "\(coordinates.latitude),\(coordinates.longitude)")
        ]
        // Nothing to label the pin with is fine; the pin itself is the
        // point. An empty `q`, on the other hand, is a search for
        // nothing, which lands Maps on a blank result instead.
        let trimmedLabel = label.trimmingCharacters(in: .whitespaces)
        if !trimmedLabel.isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: trimmedLabel))
        }
        return url(queryItems: queryItems)
    }

    private static func url(queryItems: [URLQueryItem]) -> URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = queryItems
        return components?.url
    }

    /// `GoogleMapsOpener.open(name:address:using:)`의 애플 짝. 좌표를 받는
    /// `open(coordinates:label:)`과 달리 `OpenURLAction`이 필요하다 —
    /// 이쪽은 URL을 여는 길밖에 없다.
    static func open(name: String, address: String, using openURL: OpenURLAction) {
        guard let url = webURL(name: name, address: address) else { return }
        openURL(url)
    }

    /// Pins the exact coordinate when there is one; otherwise hands the
    /// name/address to Maps' own search. `openURL` is only ever used for
    /// that second path — `MKMapItem.openInMaps` needs no `OpenURLAction`.
    static func open(for card: PlaceCard, using openURL: OpenURLAction) {
        guard card.coordinates != nil else {
            if let url = webURL(for: card) { openURL(url) }
            return
        }
        open(for: card)
    }

    /// 카드가 아직 없을 때 쓰는 입구 — "GPS로 촬영위치찾기"가 그렇다.
    /// 사진만 고른 단계라 이름도 주소도 없고 좌표 하나뿐이다.
    ///
    /// `GoogleMapsOpener.open(coordinates:using:)`의 애플 짝이지만
    /// `OpenURLAction`을 받지 않는다. 저쪽은 URL 스킴을 열어야 해서
    /// 필요하지만, 이쪽은 `MKMapItem.openInMaps`가 직접 연다 — 문자열로
    /// 꾸민 URL이 아니라 MapKit이 주는 길이라 애플 지도에서는 이게 가장
    /// 확실하다.
    static func open(coordinates: Coordinates, label: String) {
        open(
            coordinate: CLLocationCoordinate2D(
                latitude: coordinates.latitude, longitude: coordinates.longitude
            ),
            name: label
        )
    }

    private static func open(for card: PlaceCard) {
        guard let coordinates = card.coordinates else { return }
        open(
            coordinate: CLLocationCoordinate2D(
                latitude: coordinates.latitude, longitude: coordinates.longitude
            ),
            name: card.name
        )
    }

    private static func open(coordinate: CLLocationCoordinate2D, name: String) {
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = name
        // Calling `openInMaps()` with no launch options leaves the actual
        // centering up to Maps' own undocumented default — reported as
        // "엉뚱한곳이 중심에 있다": an already-running Maps app can keep
        // showing whatever region it had before instead of jumping to this
        // placemark, even though `coordinate` itself is correct (Google/
        // Naver don't hit this, since their own URL schemes hand the target
        // app a coordinate to parse fresh rather than relying on a "show
        // this item" API call). Passing the center/span explicitly forces
        // Maps to always jump here.
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsMapCenterKey: NSValue(mkCoordinate: coordinate),
            MKLaunchOptionsMapSpanKey: NSValue(mkCoordinateSpan: defaultSpan)
        ])
    }
}

/// Naver Map's own app URL scheme. There's no documented web fallback for
/// this one — `nmap://` only opens something when the Naver Map app is
/// installed. `appname` is just a required identifier for the calling app,
/// not a registered API key. Ported from Peragra's `NaverMapOpener`.
enum NaverMapOpener {
    private static let appName = "com.placecards.app"

    static func url(for card: PlaceCard) -> URL? {
        guard let coordinates = card.coordinates, !card.name.isEmpty,
              KoreaRegion.contains(latitude: coordinates.latitude, longitude: coordinates.longitude) else {
            return nil
        }
        var components = URLComponents(string: "nmap://place")
        components?.queryItems = [
            URLQueryItem(name: "lat", value: "\(coordinates.latitude)"),
            URLQueryItem(name: "lng", value: "\(coordinates.longitude)"),
            URLQueryItem(name: "name", value: card.name),
            URLQueryItem(name: "appname", value: appName),
        ]
        return components?.url
    }

    /// A plain keyword search, unlike `url(for:)` above (which needs an
    /// exact coordinate, since `/place` pins one specific point) — for a
    /// place with no verified coordinate yet, like an `AddPlaceCardView`
    /// candidate row a user wants to eyeball in the real Naver Map app
    /// before verifying it. Confirmed against NAVER Cloud Platform's own
    /// URL Scheme reference (`nmap://search?query=<keyword>&appname=
    /// <bundle id>`, both required) rather than guessed — this project
    /// has been burned before by guessing an external API's shape
    /// (`NaverPlaceSearchService`'s original endpoint/headers).
    static func searchURL(name: String, address: String) -> URL? {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return nil }
        let trimmedAddress = address.trimmingCharacters(in: .whitespaces)
        let query = trimmedAddress.isEmpty ? trimmedName : "\(trimmedName) \(trimmedAddress)"
        var components = URLComponents(string: "nmap://search")
        components?.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "appname", value: appName),
        ]
        return components?.url
    }

    /// The card-shaped counterpart to `searchURL(name:address:)`, for the
    /// saved-card "지도에서 열기" menu: `url(for:)` above needs a coordinate
    /// (its `nmap://place` scheme pins one specific point), so a card that
    /// doesn't have one yet used to get no Naver entry at all even though
    /// Google's was right there — reported alongside the same complaint
    /// about Apple Maps. Only offered while the card is unlocated; once it
    /// has a coordinate, `url(for:)`'s exact pin (and its `KoreaRegion`
    /// check) is the better answer.
    static func searchURL(for card: PlaceCard) -> URL? {
        guard card.coordinates == nil else { return nil }
        return searchURL(name: card.name, address: card.address)
    }

    /// Centers the map on an exact coordinate — no place name/search
    /// involved at all, unlike `url(for:)`/`searchURL(name:address:)`
    /// above. Meant for a photo's own EXIF GPS: rather than trust
    /// whatever name AI guessed off the photo, this drops the user right
    /// where it was actually taken so they can see for themselves which
    /// business is really there. Confirmed against NAVER Cloud Platform's
    /// own URL Scheme reference (`nmap://map?lat=...&lng=...&zoom=...&
    /// appname=...`, all four required) rather than guessed. `zoom` 17 is
    /// roughly street level — close enough to tell individual storefronts
    /// apart without the map coming up centered a whole neighborhood out.
    static func mapURL(coordinates: Coordinates, zoom: Int = 17) -> URL? {
        var components = URLComponents(string: "nmap://map")
        components?.queryItems = [
            URLQueryItem(name: "lat", value: "\(coordinates.latitude)"),
            URLQueryItem(name: "lng", value: "\(coordinates.longitude)"),
            URLQueryItem(name: "zoom", value: "\(zoom)"),
            URLQueryItem(name: "appname", value: appName),
        ]
        return components?.url
    }
}

/// Kakao Map's public "share a route" link — no API key needed. Opens the
/// native app on devices where it's installed, or map.kakao.com otherwise.
/// Ported from Peragra's `KakaoMapOpener`.
enum KakaoMapOpener {
    static func url(for card: PlaceCard) -> URL? {
        guard let coordinates = card.coordinates, !card.name.isEmpty,
              KoreaRegion.contains(latitude: coordinates.latitude, longitude: coordinates.longitude) else {
            return nil
        }
        var components = URLComponents(string: "https://map.kakao.com")
        components?.path = "/link/to/\(card.name),\(coordinates.latitude),\(coordinates.longitude)"
        return components?.url
    }

    /// Kakao's own documented keyword-search link (`/link/search/<검색어>`),
    /// the counterpart to `NaverMapOpener.searchURL(name:address:)` — for a
    /// card with no coordinate yet, where `url(for:)` above has nothing to
    /// build a `/link/to/` path from. Unlike that one this can't check
    /// `KoreaRegion` (there's no coordinate to check), so it's offered
    /// whenever the card is unlocated rather than pretending to know the
    /// place is in Korea: the same call the user is already making by
    /// picking Kakao Map from the menu themselves.
    static func searchURL(for card: PlaceCard) -> URL? {
        let trimmedName = card.name.trimmingCharacters(in: .whitespaces)
        guard card.coordinates == nil, !trimmedName.isEmpty else { return nil }
        let trimmedAddress = card.address.trimmingCharacters(in: .whitespaces)
        let query = trimmedAddress.isEmpty ? trimmedName : "\(trimmedName) \(trimmedAddress)"
        var components = URLComponents(string: "https://map.kakao.com")
        components?.path = "/link/search/\(query)"
        return components?.url
    }
}

/// Tmap's own app URL scheme. A starting point is optional — Tmap defaults
/// to the device's current location when rStX/rStY/rStName are omitted.
/// Ported from Peragra's `TmapOpener`.
enum TmapOpener {
    static func url(for card: PlaceCard) -> URL? {
        guard let coordinates = card.coordinates, !card.name.isEmpty,
              KoreaRegion.contains(latitude: coordinates.latitude, longitude: coordinates.longitude) else {
            return nil
        }
        var components = URLComponents(string: "tmap://route")
        components?.queryItems = [
            URLQueryItem(name: "rGoName", value: card.name),
            URLQueryItem(name: "rGoX", value: "\(coordinates.longitude)"),
            URLQueryItem(name: "rGoY", value: "\(coordinates.latitude)"),
        ]
        return components?.url
    }
}

/// The "지도에서 열기" menu, in one definition — `GalleryView`,
/// `PlaceCardListRow`, `PlaceCardDetailView` and `PlacesMapView`'s own
/// marker callout each had their own copy of this exact list, which is how
/// three of them ended up still offering Apple/Naver only for a card that
/// already had a coordinate long after Google's entry had learned to work
/// from a plain name.
///
/// Which entries appear is decided entirely by what the card can actually
/// open, not by what it has: each opener returns `nil` (or `canOpen` is
/// `false`) when it has nothing to work with, so a coordinate-less card
/// now still gets Google, Apple, Naver and Kakao via their text-search
/// URLs — only Tmap, whose scheme genuinely needs a destination point,
/// stays coordinate-only.
///
/// Every caller gets the same five entries, the app's own Apple map tab
/// included. That tab used to suppress Apple's, on the reasoning that
/// offering to "open" the pin already on screen was noise — but the two
/// aren't the same thing: the tab is an in-app `Map` view, and this entry
/// leaves the app for Maps proper, where turn-by-turn directions,
/// sharing, Look Around and the rest live. Suppressing it made the one
/// screen most obviously about a place the only one that couldn't hand it
/// to Apple Maps.
/// (`MenuLabel`, not `Label`: a generic parameter named `Label` would
/// shadow SwiftUI's own `Label` for the whole type.)
struct MapOpenMenu<MenuLabel: View>: View {
    let card: PlaceCard
    let label: () -> MenuLabel

    @Environment(\.openURL) private var openURL

    init(card: PlaceCard, @ViewBuilder label: @escaping () -> MenuLabel) {
        self.card = card
        self.label = label
    }

    var body: some View {
        Menu {
            if GoogleMapsOpener.url(for: card) != nil {
                Button("Google Maps") {
                    MapOpenContext.recordMapOpen(cardID: card.id)
                    GoogleMapsOpener.open(for: card, using: openURL)
                }
            }
            if AppleMapsOpener.canOpen(card) {
                Button("Apple 지도".localized) {
                    MapOpenContext.recordMapOpen(cardID: card.id)
                    AppleMapsOpener.open(for: card, using: openURL)
                }
            }
            if let url = NaverMapOpener.url(for: card) ?? NaverMapOpener.searchURL(for: card) {
                Button("Naver Map") {
                    MapOpenContext.recordMapOpen(cardID: card.id)
                    openURL(url)
                }
            }
            if let url = KakaoMapOpener.url(for: card) ?? KakaoMapOpener.searchURL(for: card) {
                Button("Kakao Map") {
                    MapOpenContext.recordMapOpen(cardID: card.id)
                    openURL(url)
                }
            }
            // No `MapOpenContext.recordMapOpen` here, unlike every entry
            // above: Tmap is turn-by-turn navigation, so tapping it means
            // "take me there", not "let me look this place up and share
            // something back". See `MapOpenContext`'s own doc comment.
            if let url = TmapOpener.url(for: card) {
                Button("Tmap") { openURL(url) }
            }
        } label: {
            label()
        }
    }
}

/// Shared by every place-card row/cell that offers a call/map/website/
/// Instagram action row (`PlaceCardGridCell`, `PlaceCardListRow`) — kept in
/// one place so both stay in sync instead of re-deriving the same checks.
extension PlaceCard {
    var callURL: URL? {
        guard let phone, !phone.isEmpty else { return nil }
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty else { return nil }
        return URL(string: "tel:\(digits)")
    }

    /// Whether `MapOpenMenu` would have anything at all to offer. Google
    /// and Apple both open from a plain name/address (each has its own
    /// text-search URL) as well as from a coordinate, and Naver/Kakao now
    /// fall back to their own keyword searches too — so a name alone is
    /// enough, and a coordinate alone (an unnamed pin) still is as well.
    var hasAnyMapLink: Bool {
        GoogleMapsOpener.url(for: self) != nil || coordinates != nil
    }

    /// A general web search for whatever reservation method this card
    /// notes (e.g. "캐치테이블 예약") together with the place's own name —
    /// not a direct deep link into that platform, since this app has no
    /// verified deep-link/search-URL format for Catch Table or any other
    /// specific Korean reservation platform (Catch Table's own site is a
    /// JS app with no documented public search URL — guessing one risked
    /// a link that silently goes nowhere, or to the wrong place, which is
    /// worse than no link). A plain web search reliably lands on a results
    /// page the user can find their way from regardless of which platform
    /// `reservationInfo` actually names.
    var reservationSearchURL: URL? {
        guard let reservationInfo, !reservationInfo.isEmpty else { return nil }
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: "\(reservationInfo) \(name)")]
        return components?.url
    }

    var hasAnyAction: Bool {
        callURL != nil || hasAnyMapLink || website != nil || instagramURL != nil || reservationSearchURL != nil
    }
}
