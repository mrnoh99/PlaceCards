import Foundation
import CoreLocation

/// Mirrors Peragra's `PlaceSortMode` ("By Category" / "Name" / "Distance").
enum PlaceSortMode: String, CaseIterable, Identifiable {
    case byCategory = "카테고리별"
    case name = "이름"
    case distance = "거리"

    var id: String { rawValue }
}

extension Array where Element == PlaceCard {
    /// Sorts by the given mode, with favorited cards always floated to the
    /// top no matter which mode is active — the mode only decides ordering
    /// within/below that. Mirrors Peragra's `TripDetailView.sortedPlaces`.
    /// `reference` is a plain coordinate (not a `PlaceCard`) so distance
    /// mode can sort from the device's current location ("현재 위치") just
    /// as well as from another saved card.
    func sorted(by mode: PlaceSortMode, distanceFrom reference: Coordinates?) -> [PlaceCard] {
        guard contains(where: \.isFavorite) else {
            return sortedWithinGroup(by: mode, distanceFrom: reference)
        }
        let favorites = filter(\.isFavorite)
        let rest = filter { !$0.isFavorite }
        return favorites.sortedWithinGroup(by: mode, distanceFrom: reference)
            + rest.sortedWithinGroup(by: mode, distanceFrom: reference)
    }

    private func sortedWithinGroup(by mode: PlaceSortMode, distanceFrom reference: Coordinates?) -> [PlaceCard] {
        switch mode {
        case .byCategory:
            // No fixed category taxonomy here (unlike Peragra's
            // PlaceCategory enum) — Google Places' category text is
            // grouped alphabetically instead, then by name within a group.
            return sorted { a, b in
                let categoryA = a.category ?? ""
                let categoryB = b.category ?? ""
                if categoryA != categoryB {
                    return categoryA.localizedCaseInsensitiveCompare(categoryB) == .orderedAscending
                }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        case .name:
            return sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .distance:
            guard let reference else { return self }
            let refLocation = CLLocation(latitude: reference.latitude, longitude: reference.longitude)
            return sorted {
                distance(from: refLocation, to: $0.coordinates) < distance(from: refLocation, to: $1.coordinates)
            }
        }
    }

    private func distance(from reference: CLLocation, to coordinates: Coordinates?) -> Double {
        guard let coordinates else { return .greatestFiniteMagnitude }
        return reference.distance(from: CLLocation(latitude: coordinates.latitude, longitude: coordinates.longitude))
    }
}
