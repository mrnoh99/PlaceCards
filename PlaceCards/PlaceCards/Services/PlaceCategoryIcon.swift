import Foundation

/// Best-effort outline SF Symbol for a free-text Google Places category
/// string — there's no fixed taxonomy to switch over here (unlike
/// Peragra's `PlaceCategory` enum), so this keyword-matches instead,
/// falling back to a generic tag icon. Every symbol below is the plain
/// (outline) variant, never a ".fill" one, to match the app's minimalist
/// outline look.
enum PlaceCategoryIcon {
    static func symbolName(for category: String?) -> String {
        guard let category, !category.isEmpty else { return "tag" }
        let text = category.lowercased()

        if text.contains("cafe") || text.contains("coffee") || text.contains("카페") {
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
}
