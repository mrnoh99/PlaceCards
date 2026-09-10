import Foundation

struct Coordinates: Codable, Equatable, Hashable {
    var latitude: Double
    var longitude: Double
}

/// A single discovered place, unifying information gathered from map
/// screenshots, shared links, direct API lookups, and photos taken on site.
struct PlaceCard: Identifiable, Codable {
    var id: String = UUID().uuidString
    /// The `Board` this card belongs to — every card is created inside a
    /// board (see `BoardDetailView`), so this is never optional.
    var boardId: String

    var name: String
    var category: String?
    var address: String
    var coordinates: Coordinates?

    var rating: Double?
    var reviewCount: Int?

    var phone: String?
    var website: String?
    /// A separate field from `website` (mirrors Peragra's `Place`, which
    /// keeps `instagramURLString` distinct from its general `linkURLString`)
    /// so the cell can show a dedicated Instagram action alongside a plain
    /// website link.
    var instagramURL: String?

    /// Mirrors Peragra's `Place.favorite`/`Place.visited` — toggled
    /// directly from the card cell.
    var isFavorite: Bool = false
    var isVisited: Bool = false

    var hoursDetail: [String: String]?
    var closingTime: String?
    var holidays: String?

    var amenities: [String] = []
    var tags: [String] = []

    var media: MediaBundle = MediaBundle()
    var sources: [SourceRecord] = []
    var discoverySource: DiscoverySource?

    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

extension PlaceCard: Equatable {
    static func == (lhs: PlaceCard, rhs: PlaceCard) -> Bool {
        lhs.id == rhs.id
    }
}

extension PlaceCard: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension PlaceCard {
    /// Fills in anything only a duplicate had, folding its media and tags
    /// in too. The caller is expected to save `self` afterward and remove
    /// `duplicates` from storage via
    /// `StorageService.removeMergedDuplicate(_:)` — not `delete(_:)`,
    /// which would delete the photo files this just took ownership of.
    /// Ported from Peragra's `Place.merge(with:context:)`, adapted to
    /// PlaceCards' own fields (no free-text notes field to fold together
    /// here, but photos are combined since PlaceCards models those on the
    /// card itself, unlike Peragra's `Place`).
    mutating func merge(with duplicates: [PlaceCard]) {
        guard !duplicates.isEmpty else { return }

        if phone == nil { phone = duplicates.compactMap(\.phone).first }
        if website == nil { website = duplicates.compactMap(\.website).first }
        if instagramURL == nil { instagramURL = duplicates.compactMap(\.instagramURL).first }
        if category == nil { category = duplicates.compactMap(\.category).first }
        if rating == nil { rating = duplicates.compactMap(\.rating).first }
        if reviewCount == nil { reviewCount = duplicates.compactMap(\.reviewCount).first }

        if address.trimmingCharacters(in: .whitespaces).isEmpty {
            if let borrowed = duplicates.first(where: { !$0.address.trimmingCharacters(in: .whitespaces).isEmpty }) {
                address = borrowed.address
            }
        }

        if coordinates == nil, let donor = duplicates.first(where: { $0.coordinates != nil }) {
            coordinates = donor.coordinates
        }

        if duplicates.contains(where: \.isVisited) { isVisited = true }
        if duplicates.contains(where: \.isFavorite) { isFavorite = true }

        for duplicate in duplicates {
            for tag in duplicate.tags where !tags.contains(tag) {
                tags.append(tag)
            }
            for amenity in duplicate.amenities where !amenities.contains(amenity) {
                amenities.append(amenity)
            }
            media.mapScreenshots.append(contentsOf: duplicate.media.mapScreenshots)
            media.officialPhotos.append(contentsOf: duplicate.media.officialPhotos)
            media.onsitePhotos.append(contentsOf: duplicate.media.onsitePhotos)
            media.receivedPhotos.append(contentsOf: duplicate.media.receivedPhotos)
            sources.append(contentsOf: duplicate.sources)
        }
    }
}
