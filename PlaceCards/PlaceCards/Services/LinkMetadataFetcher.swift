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

    /// An `og:` property triple plus the URL the request actually ended up
    /// at after redirects. `GoogleMapsListParser` needs all of it: a shared
    /// Google Maps list arrives as a `maps.app.goo.gl` short link whose
    /// *final* URL is the only reliable way to tell a list apart from a
    /// single place, and the list's own contents are carried in `og:image`
    /// (its map-thumbnail URL encodes one feature-ID block per pin).
    struct PageMetadata {
        var finalURL: URL
        var title: String?
        var description: String?
        var image: String?
    }

    static func fetchMetadata(for url: URL, session: URLSession = .shared) async -> PageMetadata? {
        guard let page = await fetchPage(for: url, session: session) else { return nil }
        return PageMetadata(
            finalURL: page.finalURL,
            title: extractOGTitle(from: page.html) ?? extractTitleTag(from: page.html),
            description: extractOGProperty("description", from: page.html),
            image: extractOGProperty("image", from: page.html)
        )
    }

    /// Fetches a page's raw HTML with the same crawler-UA-then-mobile-
    /// Safari-UA fallback described above. Shared with
    /// `WebsiteBusinessInfoFetcher`, which needs the whole page (to find its
    /// JSON-LD structured data) rather than just a parsed title.
    static func fetchHTML(for url: URL, session: URLSession = .shared) async -> String? {
        await fetchPage(for: url, session: session)?.html
    }

    /// The page body plus wherever the request finally landed — `URLSession`
    /// follows redirects on its own, so this is also how a short link gets
    /// resolved, with no separate HEAD request of its own.
    private struct Page {
        var html: String
        var finalURL: URL
    }

    private static func fetchPage(for url: URL, session: URLSession) async -> Page? {
        if let page = await fetchPage(for: url, userAgent: crawlerUserAgent, session: session) {
            return page
        }
        return await fetchPage(for: url, userAgent: mobileSafariUserAgent, session: session)
    }

    /// What language the fetched page should come back in. Google serves
    /// a place's `og:title` address in whatever this asks for — without it
    /// a Korean address comes back transliterated ("454-5 Cheongoksan-gil,
    /// Mitan-myeon, Pyeongchang-gun, Gangwon-do, South Korea") instead of
    /// as written ("대한민국 강원특별자치도 평창군 미탄면 청옥산길 454-5"),
    /// which is what then gets saved onto the card.
    private static var acceptLanguage: String {
        AppLanguage.current() == .english ? "en-US,en;q=0.9" : "ko-KR,ko;q=0.9,en;q=0.8"
    }

    private static func fetchPage(for url: URL, userAgent: String, session: URLSession) async -> Page? {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(acceptLanguage, forHTTPHeaderField: "Accept-Language")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            return nil
        }

        return Page(html: html, finalURL: http.url ?? url)
    }

    private static func extractOGTitle(from html: String) -> String? {
        extractOGProperty("title", from: html)
    }

    private static func extractOGProperty(_ property: String, from html: String) -> String? {
        if let value = firstMatch(
            in: html,
            pattern: #"<meta[^>]*property=["']og:"# + property + #"["'][^>]*content=["']([^"']*)["']"#
        ), !value.isEmpty {
            return value
        }
        // Attribute order in a <meta> tag isn't guaranteed, so try content-first too.
        let value = firstMatch(
            in: html,
            pattern: #"<meta[^>]*content=["']([^"']*)["'][^>]*property=["']og:"# + property + #"["']"#
        )
        return (value?.isEmpty ?? true) ? nil : value
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
