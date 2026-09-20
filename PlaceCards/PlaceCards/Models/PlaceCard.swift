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

/// One entry in `PlaceCard.externalLinks` — a platform name and its URL
/// (e.g. "Google Maps" → the exact share link, "Trip Advisor" → a listing
/// page). An array rather than a `[String: String]` dictionary so more
/// than one link can be kept for the same platform (two branches both
/// worth linking as "Instagram", say) without the second silently
/// overwriting the first, and so the order the user added them in is
/// preserved instead of a dictionary's undefined iteration order.
struct ExternalLink: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var platform: String
    var url: String
}

/// A single discovered place, unifying information gathered from map
/// screenshots, shared links, direct API lookups, and photos taken on site.
struct PlaceCard: Identifiable, Codable {
    var id: String = UUID().uuidString
    /// 카드가 보드 하나에만 속하던 시절의 필드. 지우지 않는다 — 저장된
    /// 카드가 전부 디코딩에 실패한다(CLAUDE.md §4). 지금은 `boardIDs`의
    /// 첫 칸과 발을 맞추며, 그 덕에 여기서 쓴 백업을 예전 빌드에서 열어도
    /// 카드가 제 보드에 들어간다.
    var boardId: String

    /// 이 카드가 들어 있는 보드 전부. 예전에 저장된 카드에는 이 필드가
    /// 아예 없어서 nil로 디코딩되고, 그때는 `boardIDs`가 `boardId` 하나로
    /// 답한다 — 따로 이관 작업을 돌릴 필요가 없다.
    ///
    /// 빈 배열은 nil과 다르다. 어느 보드에도 안 들어 있다는 뜻이고,
    /// 그런 카드도 "모든 카드"에서는 보인다.
    var boardIds: [String]?

    /// 살아 있으면 nil. 값이 있으면 삭제됨으로 옮겨진 시각이다.
    ///
    /// 옮길 때 보드 목록을 비우지 않는다. 화면들이 이 값만 보고 걸러내므로
    /// 카드는 모든 보드와 "모든 카드"에서 사라지고, 되돌리기는 이 값을
    /// nil로 되돌리기만 하면 카드가 있던 자리로 그대로 돌아온다.
    var deletedAt: Date?

    /// 이 카드가 들어 있는 보드들. 읽을 때는 `boardIds`가 nil인 예전
    /// 카드를 `boardId` 하나로 메워 주고, 쓸 때는 `boardId`를 첫 칸에
    /// 맞춰 둔다. 화면과 서비스는 `boardId`가 아니라 전부 이쪽을 쓴다.
    ///
    /// 계산 프로퍼티라 저장되지 않는다 — 디스크에 남는 것은 위의
    /// `boardId`와 `boardIds` 둘뿐이다.
    var boardIDs: [String] {
        get { boardIds ?? [boardId] }
        set {
            boardIds = newValue
            // 빈 배열이면 `boardId`는 마지막 값을 그대로 들고 있는다.
            // 어차피 `boardIDs`가 답을 정하므로 해롭지 않고, 예전 빌드가
            // 이 백업을 열었을 때 카드가 사라지지 않는 쪽이 낫다.
            if let first = newValue.first { boardId = first }
        }
    }

    var isDeleted: Bool { deletedAt != nil }

