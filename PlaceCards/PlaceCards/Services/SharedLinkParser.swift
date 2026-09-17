import Foundation

struct ParsedSharedPlace {
    var name: String?
    /// A street address, when the share itself hands one over as text
    /// (Naver) — never geocoded or guessed, only ever what was literally
    /// written in the shared content itself.
    var address: String?
    /// Exact coordinates, when they're recoverable straight from the
    /// share without any network round trip — a full (non-shortened)
    /// Google Maps URL already encodes them in its own path.
    var coordinates: Coordinates?
    /// Whatever else the share included beyond name/address/coordinates
    /// (Naver's extra detail lines) — folded into the candidate row's
    /// `scannedNote`, same destination as a photo scan's own description.
    var note: String?
    var url: URL?
    var source: SourceType
}

/// Google Maps and Naver Map hand the share sheet very different data, so
/// each needs its own parsing strategy:
/// - Google Maps only ever shares a URL. A *short* link (`goo.gl`) is an
///   opaque redirect token with nothing recoverable without following it,
///   so the caller falls back to `LinkMetadataFetcher`. A full link
///   (`google.com/maps/place/<name>/@<lat>,<lng>,<zoom>z/...`) already
///   encodes the place name and its exact coordinates right in the path —
///   both pulled out here with no network access at all.
/// - Naver Map shares plain text: an app-tag line (e.g. "[네이버 지도]"),
///   then the place name, address, and other details each on their own
///   line — all of it already text, so all of it is extracted directly.
/// - Apple Maps shares a URL whose *query string* holds the place — see
///   `parseAppleMapsURL`.
enum SharedLinkParser {
    static func parse(_ text: String) -> ParsedSharedPlace? {
        if let url = extractURL(from: text) {
            if isNaverMapHost(url) {
                return parseNaverText(text, url: url)
            }
            if isAppleMapHost(url) {
                let (name, address, coordinates) = parseAppleMapsURL(url)
                return ParsedSharedPlace(
                    name: name,
                    address: address,
                    coordinates: coordinates,
                    note: nil,
                    url: url,
                    source: .appleMapShare
                )
            }
            if isGoogleMapHost(url) {
                let (name, address, coordinates) = parseGoogleMapsURLPath(url)
                return ParsedSharedPlace(
                    name: name,
                    address: address,
                    coordinates: coordinates,
                    note: nil,
                    url: url,
                    source: .googleMapShare
                )
            }
        }

        if looksLikeNaverShareText(text) {
            return parseNaverText(text, url: nil)
        }

        return nil
    }

    /// Instagram only ever shares a bare post/reel URL with no place data
    /// in it at all — unlike Google Maps' full share links (a real place
    /// name and coordinates sitting right in the path) or Naver's share
    /// text (name/address as plain text), there's nothing here worth
    /// resolving automatically; whatever a caption/location tag might say
    /// would need a page fetch whose result is a caption string at best,
    /// not a verifiable name+address. The caller (`MainTabView`) uses
    /// this to skip straight to asking the user to screenshot the post
    /// and add it through the existing photo-scan flow instead, rather
    /// than seeding a row with a raw link that's certain to fail search.
    static func isInstagramLink(_ text: String) -> Bool {
        guard let url = extractURL(from: text), let host = url.host else { return false }
        return host.contains("instagram.com")
    }

    static func extractURL(from text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = detector.firstMatch(in: text, range: range) else { return nil }
        return match.url
    }

    private static func isGoogleMapHost(_ url: URL) -> Bool {
        guard let host = url.host else { return false }
        if host.contains("goo.gl") { return true }
        return host.contains("google.com") && url.path.contains("/maps")
    }

    private static func isNaverMapHost(_ url: URL) -> Bool {
        guard let host = url.host else { return false }
        return host.contains("map.naver.com") || host.contains("naver.me")
    }

