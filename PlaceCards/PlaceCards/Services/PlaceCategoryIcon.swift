import Foundation

/// Best-effort outline SF Symbol for a free-text Google Places category
/// string — there's no fixed taxonomy to switch over here (unlike
/// Peragra's `PlaceCategory` enum), so this keyword-matches instead,
/// falling back to a generic tag icon. Every symbol below is the plain
/// (outline) variant, never a ".fill" one, to match the app's minimalist
/// outline look.
enum PlaceCategoryIcon {
    /// "Cafe"/"Coffee shop" (Google) and "카페"/"커피숍"/"커피전문점"
    /// (Korean) all mean the same thing but arrive as different raw
    /// strings — matched together here so both the icon and
    /// `normalizedLabel(for:)` treat them identically.
    private static func isCafe(_ lowercasedText: String) -> Bool {
        lowercasedText.contains("cafe") || lowercasedText.contains("coffee")
            || lowercasedText.contains("카페") || lowercasedText.contains("커피")
    }

    static func symbolName(for category: String?) -> String {
        guard let category, !category.isEmpty else { return "tag" }
        let text = category.lowercased()

        if isCafe(text) {
            return "cup.and.saucer"
        }
        if text.contains("restaurant") || text.contains("food") || text.contains("식당") || text.contains("음식") {
            return "fork.knife"
        }
        if text.contains("hotel") || text.contains("lodging") || text.contains("호텔") || text.contains("숙박") {
            return "bed.double"
        }
        if text.contains("bar") || text.contains("pub") || text.contains("nightlife") || text.contains("술집") {
            return "wineglass"
        }
        if text.contains("shop") || text.contains("store") || text.contains("쇼핑") {
            return "bag"
        }
        if text.contains("museum") || text.contains("gallery") || text.contains("박물관") || text.contains("미술관") {
            return "building.columns"
        }
        if text.contains("park") || text.contains("공원") {
            return "tree"
        }
        return "tag"
    }

    /// Same category buckets as `symbolName(for:)`, as an actual emoji
    /// character instead of an SF Symbol name — for the one spot that
    /// needs a real glyph rather than a system image: the Naver Map
    /// marker icon (`NaverMapWebView`/`naver-map-embed.html`), which is a
    /// plain HTML string, not a SwiftUI `Image`.
    static func emoji(for category: String?) -> String {
        guard let category, !category.isEmpty else { return "📍" }
        let text = category.lowercased()

        if isCafe(text) { return "☕" }
        if text.contains("restaurant") || text.contains("food") || text.contains("식당") || text.contains("음식") {
            return "🍴"
        }
        if text.contains("hotel") || text.contains("lodging") || text.contains("호텔") || text.contains("숙박") {
            return "🏨"
        }
        if text.contains("bar") || text.contains("pub") || text.contains("nightlife") || text.contains("술집") {
            return "🍷"
        }
        if text.contains("shop") || text.contains("store") || text.contains("쇼핑") {
            return "🛍️"
        }
        if text.contains("museum") || text.contains("gallery") || text.contains("박물관") || text.contains("미술관") {
            return "🖼️"
        }
        if text.contains("park") || text.contains("공원") {
            return "🌳"
        }
        return "📍"
    }

    /// Collapses every cafe/coffee-shop variant — Google's "Cafe"/"Coffee
    /// shop", or Korean "카페"/"커피숍"/"커피전문점" — into one canonical
    /// "카페" label, so they show and filter as a single category instead
    /// of several near-duplicates that happen to differ only in wording.
    /// Everything else passes through unchanged — there's no fixed
    /// taxonomy to normalize the rest into here.
    static func normalizedLabel(for category: String) -> String {
        isCafe(category.lowercased()) ? "카페" : category
    }
}
