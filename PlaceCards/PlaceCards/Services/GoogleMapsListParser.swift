import Foundation

/// One place recovered from a shared Google Maps list.
struct SharedListPlace: Identifiable {
    /// Google's own CID for this place — the second of the two 64-bit
    /// halves of its internal feature ID, and the one `maps.google.com/?cid=`
    /// accepts. Doubles as this value's identity, since a list never holds
    /// the same place twice.
    var id: String { cid }
    var cid: String
    var name: String
    var address: String?
    /// Google's own category slug for the pin (`gcid:catholic_church` →
    /// "catholic_church"), read straight off the list thumbnail. Only used
    /// as a fallback — a Places verification fills in the properly
    /// localized category text when it runs.
    var category: String?
    /// `https://maps.google.com/?cid=…` — a stable, canonical link to this
    /// exact listing, saved on the card the same way a single Google Maps
    /// share's own URL already is.
    var mapURL: URL
}

/// A shared Google Maps list ("저장됨" → 목록 → 공유), as far as it can be
/// recovered from outside Google.
struct SharedPlaceList {
    /// The list's own name — becomes the new board's name.
    var name: String
    var ownerName: String?
    /// What Google's own `og:description` says the list holds ("2 places").
    /// Kept as a checksum against `places.count`: the thumbnail this
    /// parser reads pins out of is a picture, and a long list's picture
    /// may well not carry a pin for every single entry, so this is the
    /// only way to know that what was recovered is short.
    var statedCount: Int?
    var places: [SharedListPlace]
    var sourceURL: URL

    /// Whether every place Google says is in the list was actually
    /// recovered. `false` means the user has to be told, not quietly given
    /// a partial import.
    var isComplete: Bool {
        guard let statedCount else { return true }
        return places.count >= statedCount
    }

    var missingCount: Int {
        guard let statedCount else { return 0 }
        return max(0, statedCount - places.count)
    }
}

/// Recovers the places in a shared Google Maps list.
///
/// There is no API for this — Google Places has no endpoint that reads a
/// user's list — and the list page itself is a JavaScript shell whose
/// actual contents arrive over a separate internal RPC. What makes this
/// work without running that JavaScript is that the page's *metadata*,
/// served to crawler user agents (the same trick `LinkMetadataFetcher`
/// already relies on for single places), carries enough:
///
/// - `og:title` is "<list name> · <owner>"
/// - `og:description` is "N places - "
/// - `og:image` is the list's map-thumbnail URL, and its `pb=` parameter
///   encodes one block per pin: `!1y<cellId>!2y<cid>!2s<mid>` plus
///   `!15sgcid:<category>`.
///
/// The `2y` half of each feature ID is the place's CID, and
/// `maps.google.com/?cid=<CID>` is a real page whose own `og:title` is
/// "<place name> · <full address>". So one fetch for the list plus one per
/// place recovers name and address for every pin, using nothing but
/// documented-shaped `og:` tags — no scraping of Google's obfuscated
/// `APP_INITIALIZATION_STATE` blob, which changes without notice.
///
/// Everything here is best-effort by design. A failure at any step returns
/// `nil`/fewer places rather than throwing, and the caller
/// (`SharedLinkBoardPickerSheet`) falls back to asking the user to
/// screenshot the list instead — which works, since the AI photo scan
/// already reads several places out of one image.
enum GoogleMapsListParser {
    /// Hard ceiling on how many places one shared list will be turned into.
    /// Each one costs a page fetch here and, once the user saves, a Google
    /// Places lookup on their own API key — a runaway list shouldn't be
    /// able to spend either without bound.
    static let maxPlaces = 200

    /// How many place lookups run at once. The rest of this app fans work
    /// out with an unbounded `TaskGroup`, which is fine for the five-ish
    /// rows a photo scan produces but not for a list that can hold
    /// hundreds — that many simultaneous requests is how a client gets
    /// rate-limited rather than served.
    private static let concurrentLookups = 5

    /// Whether this URL is (or redirects to) a shared list rather than a
    /// single place. A `maps.app.goo.gl` short link gives nothing away on
    /// its own, so this is decided from the URL the fetch actually landed
    /// on — see `fetchList(from:)`.
    static func isListURL(_ url: URL) -> Bool {
        let absolute = url.absoluteString
        if url.path.contains("/maps/placelists/list/") { return true }
        // What `/maps/placelists/list/<id>` itself redirects to: the list id
        // moves into the opaque `data=` blob, tagged `!11m1!2s<id>`.
        return absolute.contains("!11m1!2s")
    }

    /// Whether this share is a list, without paying for the per-place
    /// lookups `fetchList(from:)` does. Used where the only thing that
    /// matters is which screen to route to — `MainTabView` has to know
    /// before it can decide whether a share belongs to the card the user
    /// just opened a map for, and a list never does.
    static func isSharedList(_ url: URL, session: URLSession = .shared) async -> Bool {
        guard let metadata = await LinkMetadataFetcher.fetchMetadata(for: url, session: session) else {
            return false
        }
        return isListURL(metadata.finalURL)
    }

