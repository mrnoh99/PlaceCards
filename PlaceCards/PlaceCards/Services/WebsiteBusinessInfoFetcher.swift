import Foundation

/// Recovered from a business homepage's own schema.org JSON-LD structured
/// data (`<script type="application/ld+json">`) — the same markup real
/// sites already embed so Google's own knowledge panel can show them,
/// which makes it the most reliable source for a place Google Maps itself
/// doesn't have listed.
struct ExtractedBusinessInfo {
    let name: String
    let address: String?
    /// Phone/hours formatted into one string, meant for `PlaceCard.memo`
    /// (via `PlaceCard.combinedMemo`) rather than a dedicated field — unlike
    /// a Google/Naver Places phone number, `telephone` here comes from the
    /// business's own page with no independent verification behind it.
    let note: String?
}

/// Deliberately doesn't restrict matches to a fixed list of schema.org
/// `@type` values ("LocalBusiness", "Restaurant", "Store", ...) — schema.org
/// has dozens of `LocalBusiness` subtypes and keeps adding more, so instead
/// any JSON-LD object with a `name` *and* at least one of `address`/
/// `telephone` is accepted as a real business listing.
enum WebsiteBusinessInfoFetcher {
    static func fetch(for url: URL, session: URLSession = .shared) async -> ExtractedBusinessInfo? {
        guard let html = await LinkMetadataFetcher.fetchHTML(for: url, session: session) else { return nil }
        for block in jsonLDBlocks(in: html) {
            if let info = businessInfo(fromJSONLD: block) {
                return info
            }
        }
        return nil
    }

    private static func jsonLDBlocks(in html: String) -> [String] {
        let pattern = #"<script[^>]*type=["']application/ld\+json["'][^>]*>([\s\S]*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let bodyRange = Range(match.range(at: 1), in: html) else { return nil }
            return String(html[bodyRange])
        }
    }

    private static func businessInfo(fromJSONLD raw: String) -> ExtractedBusinessInfo? {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else { return nil }

        for object in flattenedObjects(from: json) {
            if let info = businessInfo(from: object) {
                return info
            }
        }
        return nil
    }

    /// JSON-LD can hand over a single object, an array of them, or an
    /// `@graph` wrapper holding the array — flattened here into one list of
    /// plain objects so every shape is searched the same way.
    private static func flattenedObjects(from json: Any) -> [[String: Any]] {
        if let object = json as? [String: Any] {
            if let graph = object["@graph"] as? [Any] {
                return graph.compactMap { $0 as? [String: Any] }
            }
            return [object]
        }
        if let array = json as? [Any] {
            return array.compactMap { $0 as? [String: Any] }
        }
        return []
    }

    private static func businessInfo(from object: [String: Any]) -> ExtractedBusinessInfo? {
        guard let name = (object["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else {
            return nil
        }

        let address = formattedAddress(from: object["address"])
        let telephone = (object["telephone"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard address != nil || (telephone?.isEmpty == false) else { return nil }

        var noteLines: [String] = []
        if let telephone, !telephone.isEmpty {
            noteLines.append("전화번호: ".localized + telephone)
        }
        if let hours = formattedOpeningHours(from: object["openingHours"]) {
            noteLines.append(hours)
        }

        return ExtractedBusinessInfo(
            name: name.strippingInvisibleFormatCharacters(),
            address: address?.strippingInvisibleFormatCharacters(),
            note: noteLines.isEmpty ? nil : noteLines.joined(separator: "\n")
        )
    }

    private static func formattedAddress(from raw: Any?) -> String? {
        if let string = raw as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard let object = raw as? [String: Any] else { return nil }
        let parts = [
            object["streetAddress"] as? String,
            object["addressLocality"] as? String,
            object["addressRegion"] as? String,
            object["postalCode"] as? String
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// `openingHours` can be a single string or an array of strings (both
    /// are valid schema.org shapes); the structured `openingHoursSpecification`
    /// form needs day/time fields this app has nowhere to display, so it's
    /// skipped here rather than half-parsed into something misleading.
    private static func formattedOpeningHours(from raw: Any?) -> String? {
        if let string = raw as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : "영업시간(홈페이지): ".localized + trimmed
        }
        if let array = raw as? [String] {
            let joined = array
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            return joined.isEmpty ? nil : "영업시간(홈페이지): ".localized + joined
        }
        return nil
    }
}
