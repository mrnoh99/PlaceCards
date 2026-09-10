import Foundation
import CoreLocation

/// Mirrors Peragra's `PlaceSortMode` ("By Category" / "Name" / "Distance").
enum PlaceSortMode: String, CaseIterable, Identifiable {
    case byCategory = "카테고리별"
    case name = "이름"
    case distance = "거리"

    var id: String { rawValue }

    /// `rawValue` itself must stay a fixed Korean literal (enum raw values
    /// have to be compile-time constants, and this one's also read back
    /// via `Picker`/`@AppStorage`-style persistence elsewhere) — this is
    /// the one to actually show in UI.
    var displayName: String { rawValue.localized }
}

extension Array where Element == PlaceCard {
    /// Sorts purely by the given mode — favorite status has no effect on
    /// ordering (a favorited card sorts exactly where its
    /// category/name/distance would otherwise place it). `reference` is a
    /// plain coordinate (not a `PlaceCard`) so distance mode can sort from
    /// the device's current location ("현재 위치") just as well as from
    /// another saved card.
    ///
    /// `pinnedID`, when distance-sorting from another saved card (never
    /// set for "현재 위치"), is that reference card's own id — it's pinned
    /// to the very first position, since it's the point everything else
    /// is being measured from rather than an ordinary list entry;
    /// everything else keeps the usual sort order.
    func sorted(by mode: PlaceSortMode, distanceFrom reference: Coordinates?, pinnedID: String? = nil) -> [PlaceCard] {
        guard mode == .distance, let pinnedID, let pinnedIndex = firstIndex(where: { $0.id == pinnedID }) else {
            return sortedWithinGroup(by: mode, distanceFrom: reference)
        }
        var rest = self
        let pinned = rest.remove(at: pinnedIndex)
        return [pinned] + rest.sortedWithinGroup(by: mode, distanceFrom: reference)
    }

    private func sortedWithinGroup(by mode: PlaceSortMode, distanceFrom reference: Coordinates?) -> [PlaceCard] {
        switch mode {
        case .byCategory:
            // No fixed category taxonomy here (unlike Peragra's
            // PlaceCategory enum) — Google Places' category text is
            // grouped alphabetically instead, then by name within a group.
            return sorted { isByCategoryAscending($0, $1) }
        case .name:
            return sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .distance:
            guard let reference else { return self }
            let refLocation = CLLocation(latitude: reference.latitude, longitude: reference.longitude)
            // Ties (same distance — most commonly several cards with no
            // coordinate at all, which all fall back to the same
            // greatestFiniteMagnitude placeholder) fall back to the same
            // category/name order "카테고리별" uses, rather than being left
            // in whatever arbitrary order they happened to start in.
            return sorted { a, b in
                let distanceA = distance(from: refLocation, to: a.coordinates)
                let distanceB = distance(from: refLocation, to: b.coordinates)
                if distanceA != distanceB {
                    return distanceA < distanceB
                }
                return isByCategoryAscending(a, b)
            }
        }
    }

    private func isByCategoryAscending(_ a: PlaceCard, _ b: PlaceCard) -> Bool {
        let categoryA = normalizedCategory(a)
        let categoryB = normalizedCategory(b)
        if categoryA != categoryB {
            return categoryA.localizedCaseInsensitiveCompare(categoryB) == .orderedAscending
        }
        return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }

    /// Cafe/coffee-shop variants ("Cafe", "Coffee shop", "카페", "커피숍",
    /// "커피전문점", ...) group together under one "카페" bucket here too,
    /// same as the category filter dropdown — otherwise "카테고리별" sort
    /// would split them into separate alphabetical groups despite meaning
    /// the same thing.
    private func normalizedCategory(_ card: PlaceCard) -> String {
        guard let category = card.category, !category.isEmpty else { return "" }
        return PlaceCategoryIcon.normalizedLabel(for: category)
    }

    private func distance(from reference: CLLocation, to coordinates: Coordinates?) -> Double {
        guard let coordinates else { return .greatestFiniteMagnitude }
        return reference.distance(from: CLLocation(latitude: coordinates.latitude, longitude: coordinates.longitude))
    }
}

extension Coordinates {
    /// A short "250m"/"1.3km" label for the distance from `reference` to
    /// `coordinates`, shown next to a card once the list is sorted by
    /// distance — mirrors Peragra's `PlaceRowView.formattedDistance`
    /// ("N km away"). nil whenever either coordinate is missing (not
    /// currently distance-sorting, or this specific card has no
    /// coordinate yet), so callers can just hide the label.
    static func distanceText(from reference: Coordinates?, to coordinates: Coordinates?) -> String? {
        guard let reference, let coordinates else { return nil }
        let refLocation = CLLocation(latitude: reference.latitude, longitude: reference.longitude)
        let pointLocation = CLLocation(latitude: coordinates.latitude, longitude: coordinates.longitude)
        let meters = refLocation.distance(from: pointLocation)
        return meters < 1000 ? "\(Int(meters.rounded()))m" : String(format: "%.1fkm", meters / 1000)
    }
}