    /// `nil` when this isn't a shared list at all (the overwhelmingly
    /// common case — an ordinary single-place share), or when the page
    /// couldn't be read.
    static func fetchList(from url: URL, session: URLSession = .shared) async -> SharedPlaceList? {
        guard let metadata = await LinkMetadataFetcher.fetchMetadata(for: url, session: session) else {
            return nil
        }
        guard isListURL(metadata.finalURL) else { return nil }

        let (listName, owner) = splitOnMiddleDot(metadata.title)
        guard let listName, !listName.isEmpty else { return nil }

        let entries = featureEntries(in: metadata.image ?? "").prefix(maxPlaces)
        let places = await resolvePlaces(Array(entries), session: session)

        return SharedPlaceList(
            name: listName,
            ownerName: owner,
            statedCount: statedPlaceCount(in: metadata.description),
            places: places,
            sourceURL: metadata.finalURL
        )
    }

    // MARK: - Thumbnail parsing

    private struct FeatureEntry {
        var cid: String
        var category: String?
    }

    /// One entry per pin in the thumbnail's `pb=` parameter. Each pin's
    /// block starts `!5m8!1m2!1y<cellId>!2y<cid>!2s<mid>` and its category
    /// (`!15sgcid:<slug>`) follows before the next block begins.
    private static func featureEntries(in thumbnailURL: String) -> [FeatureEntry] {
        let pattern = #"!1y\d+!2y(\d+)!2s/[a-z]/[0-9a-z_]+(.*?)(?=!1y\d+!2y|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(thumbnailURL.startIndex..., in: thumbnailURL)

        var entries: [FeatureEntry] = []
        var seen: Set<String> = []
        for match in regex.matches(in: thumbnailURL, range: range) {
            guard let cidRange = Range(match.range(at: 1), in: thumbnailURL) else { continue }
            let cid = String(thumbnailURL[cidRange])
            guard !cid.isEmpty, seen.insert(cid).inserted else { continue }

            var category: String?
            if let tailRange = Range(match.range(at: 2), in: thumbnailURL) {
                category = firstMatch(in: String(thumbnailURL[tailRange]), pattern: #"!15sgcid:([a-z0-9_]+)"#)
            }
            entries.append(FeatureEntry(cid: cid, category: category))
        }
        return entries
    }

    private static func statedPlaceCount(in description: String?) -> Int? {
        guard let description,
              let text = firstMatch(in: description, pattern: #"(\d+)\s+places?"#) else { return nil }
        return Int(text)
    }

    // MARK: - Per-place resolution

    /// Resolves each pin's CID into a real name/address, at most
    /// `concurrentLookups` at a time. Order is preserved so the saved cards
    /// come out in the order the list showed them; a place that fails to
    /// resolve is dropped rather than saved under a placeholder name, and
    /// `SharedPlaceList.isComplete` is what surfaces that it happened.
    private static func resolvePlaces(_ entries: [FeatureEntry], session: URLSession) async -> [SharedListPlace] {
        guard !entries.isEmpty else { return [] }

        var resolved: [(offset: Int, place: SharedListPlace)] = []
        for chunk in stride(from: 0, to: entries.count, by: concurrentLookups) {
            let upperBound = min(chunk + concurrentLookups, entries.count)
            let batch = await withTaskGroup(of: (Int, SharedListPlace?).self) { group -> [(Int, SharedListPlace?)] in
                for offset in chunk..<upperBound {
                    let entry = entries[offset]
                    group.addTask {
                        (offset, await resolvePlace(entry, session: session))
                    }
                }
                var collected: [(Int, SharedListPlace?)] = []
                for await result in group {
                    collected.append(result)
                }
                return collected
            }
            for (offset, place) in batch {
                if let place { resolved.append((offset, place)) }
            }
        }

        return resolved.sorted { $0.offset < $1.offset }.map(\.place)
    }

    private static func resolvePlace(_ entry: FeatureEntry, session: URLSession) async -> SharedListPlace? {
        guard let url = URL(string: "https://maps.google.com/?cid=\(entry.cid)") else { return nil }
        guard let metadata = await LinkMetadataFetcher.fetchMetadata(for: url, session: session) else { return nil }

        let (name, address) = splitOnMiddleDot(metadata.title)
        guard let name, !name.isEmpty else { return nil }

        return SharedListPlace(
            cid: entry.cid,
            name: name.strippingInvisibleFormatCharacters(),
            address: address?.strippingInvisibleFormatCharacters(),
            category: entry.category.map(readableCategory),
            mapURL: url
        )
    }

    // MARK: - Helpers

    /// Google writes both "<list name> · <owner>" and "<place name> ·
    /// <address>" with the same " · " separator, split on the *first* one
    /// so an address that contains it of its own doesn't lose its tail.
    private static func splitOnMiddleDot(_ text: String?) -> (String?, String?) {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return (nil, nil)
        }
        guard let separator = text.range(of: " · ") else { return (text, nil) }
        let leading = String(text[..<separator.lowerBound]).trimmingCharacters(in: .whitespaces)
        let trailing = String(text[separator.upperBound...]).trimmingCharacters(in: .whitespaces)
        return (leading, trailing.isEmpty ? nil : trailing)
    }

    /// "catholic_church" → "Catholic Church". Google's category slugs are
    /// only ever a rough fallback here, so this is a plain de-slugging
    /// rather than a lookup table that would need a new entry per category
    /// Google invents.
    private static func readableCategory(_ slug: String) -> String {
        slug.split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let group = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[group])
    }
}
