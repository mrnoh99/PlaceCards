import Foundation

/// A named collection of PlaceCards — created first, before any place card,
/// mirroring Peragra's "board" (its `Trip` model): give it a name and a
/// subtitle, then start adding place cards into it.
struct Board: Identifiable, Codable, Equatable {
    /// Outline SF Symbols only, matching the app's minimalist outline
    /// look (the app icon and category icons) — no ".fill" variants.
    static let coverIconChoices = [
        "airplane", "map", "beach.umbrella", "building.2",
        "mountain.2", "fork.knife", "camera", "tram",
    ]

    var id: String = UUID().uuidString
    var name: String
    var subtitle: String
    var coverIcon: String
    var createdAt: Date = Date()
}
