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
enum SharedLinkParser {
    static func parse(_ text: String) -> ParsedSharedPlace? {
        if let url = extractURL(from: text) {
            if isNaverMapHost(url) {
                return parseNaverText(text, url: url)
            }
            if isGoogleMapHost(url) {
                let (name, coordinates) = parseGoogleMapsURLPath(url)
                return ParsedSharedPlace(
                    name: name,
                    address: nil,
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

    /// Pulls the place name and coordinates straight out of a full Google
    /// Maps URL's own path (`/maps/place/<name>/@<lat>,<lng>,<zoom>z/...`)
    /// — every value Google Maps' own share button already puts there, so
    /// none of it needs a page fetch to recover. Silently yields `(nil, nil)`
    /// for anything that doesn't match this shape (a short `goo.gl` link,
    /// or any other Google Maps URL form), which just means the caller's
    /// `LinkMetadataFetcher` fallback runs instead — never a bug on its own.
    private static func parseGoogleMapsURLPath(_ url: URL) -> (name: String?, coordinates: Coordinates?) {
        let path = url.path

        var name: String?
        if let placeRange = path.range(of: "/place/") {
            let afterPlace = path[placeRange.upperBound...]
            let nameSegment = afterPlace.prefix(while: { $0 != "/" })
            // A URL zoomed to bare coordinates rather than a named place
            // (e.g. ".../place/@37.5,127.0,14z/") puts the "@lat,lng,zoom"
            // segment right where a name would be — not a real name.
            if !nameSegment.hasPrefix("@") {
                let decoded = String(nameSegment)
                    .replacingOccurrences(of: "+", with: " ")
                    .removingPercentEncoding
                name = (decoded?.isEmpty == false) ? decoded : nil
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

        return (name, coordinates)
    }
}
