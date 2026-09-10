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
