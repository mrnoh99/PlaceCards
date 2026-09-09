import Foundation

struct ParsedSharedPlace {
    var name: String?
    var url: URL?
    var source: SourceType
}

/// Google Maps and Naver Map hand the share sheet very different data, so
/// each needs its own parsing strategy:
/// - Google Maps only shares a URL, with no place name in it at all — the
///   name has to come from fetching the page (`LinkMetadataFetcher`).
/// - Naver Map shares plain text: an app-tag line (e.g. "[네이버 지도]"),
///   then the place name, address, and other details each on their own line.
enum SharedLinkParser {
    static func parse(_ text: String) -> ParsedSharedPlace? {
        if let url = extractURL(from: text) {
            if isNaverMapHost(url) {
                return parseNaverText(text, url: url)
            }
            if isGoogleMapHost(url) {
                // No place name is recoverable from the URL itself here —
                // the caller resolves it separately via LinkMetadataFetcher.
                return ParsedSharedPlace(name: nil, url: url, source: .googleMapShare)
            }
        }

        if looksLikeNaverShareText(text) {
            return parseNaverText(text, url: nil)
        }

        return nil
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
    /// then address/other details. The tag line is dropped and the first
    /// remaining non-empty line is treated as the name.
    private static func parseNaverText(_ text: String, url: URL?) -> ParsedSharedPlace {
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("[") }

        return ParsedSharedPlace(name: lines.first, url: url, source: .naverMapShare)
    }
}
