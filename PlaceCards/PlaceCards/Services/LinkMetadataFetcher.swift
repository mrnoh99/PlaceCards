import Foundation

/// Fetches a webpage's title/`og:title` metadata to recover a place name
/// from a bare share URL (Google Maps share links carry no name in the URL
/// itself, only a place ID or short link).
///
/// Different servers serve very different content depending on the
/// User-Agent: Google Maps serves a JS-only shell to normal browsers but a
/// static, pre-rendered page with the place name in its meta tags to known
/// crawlers. So a crawler UA is tried first, with a mobile Safari UA as a
/// fallback for sites that block crawlers outright.
enum LinkMetadataFetcher {
    private static let crawlerUserAgent =
        "facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)"
    private static let mobileSafariUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"

    static func fetchTitle(for url: URL, session: URLSession = .shared) async -> String? {
        guard let html = await fetchHTML(for: url, session: session) else { return nil }
        return extractOGTitle(from: html) ?? extractTitleTag(from: html)
    }

    /// Fetches a page's raw HTML with the same crawler-UA-then-mobile-
    /// Safari-UA fallback described above. Shared with
    /// `WebsiteBusinessInfoFetcher`, which needs the whole page (to find its
    /// JSON-LD structured data) rather than just a parsed title.
    static func fetchHTML(for url: URL, session: URLSession = .shared) async -> String? {
        if let html = await fetchHTML(for: url, userAgent: crawlerUserAgent, session: session) {
            return html
        }
        return await fetchHTML(for: url, userAgent: mobileSafariUserAgent, session: session)
    }

    private static func fetchHTML(for url: URL, userAgent: String, session: URLSession) async -> String? {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            return nil
        }

        return html
    }

    private static func extractOGTitle(from html: String) -> String? {
        if let title = firstMatch(
            in: html,
            pattern: #"<meta[^>]*property=["']og:title["'][^>]*content=["']([^"']+)["']"#
        ) {
            return title
        }
        // Attribute order in a <meta> tag isn't guaranteed, so try content-first too.
        return firstMatch(
            in: html,
            pattern: #"<meta[^>]*content=["']([^"']+)["'][^>]*property=["']og:title["']"#
        )
    }

    private static func extractTitleTag(from html: String) -> String? {
        firstMatch(in: html, pattern: #"<title[^>]*>([^<]+)</title>"#)
    }

    private static func firstMatch(in html: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let group = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[group])
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