    private static func isAppleMapHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "maps.apple.com" || host.hasSuffix(".maps.apple.com")
    }

    /// Apple Maps puts the shared place in its URL's *query string*, so —
    /// like a full Google Maps link, and unlike a short one — the name,
    /// address and exact coordinate all come out of the URL itself with no
    /// network round trip.
    ///
    /// Apple's own Maps URL Scheme reference documents `q` (the search
    /// term, or the label for `ll`), `ll` ("latitude,longitude") and
    /// `address`; shares have also been seen spelling those last two
    /// `name` and `coordinate`, so both spellings are read. This only ever
    /// *reads* keys it recognises, so a share that uses none of them (a
    /// short `maps.apple.com/p/...` link, say) simply yields `nil`s and
    /// leaves the caller to its existing page-title fallback — the URL
    /// still comes back as this place's map link rather than, as before,
    /// being filed as the business's own website.
    private static func parseAppleMapsURL(_ url: URL) -> (name: String?, address: String?, coordinates: Coordinates?) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return (nil, nil, nil)
        }

        func value(forAnyOf keys: [String]) -> String? {
            for key in keys {
                guard let raw = queryItems.first(where: { $0.name.caseInsensitiveCompare(key) == .orderedSame })?.value else {
                    continue
                }
                // `URLComponents` percent-decodes but leaves "+" alone, and
                // these values use it for spaces — same treatment
                // `parseGoogleMapsURLPath` gives its own name segment.
                let decoded = raw
                    .replacingOccurrences(of: "+", with: " ")
                    .trimmingCharacters(in: .whitespaces)
                    .strippingInvisibleFormatCharacters()
                if !decoded.isEmpty { return decoded }
            }
            return nil
        }

        let coordinates = value(forAnyOf: ["ll", "coordinate", "sll"]).flatMap(parseCoordinatePair)
        let address = value(forAnyOf: ["address"])

        // `q` is the place's label for a named place but a bare
        // "lat,lng" string for a dropped pin — which is not a name, and
        // saving it as one is how a card ends up called "37.5665,126.978".
        var name = value(forAnyOf: ["name"])
        if name == nil, let query = value(forAnyOf: ["q"]), parseCoordinatePair(query) == nil {
            name = query
        }

        return (name, address, coordinates)
    }

    /// "latitude,longitude", rejected unless both halves parse *and* fall
    /// inside the real ranges — a query value that merely contains a comma
    /// must not become a coordinate.
    private static func parseCoordinatePair(_ text: String) -> Coordinates? {
        let parts = text.split(separator: ",")
        guard parts.count == 2,
              let latitude = Double(parts[0].trimmingCharacters(in: .whitespaces)),
              let longitude = Double(parts[1].trimmingCharacters(in: .whitespaces)),
              (-90.0...90.0).contains(latitude),
              (-180.0...180.0).contains(longitude) else {
            return nil
        }
        return Coordinates(latitude: latitude, longitude: longitude)
    }

    private static func looksLikeNaverShareText(_ text: String) -> Bool {
        // Naver's share text starts with an app-name tag line like "[네이버 지도]".
        text.split(separator: "\n").first?.trimmingCharacters(in: .whitespaces).hasPrefix("[") == true
    }

    /// Naver's share text is a handful of lines: an app tag, the place name,
    /// then address/other details. The tag line and any bare URL line
    /// (already captured separately as `url`) are dropped; of what's left,
    /// the first line is the name, the second the address, and anything
    /// further is joined into `note`.
    private static func parseNaverText(_ text: String, url: URL?) -> ParsedSharedPlace {
        let urlString = url?.absoluteString
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces).strippingInvisibleFormatCharacters() }
            .filter { line in
                guard !line.isEmpty, !line.hasPrefix("[") else { return false }
                if let urlString, line == urlString { return false }
                return !(line.hasPrefix("http://") || line.hasPrefix("https://"))
            }

        return ParsedSharedPlace(
            name: lines.first,
            address: lines.count > 1 ? lines[1] : nil,
            coordinates: nil,
            note: lines.count > 2 ? lines[2...].joined(separator: "\n") : nil,
            url: url,
            source: .naverMapShare
        )
    }

    /// Google's own page `<title>`/`og:title` for a Maps share reads
    /// "이름 · 지역, 지역" (a middle dot before the locality) — the same
    /// name-plus-address shape `parseGoogleMapsURLPath`'s own name segment
    /// carries, just spelled with " · " instead of a comma. This is the
    /// fallback `MapLinkImportSheet`/`PlaceCardViewModel.resolveSharedPlace`
    /// use for a short (`goo.gl`) Google Maps link, whose URL path alone
    /// has no name to parse — left unsplit, the whole "이름 · 지역" string
    /// lands in `name` alone, which is exactly why merging a shared link
    /// back into an already-named card could prompt "이름이 다릅니다" even
    /// though the actual place name (before the " · ") was identical.
    static func splitGoogleTitle(_ title: String) -> (name: String, address: String?) {
        guard let dotRange = title.range(of: " · ") else { return (title, nil) }
        let name = String(title[..<dotRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        let addressPart = String(title[dotRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        return (name.isEmpty ? title : name, addressPart.isEmpty ? nil : addressPart)
    }

    /// Pulls the place name, address, and coordinates straight out of a
    /// full Google Maps URL's own path (`/maps/place/<name>/@<lat>,<lng>,
    /// <zoom>z/...`) — every value Google Maps' own share button already
    /// puts there, so none of it needs a page fetch to recover. Silently
    /// yields `(nil, nil, nil)` for anything that doesn't match this shape
    /// (a short `goo.gl` link, or any other Google Maps URL form), which
    /// just means the caller's `LinkMetadataFetcher` fallback runs instead
    /// — never a bug on its own.
    private static func parseGoogleMapsURLPath(_ url: URL) -> (name: String?, address: String?, coordinates: Coordinates?) {
        let path = url.path

        var name: String?
        var address: String?
        if let placeRange = path.range(of: "/place/") {
            let afterPlace = path[placeRange.upperBound...]
            let nameSegment = afterPlace.prefix(while: { $0 != "/" })
            // A URL zoomed to bare coordinates rather than a named place
            // (e.g. ".../place/@37.5,127.0,14z/") puts the "@lat,lng,zoom"
            // segment right where a name would be — not a real name.
            if !nameSegment.hasPrefix("@") {
                // Google is known to embed invisible bidi direction-control
                // marks in a mixed-script (Korean + Latin/numeric) place
                // name — harmless in a browser, but left in here it makes
                // this name compare as different from the same place's
                // name elsewhere in the app (every other source of a name/
                // address, and every already-saved card on load, already
                // strips these — see `String.strippingInvisibleFormat
                // Characters()`'s own comment). Missing this stripping
                // here specifically is exactly why sharing a place back
                // from the Google Maps app could trigger "이름이 다릅니다"
                // even when the two names were visually identical.
                let decoded = String(nameSegment)
                    .replacingOccurrences(of: "+", with: " ")
                    .removingPercentEncoding?
                    .strippingInvisibleFormatCharacters()
                if let decoded, !decoded.isEmpty {
                    // Whenever there's no single unambiguous display name
                    // to put on the pin (a bare address pin, or a venue
                    // Google only knows by its street context), this same
                    // segment instead carries the full comma-separated
                    // string Google would show as the title — e.g.
                    // ".../place/서울특별시+강남구+테헤란로+152,+대한민국/...".
                    // Left unsplit, the whole thing (name AND address)
                    // landed in `name` alone with `address` always `nil` —
                    // which is exactly why a shared-back card kept asking
                    // "이름이 다릅니다" against an already-clean saved name,
                    // and why the Google Places search this feeds
                    // (`MapLinkImportSheet.enrichFromGooglePlaces()`) had
                    // a garbled query to match against. Splitting on the
                    // first comma keeps just the actual name/street line
                    // in `name` and folds the rest into `address`, mirroring
                    // how `formattedAddress` itself is comma-joined.
                    if let commaIndex = decoded.firstIndex(of: ",") {
                        name = String(decoded[..<commaIndex]).trimmingCharacters(in: .whitespaces)
                        let addressPart = String(decoded[decoded.index(after: commaIndex)...])
                            .trimmingCharacters(in: .whitespaces)
                        address = addressPart.isEmpty ? nil : addressPart
                    } else {
                        name = decoded
                    }
                }
            }
        }

        var coordinates: Coordinates?
        if let atRange = path.range(of: "/@") {
            let afterAt = path[atRange.upperBound...]
            let coordsSegment = afterAt.prefix(while: { $0 != "/" })
            let parts = coordsSegment.split(separator: ",")
            if parts.count >= 2, let latitude = Double(parts[0]), let longitude = Double(parts[1]) {
                coordinates = Coordinates(latitude: latitude, longitude: longitude)
            }
        }

        return (name, address, coordinates)
    }
}
