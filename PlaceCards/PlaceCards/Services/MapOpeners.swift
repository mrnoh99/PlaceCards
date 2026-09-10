import Foundation
import SwiftUI

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
        guard let query = query(for: card) else { return nil }
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
        guard let query = query(for: card),
              let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
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
        if let appURL = appSchemeURL(for: card) {
            openURL(appURL) { accepted in
                guard !accepted, let webURL = url(for: card) else { return }
                openURL(webURL)
            }
        } else if let webURL = url(for: card) {
            openURL(webURL)
        }
    }

    private static func query(for card: PlaceCard) -> String? {
        let trimmedName = card.name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            guard let coordinates = card.coordinates else { return nil }
            return "\(coordinates.latitude),\(coordinates.longitude)"
        }
        let trimmedAddress = card.address.trimmingCharacters(in: .whitespaces)
        return trimmedAddress.isEmpty ? trimmedName : "\(trimmedName), \(trimmedAddress)"
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

    var hasAnyMapLink: Bool {
        GoogleMapsOpener.url(for: self) != nil || NaverMapOpener.url(for: self) != nil
            || KakaoMapOpener.url(for: self) != nil || TmapOpener.url(for: self) != nil
    }

    var hasAnyAction: Bool {
        callURL != nil || hasAnyMapLink || website != nil || instagramURL != nil
    }
}
