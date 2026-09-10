import Foundation

/// A named collection of PlaceCards — created first, before any place card,
/// mirroring Peragra's "board" (its `Trip` model): give it a name and a
/// subtitle, then start adding place cards into it.
struct Board: Identifiable, Codable, Equatable {
    static let coverEmojiChoices = ["✈️", "🗺️", "🏖️", "🏙️", "⛰️", "🍜", "🎡", "🚆"]

    var id: String = UUID().uuidString
    var name: String
    var subtitle: String
    var coverEmoji: String
    var createdAt: Date = Date()
}
