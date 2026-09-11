import Foundation

struct Coordinates: Codable, Equatable, Hashable {
    var latitude: Double
    var longitude: Double
}

/// Mirrors Google Places API (New)'s own `priceLevel` enum exactly (raw
/// values are its actual JSON string values, confirmed against the live
/// REST reference — https://developers.google.com/maps/documentation/places/web-service/reference/rest/v1/places#pricelevel)
/// so a search result's `priceLevel` decodes straight into this with no
/// translation layer. `PRICE_LEVEL_UNSPECIFIED` has no case here — an
/// unspecified/unknown price level and a place Google never returned a
/// price level for both mean the same "don't know" to this app, so both
/// just decode to `nil` rather than a distinct "unspecified" case.
enum PriceLevel: String, Codable, CaseIterable {
    case free = "PRICE_LEVEL_FREE"
    case inexpensive = "PRICE_LEVEL_INEXPENSIVE"
    case moderate = "PRICE_LEVEL_MODERATE"
    case expensive = "PRICE_LEVEL_EXPENSIVE"
    case veryExpensive = "PRICE_LEVEL_VERY_EXPENSIVE"

    /// A short "₩"-style symbol — mirrors how Google/Naver Maps' own UI
    /// shows price level, familiar at a glance without reading a label.
    var symbol: String {
        switch self {
        case .free: return "무료".localized
        case .inexpensive: return "₩"
        case .moderate: return "₩₩"
        case .expensive: return "₩₩₩"
        case .veryExpensive: return "₩₩₩₩"
        }
    }
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
    /// The user's own rating, separate from `rating` (Google/Naver's
    /// public aggregate) — this app has no review-writing feature, just a
    /// personal 1–5 note of how the user themself felt about the place.
    var myRating: Double?
    /// From Google Places' own `priceLevel` — `nil` for a card that either
    /// has no verified Google match at all, or one Google itself never
    /// returned a price level for (a Naver-verified card never gets this,
    /// since Naver's local search API has no equivalent field).
    var priceLevel: PriceLevel?

    var phone: String?
    var website: String?
    /// A separate field from `website` (mirrors Peragra's `Place`, which
    /// keeps `instagramURLString` distinct from its general `linkURLString`)
    /// so the cell can show a dedicated Instagram action alongside a plain
    /// website link.
    var instagramURL: String?
    /// Other pages worth a quick link out to — the exact Google/Naver Map
    /// listing this card was verified against (captured from a share's own
    /// URL rather than reconstructed from name/coordinates, so it's exact
    /// rather than a best-effort search link), or a review/booking
    /// platform's own page (TripAdvisor, Yelp, OpenTable, ...) added by
    /// hand. Keyed by a short platform label (e.g. "Google Maps", "Naver
    /// Map", "TripAdvisor") rather than one named field per platform,
    /// since there's no fixed, closed set of these worth hardcoding —
    /// `website`/`instagramURL` stay their own dedicated fields since
    /// every card routinely has those specific two and the UI treats them
    /// distinctly (a dedicated icon/action each).
    var externalLinks: [String: String] = [:]

    /// Mirrors Peragra's `Place.favorite`/`Place.visited` — toggled
    /// directly from the card cell.
    var isFavorite: Bool = false
    var isVisited: Bool = false
    /// Every date the user actually logged a visit on, most useful for
    /// "언제 갔었지?"/"몇 번 갔지?" beyond the plain visited/not-visited
    /// flag `isVisited` already gives — independent of that flag by
    /// design (toggling `isVisited` doesn't touch this, and this doesn't
    /// imply `isVisited`), so a card can track detailed visit history
    /// without forcing every user through it just to mark "visited".
    var visitDates: [Date] = []
    /// Whether the user would go back — a separate question from
    /// `isFavorite` (liking a place) and `isVisited` (having been), and
    /// genuinely three-valued: `nil` for "haven't decided/doesn't apply"
    /// (every card before this existed, and most new ones until the user
    /// actively answers it), as opposed to `false` meaning they actively
    /// decided not to.
    var wouldRevisit: Bool?

    var hoursDetail: [String: String]?
    var closingTime: String?
    var holidays: String?

