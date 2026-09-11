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

    /// Free-text catch-all for anything worth keeping that doesn't fit any
    /// field above — mirrors Peragra's `Place.notes`, which PlaceCards
    /// didn't have until now. Optional (not a `= ""` default), like every
    /// other field added to this struct after its original release —
    /// synthesized `Decodable` only defaults a missing key for Optional
    /// properties, so a non-optional addition here would fail to decode
    /// every already-saved card that predates this field.
    var memo: String?

    /// The `MediaItem.id` the user explicitly picked as this card's
    /// representative photo (detail view banner, grid/list thumbnail) —
    /// nil (the default, for every card saved before this field existed
    /// too) falls back to `officialPhotos.first ?? allItems.first`, same
    /// as before this existed. Cleared automatically if that photo is
    /// ever deleted (see `PlaceCardDetailView.deletePhoto`).
    var coverPhotoID: String?

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
    /// The card's representative photo — shown as the detail view's hero
    /// banner and every list/grid cell's thumbnail. The user's explicit
    /// `coverPhotoID` pick, if set and that photo is still attached;
    /// otherwise the first official Google photo, else just whatever
    /// photo comes first — the same fallback every one of those screens
    /// used before `coverPhotoID` existed.
    var coverPhoto: MediaItem? {
        if let coverPhotoID, let match = media.allItems.first(where: { $0.id == coverPhotoID }) {
            return match
        }
        return media.officialPhotos.first ?? media.allItems.first
    }
}

extension PlaceCard {
    /// Folds a newly scanned note (an AI photo-analysis "description" —
    /// a hashtag, a one-line impression, anything worth keeping that
    /// isn't the name/address themselves) into an existing memo, rather
    /// than overwriting it: appended as a new line, and skipped if
    /// already present so re-scanning the same photo doesn't keep piling
    /// up duplicates. Shared by every place this app turns an AI scan
    /// into a saved/updated card (`PlaceCardViewModel.createPlaceCard`,
    /// `EditPlaceCardSheet`, `MapScreenshotImportSheet`).
    static func combinedMemo(_ existing: String?, appending note: String?) -> String? {
        guard let note else { return existing }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNote.isEmpty else { return existing }

        let currentMemo = (existing ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if currentMemo.isEmpty { return trimmedNote }
        if currentMemo.contains(trimmedNote) { return currentMemo }
        return currentMemo + "\n" + trimmedNote
    }

    /// Whether this card matches a free-text search — checked against
    /// every field a user might plausibly search by (name, address,
    /// category, memo, tags, amenities, phone), not just name/address,
    /// word by word: the query is split on whitespace, and the card
    /// matches as soon as *any one* of those words turns up anywhere
    /// among those fields — so "강남 카페" finds a card named "OO카페"
    /// whose address is in 강남, even though neither field contains the
    /// full two-word phrase. Shared by every search box in the app
    /// (`HomeView`, `BoardDetailView`, `PlacesMapView`,
    /// `StorageService.search(query:tags:)`) so they all search the same
    /// way. An empty/whitespace-only query matches everything.
    func matchesSearch(_ query: String) -> Bool {
        let words = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !words.isEmpty else { return true }
        let searchableFields: [String?] = [
            name, address, category, memo, phone,
            tags.joined(separator: " "), amenities.joined(separator: " ")
        ]
        let haystack = searchableFields.compactMap { $0 }.joined(separator: " ")
        return words.contains { haystack.localizedCaseInsensitiveContains($0) }
    }

    /// Fills in anything only a duplicate had, folding its media and tags
    /// in too. The caller is expected to save `self` afterward and remove
    /// `duplicates` from storage via
    /// `StorageService.removeMergedDuplicate(_:)` — not `delete(_:)`,
    /// which would delete the photo files this just took ownership of.
    /// Ported from Peragra's `Place.merge(with:context:)`, adapted to
    /// PlaceCards' own fields (photos are combined since PlaceCards models
    /// those on the card itself, unlike Peragra's `Place`).
    mutating func merge(with duplicates: [PlaceCard]) {
        guard !duplicates.isEmpty else { return }

        if phone == nil { phone = duplicates.compactMap(\.phone).first }
        if website == nil { website = duplicates.compactMap(\.website).first }
        if instagramURL == nil { instagramURL = duplicates.compactMap(\.instagramURL).first }
        if category == nil { category = duplicates.compactMap(\.category).first }
        if rating == nil { rating = duplicates.compactMap(\.rating).first }
        if reviewCount == nil { reviewCount = duplicates.compactMap(\.reviewCount).first }
        if memo?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            memo = duplicates.compactMap(\.memo).first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }

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
