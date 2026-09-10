import Foundation
import SwiftUI
import MapKit

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

/// Opens Apple's own Maps app via `MKMapItem` — needs a coordinate (unlike
/// `GoogleMapsOpener`, which can fall back to a plain name/address text
/// search), since that's how `MKMapItem`/`MKPlacemark` locate a place.
enum AppleMapsOpener {
    static func open(for card: PlaceCard) {
        guard let coordinates = card.coordinates else { return }
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: coordinates.latitude, longitude: coordinates.longitude))
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = card.name
        mapItem.openInMaps()
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

    /// Google Maps (name/address, or a raw coordinate) or Apple Maps
    /// (coordinate only) — whichever has enough to work with.
    var hasAnyMapLink: Bool {
        GoogleMapsOpener.url(for: self) != nil || coordinates != nil
    }

    var hasAnyAction: Bool {
        callURL != nil || hasAnyMapLink || website != nil || instagramURL != nil
    }
}