    var name: String
    var category: String?
    var address: String
    var coordinates: Coordinates?
    /// This place's Google Places `placeId`, set when the card was created
    /// from (or later confirmed against, via `EditPlaceCardSheet`'s "장소
    /// 확정" section) a verified Google Places search result
    /// (`PlaceSearchResult.isFromGooglePlaces`) — `nil` for a
    /// Naver-verified-only or manually-entered card. Lets
    /// `EditPlaceCardSheet` re-fetch this place's own
    /// `GooglePlacesService.details(placeId:)` (hours, rating, phone,
    /// website) straight from Google with no AI involved at all — the
    /// one non-AI way to refresh a card's info after creation.
    var googlePlaceId: String?
    /// Whether this card was matched against a verified Naver local-search
    /// result (`PlaceSearchResult` with `isFromGooglePlaces == false`) —
    /// at creation, or later via `EditPlaceCardSheet`'s "장소 확정"
    /// section falling back to Naver. Naver's local search API has no
    /// stable place ID worth keeping (unlike `googlePlaceId`, there's
    /// nothing to re-fetch details from later), so this is just a flag,
    /// not an ID — used alongside `googlePlaceId` to decide whether a
    /// card counts as "장소확정" (the green badge on the detail view,
    /// list row, and grid cell): either source confirming it is enough.
    /// Optional (not a `= false` default), same reason `memo`'s own doc
    /// comment gives — a field added after this struct's original release
    /// has to be `Optional` for synthesized `Decodable` to default a
    /// missing key on an already-saved card; a non-optional `= false`
    /// default is only honored for a key present at the struct's original
    /// release, not one added later.
    var naverVerified: Bool?

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
    /// hand — any number of these, including more than one for the same
    /// platform. Labeled by a short platform name (e.g. "Google Maps",
    /// "Naver Map", "TripAdvisor") per entry rather than one named field
    /// per platform, since there's no fixed, closed set of these worth
    /// hardcoding — `website`/`instagramURL` stay their own dedicated
    /// fields since every card routinely has those specific two and the UI
    /// treats them distinctly (a dedicated icon/action each).
    var externalLinks: [ExternalLink] = []

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
    /// The machine-readable form of `hoursDetail`, when it came from
    /// Google — what makes "지금 영업 중" answerable. Optional, like every
    /// field added after this struct's first release (see `memo`), so
    /// already-saved cards keep decoding. Deliberately cleared whenever
    /// the user edits the hours text by hand (`EditPlaceCardSheet.save()`):
    /// once the two can disagree, the text is what the user believes, and
    /// showing a badge computed from stale Google data next to their own
    /// corrected hours would be worse than showing no badge at all.
    var openingPeriods: [OpeningPeriod]?
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
    /// Third-party recognition — Michelin stars/Bib Gourmand, TripAdvisor
    /// "Travelers' Choice", 블루리본서베이, and the like (e.g. "미쉐린
    /// 1스타", "TripAdvisor Travelers' Choice 2026"). Deliberately
    /// separate from `tags`: a tag is the user's own personal
    /// categorization, an award is a specific third party's own
    /// recognition — conflating the two would lose which is which.
    var awards: [String] = []
    /// How long a visit here is expected to take, e.g. "1~2시간" —
    /// mainly meaningful for attractions/museums (TripAdvisor and
    /// similar sites routinely show this), not really for restaurants.
    var suggestedDuration: String?
    /// Entry ticket pricing, e.g. "성인 15,000원 / 청소년 10,000원" — free
    /// text since fee structures vary too much for a single number.
    /// Distinct from `priceLevel` (a restaurant's rough $-tier), which
    /// says nothing about an admission fee.
    var admissionFee: String?
    /// Dietary accommodations, e.g. "비건 옵션", "글루텐프리", "할랄" —
    /// kept separate from `amenities` (parking, pet-friendly, takeout,
    /// ...) since these two answer different questions ("can I eat
    /// here at all" vs. "what's convenient about this place"), even
    /// though both are free-text lists filled the same way.
    var dietaryOptions: [String] = []

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
    /// "장소확정" — whether this place has actually been matched against a
    /// real map listing, on Google or Naver, rather than sitting as a
    /// manually-entered or AI-guessed name/address. Drives the green
    /// badge shown on the detail view, list row, and grid cell.
    var isPlaceConfirmed: Bool {
        googlePlaceId != nil || (naverVerified ?? false)
    }

