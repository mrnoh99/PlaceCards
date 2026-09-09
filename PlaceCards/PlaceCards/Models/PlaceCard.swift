import Foundation

struct PlaceCard: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var guestName: String
    var tableName: String = ""
    var note: String = ""
}
