import Foundation

/// A record of one occasion a PlaceCard's data was populated or verified.
struct SourceRecord: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var sourceType: SourceType
    var timestamp: Date = Date()
    var dataProvided: [String] = []
    var confidence: Double?
    var notes: String?
}

/// How a place was first discovered on social media, before it was
/// verified against a map API.
struct DiscoverySource: Codable, Equatable {
    var platform: String
    var screenshotPath: String?
    var extractedCaptionText: String?
    var originalPostUrl: String?
    var extractionConfidence: Double?
    var discoveredAt: Date = Date()
}