    /// The card's representative photo — shown as the detail view's hero
    /// banner and every list/grid cell's thumbnail. The user's explicit
    /// `coverPhotoID` pick, if set and that photo is still attached;
    /// otherwise a photo they actually contributed, then Google's, then
    /// whatever comes first.
    ///
    /// The fallback used to reach for `officialPhotos.first` before
    /// anything else, which was harmless while a Google photo was only
    /// ever fetched for a card that had none of its own. Now that both
    /// are fetched, that order would quietly replace the photo the user
    /// took with a stock one from Google the moment a refresh ran —
    /// the opposite of what adding their own photo means. They can still
    /// pick Google's explicitly; it just isn't chosen for them.
    var coverPhoto: MediaItem? {
        if let coverPhotoID, let match = media.allItems.first(where: { $0.id == coverPhotoID }) {
            return match
        }
        return media.onsitePhotos.first
            ?? media.receivedPhotos.first
            ?? media.officialPhotos.first
            ?? media.allItems.first
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
            name, address, category, memo, phone, recommendedMenu, suggestedDuration, admissionFee,
            tags.joined(separator: " "), amenities.joined(separator: " "),
            awards.joined(separator: " "), dietaryOptions.joined(separator: " ")
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
        card.suggestedDuration = suggestedDuration?.strippingInvisibleFormatCharacters()
        card.admissionFee = admissionFee?.strippingInvisibleFormatCharacters()
        card.tags = tags.map { $0.strippingInvisibleFormatCharacters() }
        card.amenities = amenities.map { $0.strippingInvisibleFormatCharacters() }
        card.awards = awards.map { $0.strippingInvisibleFormatCharacters() }
        card.dietaryOptions = dietaryOptions.map { $0.strippingInvisibleFormatCharacters() }
        card.externalLinks = externalLinks.map {
            ExternalLink(
                id: $0.id,
                platform: $0.platform.strippingInvisibleFormatCharacters(),
                url: $0.url.strippingInvisibleFormatCharacters()
            )
        }
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
    /// photo's extra details (`PlaceWebDetails` — `EditPlaceCardSheet`'s
    /// "AI로 정보 읽어오기", `MapScreenshotImportSheet`'s own photo import,
    /// and `PlaceCardViewModel.createCards()` for a brand-new card all
    /// share this) — never overwrites a value already set from elsewhere.
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
        // No `openingPeriods` counterpart here on purpose: an AI scan reads
        // hours off a screenshot as free text, with nothing structured
        // behind it to judge "지금 영업 중" from.
        if hoursDetail?.isEmpty ?? true, let value = details.hoursDetail, !value.isEmpty { hoursDetail = value }
        if closingTime == nil, let value = details.closingTime, !value.isEmpty { closingTime = value }
        if holidays == nil, let value = details.holidays, !value.isEmpty { holidays = value }
        if amenities.isEmpty, !details.amenities.isEmpty { amenities = details.amenities }
        if reservationInfo == nil, let value = details.reservationInfo, !value.isEmpty { reservationInfo = value }
        if recommendedMenu == nil, let value = details.recommendedMenu, !value.isEmpty { recommendedMenu = value }
        if suggestedDuration == nil, let value = details.suggestedDuration, !value.isEmpty { suggestedDuration = value }
        if admissionFee == nil, let value = details.admissionFee, !value.isEmpty { admissionFee = value }
        // Unlike `tags` above, `awards`/`dietaryOptions` are objective
        // third-party facts (Michelin either gave a star or didn't; a
        // menu either has a vegan option or doesn't) rather than
        // personal categorization, so — same as `amenities` — these
        // apply directly instead of staging for confirmation.
        if awards.isEmpty, !details.awards.isEmpty { awards = details.awards }
        if dietaryOptions.isEmpty, !details.dietaryOptions.isEmpty { dietaryOptions = details.dietaryOptions }
    }