    /// Free text naming how to reserve a table here (e.g. "캐치테이블 예약",
    /// "테이블링 예약", "전화 예약만 가능") — set by hand, or filled in by
    /// an AI photo scan/web search the same way phone/hours are. No
    /// dedicated field for a specific platform's own booking link, since
    /// this app has no verified deep-link/search-URL format for any one
    /// Korean reservation platform (see `PlaceCard.reservationSearchURL`'s
    /// own comment); instead this text becomes the query for a general web
    /// search that reliably lands the user on results for it regardless of
    /// which platform it names.
    var reservationInfo: String?
    /// Free text for what to actually order here, e.g. "시그니처 라떼,
    /// 크로플" — filled by hand, or by an AI photo scan/web search the
    /// same way phone/hours are.
    var recommendedMenu: String?

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
            name, address, category, memo, phone, recommendedMenu,
            tags.joined(separator: " "), amenities.joined(separator: " ")
        ]
        let haystack = searchableFields.compactMap { $0 }.joined(separator: " ")
        return words.contains { haystack.localizedCaseInsensitiveContains($0) }
    }

    /// Strips invisible Unicode "format" characters (see
    /// `String.strippingInvisibleFormatCharacters()`) from every
    /// human-readable text field. Run on every card as it's loaded from
    /// disk (`StorageService.loadPlaceCards()`) rather than only where a
    /// field first enters the app — a card saved before that stripping
    /// existed, or through a source path that missed it (Google/Naver's
    /// own `category` text did, until this fix), would otherwise carry
    /// those invisible characters — and the display glitch they cause —
    /// forever, since nothing else ever re-touches an already-saved card's
    /// text.
    func strippingInvisibleFormatCharacters() -> PlaceCard {
        var card = self
        card.name = name.strippingInvisibleFormatCharacters()
        card.address = address.strippingInvisibleFormatCharacters()
        card.category = category?.strippingInvisibleFormatCharacters()
        card.memo = memo?.strippingInvisibleFormatCharacters()
        card.closingTime = closingTime?.strippingInvisibleFormatCharacters()
        card.holidays = holidays?.strippingInvisibleFormatCharacters()
        card.reservationInfo = reservationInfo?.strippingInvisibleFormatCharacters()
        card.recommendedMenu = recommendedMenu?.strippingInvisibleFormatCharacters()
        card.tags = tags.map { $0.strippingInvisibleFormatCharacters() }
        card.amenities = amenities.map { $0.strippingInvisibleFormatCharacters() }
        card.externalLinks = Dictionary(
            uniqueKeysWithValues: externalLinks.map {
                ($0.key.strippingInvisibleFormatCharacters(), $0.value.strippingInvisibleFormatCharacters())
            }
        )
        if let hoursDetail {
            card.hoursDetail = Dictionary(
                uniqueKeysWithValues: hoursDetail.map {
                    ($0.key.strippingInvisibleFormatCharacters(), $0.value.strippingInvisibleFormatCharacters())
                }
            )
        }
        return card
    }

    /// Fills only whatever's still blank on this card from a scanned
    /// photo's or web search's extra details (`PlaceWebDetails` —
    /// `EditPlaceCardSheet`'s "AI로 정보 읽어오기"/"웹 검색으로 채우기",
    /// `MapScreenshotImportSheet`'s own photo import, and
    /// `PlaceCardViewModel.createCards()` for a brand-new card all share
    /// this) — never overwrites a value already set from elsewhere.
    ///
    /// `details.tags` is deliberately never touched here — unlike every
    /// other field on `PlaceWebDetails`, AI-suggested tags aren't applied
    /// silently anywhere in this app (see that field's own doc comment):
    /// they're closer to the user's own personal categorization than an
    /// objective fact worth auto-filling, so a wrong guess landing here
    /// with no review step would be worse than just not offering them.
    /// Every call site stages and confirms them separately instead.
    mutating func applyScannedDetails(_ details: PlaceWebDetails?) {
        guard let details else { return }
        if phone == nil, let value = details.phone, !value.isEmpty { phone = value }
        if website == nil, let value = details.website, !value.isEmpty { website = value }
        if category == nil, let value = details.category, !value.isEmpty { category = value }
        if hoursDetail?.isEmpty ?? true, let value = details.hoursDetail, !value.isEmpty { hoursDetail = value }
        if closingTime == nil, let value = details.closingTime, !value.isEmpty { closingTime = value }
        if holidays == nil, let value = details.holidays, !value.isEmpty { holidays = value }
        if amenities.isEmpty, !details.amenities.isEmpty { amenities = details.amenities }
        if reservationInfo == nil, let value = details.reservationInfo, !value.isEmpty { reservationInfo = value }
        if recommendedMenu == nil, let value = details.recommendedMenu, !value.isEmpty { recommendedMenu = value }
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
