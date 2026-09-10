import Foundation
import CoreLocation

/// Finds place cards in the same board that look like the same real-world
/// spot saved more than once. Ported from Peragra's `DuplicatePlaces`.
enum DuplicatePlaces {
    /// Lowercases and strips everything but letters/digits, so "Blue Bottle
    /// Coffee", "blue-bottle coffee!", and "BlueBottleCoffee" all compare
    /// equal — the differences that actually show up between the same
    /// place typed twice (spacing, punctuation, case) rather than real
    /// distinctions.
    private static func normalize(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    /// Cards within this distance of each other, with matching names, are
    /// treated as the same real-world place — loose enough to cover a
    /// geocoder snapping to a slightly different point on the same
    /// building or block, tight enough that two different branches of the
    /// same chain don't get merged.
    private static let duplicateDistanceMeters: CLLocationDistance = 150

    /// Whether two cards look like the same real-world place saved twice:
    /// their names must match (after normalizing away case/spacing/
    /// punctuation), AND either their coordinates are close together,
    /// their addresses match/overlap, or — only when neither card has any
    /// coordinate or address to compare — the name match stands on its
    /// own, since there's nothing else available to check.
    static func likelyDuplicate(_ a: PlaceCard, _ b: PlaceCard) -> Bool {
        let trimmedA = a.name.trimmingCharacters(in: .whitespaces)
        let trimmedB = b.name.trimmingCharacters(in: .whitespaces)
        guard !trimmedA.isEmpty, !trimmedB.isEmpty else { return false }
        guard normalize(a.name) == normalize(b.name) else { return false }

        if let coordinatesA = a.coordinates, let coordinatesB = b.coordinates {
            let locationA = CLLocation(latitude: coordinatesA.latitude, longitude: coordinatesA.longitude)
            let locationB = CLLocation(latitude: coordinatesB.latitude, longitude: coordinatesB.longitude)
            return locationA.distance(from: locationB) <= duplicateDistanceMeters
        }

        let addressA = normalize(a.address)
        let addressB = normalize(b.address)
        if !addressA.isEmpty, !addressB.isEmpty {
            return addressA == addressB || addressA.contains(addressB) || addressB.contains(addressA)
        }

        // Neither has a coordinate, and at least one has no address
        // either — nothing left to compare but the name, which already
        // matched.
        return true
    }

    /// Groups a board's cards into duplicate clusters — union-find over
    /// `likelyDuplicate` so A-matches-B and B-matches-C still group all
    /// three together even if A and C weren't compared as a close enough
    /// pair directly. Only groups of 2+ are returned; cards with no
    /// duplicate are simply omitted rather than returned as singleton
    /// groups.
    static func findDuplicateGroups(_ cards: [PlaceCard]) -> [[PlaceCard]] {
        var parent: [String: String] = [:]

        func find(_ id: String) -> String {
            var root = id
            while let next = parent[root], next != root {
                root = next
            }
            parent[id] = root
            return root
        }

        func union(_ a: String, _ b: String) {
            let rootA = find(a)
            let rootB = find(b)
            if rootA != rootB { parent[rootA] = rootB }
        }

        for card in cards { parent[card.id] = card.id }

        for i in 0..<cards.count {
            for j in (i + 1)..<cards.count where j > i {
                if likelyDuplicate(cards[i], cards[j]) {
                    union(cards[i].id, cards[j].id)
                }
            }
        }

        var groups: [String: [PlaceCard]] = [:]
        for card in cards {
            groups[find(card.id), default: []].append(card)
        }

        return groups.values.filter { $0.count > 1 }
    }
}