    /// Fills in anything only a duplicate had, folding its media and tags
    /// in too. The caller is expected to save `self` afterward and remove
    /// `duplicates` from storage via
    /// `StorageService.removeMergedDuplicate(_:)` — not `delete(_:)`,
    /// which would delete the photo files this just took ownership of.
    /// Ported from Peragra's `Place.merge(with:context:)`, adapted to
    /// PlaceCards' own fields (photos are combined since PlaceCards models
    /// those on the card itself, unlike Peragra's `Place`).
    /// Every field a duplicate might be the only holder of is covered here
    /// — deliberately, and it needs to stay that way as fields are added.
    /// A merge is irreversible (`FindDuplicatesSheet` removes the
    /// duplicates immediately afterward) and the user is told their
    /// information is being moved onto the surviving card, so any field
    /// left out is silent, permanent loss of something they had. This
    /// previously covered only about a third of the struct, dropping —
    /// among others — `googlePlaceId`/`naverVerified` (so merging a
    /// confirmed card into an unconfirmed one *unconfirmed* the place) and
    /// `externalLinks` (which `FindDuplicatesSheet`'s own on-screen text
    /// explicitly promises to move).
    mutating func merge(with duplicates: [PlaceCard]) {
        guard !duplicates.isEmpty else { return }

        // Whether the *surviving* card brought any photo of its own, read
        // before the merge loop below appends the duplicates' — decides
        // whether a duplicate's explicit cover-photo pick is worth
        // adopting further down.
        let hadOwnMedia = !media.allItems.isEmpty

        if phone == nil { phone = duplicates.compactMap(\.phone).first }
        if website == nil { website = duplicates.compactMap(\.website).first }
        if instagramURL == nil { instagramURL = duplicates.compactMap(\.instagramURL).first }
        if category == nil { category = duplicates.compactMap(\.category).first }
        if rating == nil { rating = duplicates.compactMap(\.rating).first }
        if reviewCount == nil { reviewCount = duplicates.compactMap(\.reviewCount).first }
        if myRating == nil { myRating = duplicates.compactMap(\.myRating).first }
        if priceLevel == nil { priceLevel = duplicates.compactMap(\.priceLevel).first }
        if wouldRevisit == nil { wouldRevisit = duplicates.compactMap(\.wouldRevisit).first }
        if closingTime == nil { closingTime = duplicates.compactMap(\.closingTime).first }
        if holidays == nil { holidays = duplicates.compactMap(\.holidays).first }
        if reservationInfo == nil { reservationInfo = duplicates.compactMap(\.reservationInfo).first }
        if recommendedMenu == nil { recommendedMenu = duplicates.compactMap(\.recommendedMenu).first }
        if suggestedDuration == nil { suggestedDuration = duplicates.compactMap(\.suggestedDuration).first }
        if admissionFee == nil { admissionFee = duplicates.compactMap(\.admissionFee).first }
        if discoverySource == nil { discoverySource = duplicates.compactMap(\.discoverySource).first }
        if hoursDetail?.isEmpty ?? true {
            hoursDetail = duplicates.compactMap(\.hoursDetail).first { !$0.isEmpty }
            openingPeriods = duplicates.compactMap(\.openingPeriods).first { !$0.isEmpty }
        }
        if memo?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            memo = duplicates.compactMap(\.memo).first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }

        // "장소확정" survives a merge in either direction — a duplicate
        // having been matched against a real Google/Naver listing is a
        // fact about the place, not about which copy the user happened to
        // keep, and re-confirming by hand afterward is work they already
        // did once.
        if googlePlaceId == nil { googlePlaceId = duplicates.compactMap(\.googlePlaceId).first }
        if naverVerified != true, duplicates.contains(where: { $0.naverVerified == true }) {
            naverVerified = true
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
            for award in duplicate.awards where !awards.contains(award) {
                awards.append(award)
            }
            for option in duplicate.dietaryOptions where !dietaryOptions.contains(option) {
                dietaryOptions.append(option)
            }
            // Matched on the URL rather than the whole entry: `ExternalLink`
            // mints a fresh `id` per instance, so two copies of the same
            // link are never `==` even when they point at the identical page.
            for link in duplicate.externalLinks where !externalLinks.contains(where: { $0.url == link.url }) {
                externalLinks.append(link)
            }
            for date in duplicate.visitDates where !visitDates.contains(date) {
                visitDates.append(date)
            }
            media.mapScreenshots.append(contentsOf: duplicate.media.mapScreenshots)
            media.officialPhotos.append(contentsOf: duplicate.media.officialPhotos)
            media.onsitePhotos.append(contentsOf: duplicate.media.onsitePhotos)
            media.receivedPhotos.append(contentsOf: duplicate.media.receivedPhotos)
            sources.append(contentsOf: duplicate.sources)
        }

        visitDates.sort()

        // Only when the surviving card had no photo of its own to pick
        // from — otherwise its own `coverPhoto` fallback already resolves
        // to one of its own photos, which is the more likely intent than
        // promoting a merged-in card's pick to represent the result.
        if coverPhotoID == nil, !hadOwnMedia {
            coverPhotoID = duplicates.compactMap(\.coverPhotoID).first
        }
    }
}
