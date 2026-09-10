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

    /// Same category buckets as `symbolName(for:)`, as a small inline-SVG
    /// line icon (thin stroke, no fill — same outline look as the SF
    /// Symbols elsewhere in the app) inside a white circular badge, for
    /// the one spot that needs real markup rather than a system image:
    /// the Naver Map marker icon (`NaverMapWebView`/
    /// `naver-map-embed.html`). That page takes this string and
    /// concatenates it directly into the marker's HTML content — it was
    /// written for Peragra, where this field is a literal color emoji
    /// character (hence its name, kept as-is to match that page's
    /// payload shape), but nothing there actually requires it to *be* an
    /// emoji; any safe inline markup works the same way, and full-color
    /// emoji read poorly at marker scale against a busy map versus a
    /// flat, high-contrast outline glyph.
    static func markerGlyphHTML(for category: String?) -> String {
        guard let category, !category.isEmpty else { return badge(mapPinPath) }
        let text = category.lowercased()

        if isCafe(text) { return badge(coffeePath) }
        if text.contains("restaurant") || text.contains("food") || text.contains("식당") || text.contains("음식") {
            return badge(forkKnifePath)
        }
        if text.contains("hotel") || text.contains("lodging") || text.contains("호텔") || text.contains("숙박") {
            return badge(bedPath)
        }
        if text.contains("bar") || text.contains("pub") || text.contains("nightlife") || text.contains("술집") {
            return badge(wineGlassPath)
        }
        if text.contains("shop") || text.contains("store") || text.contains("쇼핑") {
            return badge(bagPath)
        }
        if text.contains("museum") || text.contains("gallery") || text.contains("박물관") || text.contains("미술관") {
            return badge(museumPath)
        }
        if text.contains("park") || text.contains("공원") {
            return badge(treePath)
        }
        return badge(mapPinPath)
    }

    /// Wraps one icon's inner SVG markup in a small white circular badge
    /// (for contrast against the map) and a shared stroke style, so every
    /// category glyph below only needs to specify its own shapes.
    private static func badge(_ innerSVG: String) -> String {
        """
        <div style="width:24px;height:24px;border-radius:50%;background:#ffffff;box-shadow:0 1px 3px rgba(0,0,0,0.35);display:flex;align-items:center;justify-content:center;box-sizing:border-box;">\
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="#1f2937" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">\(innerSVG)</svg>\
        </div>
        """
    }

    private static let mapPinPath = """
    <path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z"/><circle cx="12" cy="10" r="3"/>
    """

    private static let coffeePath = """
    <path d="M18 8h1a4 4 0 0 1 0 8h-1"/><path d="M2 8h16v9a4 4 0 0 1-4 4H6a4 4 0 0 1-4-4V8z"/><line x1="6" y1="1" x2="6" y2="4"/><line x1="10" y1="1" x2="10" y2="4"/><line x1="14" y1="1" x2="14" y2="4"/>
    """

    private static let forkKnifePath = """
    <line x1="4" y1="2" x2="4" y2="9"/><line x1="7" y1="2" x2="7" y2="9"/><line x1="10" y1="2" x2="10" y2="9"/><line x1="4" y1="9" x2="10" y2="9"/><line x1="7" y1="9" x2="7" y2="22"/><polygon points="16,2 20,2 18,10"/><line x1="18" y1="10" x2="18" y2="22"/>
    """

    private static let bedPath = """
    <rect x="2" y="14" width="20" height="7" rx="1"/><line x1="2" y1="14" x2="2" y2="21"/><line x1="22" y1="14" x2="22" y2="21"/><rect x="4" y="9" width="7" height="5" rx="1"/><line x1="2" y1="14" x2="22" y2="14"/>
    """

    private static let wineGlassPath = """
    <polygon points="7,2 17,2 12,12"/><line x1="12" y1="12" x2="12" y2="20"/><line x1="7" y1="20" x2="17" y2="20"/>
    """

    private static let bagPath = """
    <path d="M8 6a4 4 0 0 1 8 0"/><rect x="4" y="6" width="16" height="14" rx="2"/>
    """

    private static let museumPath = """
    <line x1="3" y1="21" x2="21" y2="21"/><line x1="5" y1="21" x2="5" y2="10"/><line x1="9" y1="21" x2="9" y2="10"/><line x1="13" y1="21" x2="13" y2="10"/><line x1="17" y1="21" x2="17" y2="10"/><polygon points="3,10 12,3 21,10"/>
    """

    private static let treePath = """
    <polygon points="12,2 18,12 6,12"/><polygon points="12,7 19,17 5,17"/><line x1="12" y1="17" x2="12" y2="22"/>
    """

    /// Collapses every cafe/coffee-shop variant — Google's "Cafe"/"Coffee
    /// shop", or Korean "카페"/"커피숍"/"커피전문점" — into one canonical
    /// "카페" label, so they show and filter as a single category instead
    /// of several near-duplicates that happen to differ only in wording.
    /// Everything else passes through unchanged — there's no fixed
    /// taxonomy to normalize the rest into here.
    static func normalizedLabel(for category: String) -> String {
        isCafe(category.lowercased()) ? "카페".localized : category
    }
}
