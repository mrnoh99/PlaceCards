import Foundation
import UIKit
import Combine
import CoreLocation

/// One AI-extracted (or manually added) place awaiting review before being
/// saved as a card — mirrors Peragra's `AddPlaceSheet.CandidateRow`,
/// simplified to this app's own "AI extracts a name/address guess, then
/// verify against Google Places" flow: no category/phone fields of its
/// own, since `createPlaceCard(from:)` already fills those in from
/// whichever Google result gets picked.
struct PlaceCandidateRow: Identifiable {
    let id = UUID()
    var selected = true
    var name: String
    var address: String
    /// Whatever the AI scan found worth keeping beyond the name/address
    /// themselves (`AIAnalysisResult.description` — a hashtag, a one-line
    /// impression, anything that doesn't fit a specific field) — carried
    /// straight into the saved card's `memo` at `createCards()`. The
    /// whole point of scanning a photo is gathering everything usable
    /// about the place, not just enough to identify it.
    var scannedNote: String? = nil
    /// The homepage URL itself, when the row's name/address came from a
    /// plain business-homepage link (see `WebsiteBusinessInfoFetcher`) — a
    /// place worth adding this way is usually one Google Maps doesn't have
    /// listed at all, so this carries straight into the saved card instead
    /// of waiting on a Google Places match that may never come.
    var scannedWebsite: String? = nil
    /// The share's own URL (a Google Maps place link, a Naver Map share
    /// link), when the row was seeded from one — set once, the same way
    /// `originSource` is, and carried into the saved card's
    /// `externalLinks` at `createCards()`. `nil` for plain typed text or a
    /// business-homepage link (`scannedWebsite` covers that case instead).
    var scannedMapURL: URL? = nil
    /// Phone/website/category/hours/amenities the AI scan could read off
    /// the screenshot itself, beyond name/address/note (e.g. a Google Maps
    /// info card's own "영업시간" section) — carried into the saved card
    /// at `createCards()` the same way `scannedNote`/`scannedWebsite` are,
    /// filling in whatever the eventual card doesn't already have from a
    /// chosen search result.
    var scannedDetails: PlaceWebDetails? = nil
    /// Tags the user has actually accepted for this row — starts empty
    /// even when `scannedDetails?.tags` suggests some, since tags aren't
    /// auto-applied anywhere in this app (see `PlaceWebDetails.tags`'s own
    /// doc comment); `AddPlaceCardView` shows those suggestions next to
    /// this row with its own "추가" action that copies them in here via
    /// `PlaceCardViewModel.acceptSuggestedTags(_:forRowID:)`.
    var tags: [String] = []
    /// Which app this row's info originally came from, if any — set once,
    /// the first time `search(rowID:)` resolves this row, and never
    /// touched again after that. Needed because `search(rowID:)` also
    /// overwrites `name` with the cleaned-up parse of whatever was there
    /// (see its own comment), which for a Naver share means the "[네이버
    /// 지도]" tag and URL that `SharedLinkParser` uses to *recognize* a
    /// Naver share are gone from `name` after the first search — without
    /// this stored separately, tapping "Google에서 검색" again (to retry
    /// after a first search came back empty, say) would silently
    /// re-resolve from the now-plain name text, find no source to detect,
    /// and verify against Google instead of Naver every time after the
    /// first.
    var originSource: SourceType?
    var searchResults: [PlaceSearchResult] = []
    /// The specific Google Places result the user tapped, if any — takes
    /// priority over the raw name/address at save time since it carries
    /// verified rating/phone/website/coordinates. Cleared whenever the
    /// name is edited, since it no longer describes what's typed.
    var chosenResult: PlaceSearchResult?
    var isSearching = false
}

@MainActor
final class PlaceCardViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?
    /// A neutral (non-error) notice — currently only used to tell the
    /// user their photo scan was answered by a fallback AI provider
    /// (`AIProviderChain.run(_:)`'s `isFallback`) rather than the one
    /// they've prioritized first, so the switch isn't silent. Shown
    /// alongside `errorMessage` in `AddPlaceCardView`, but styled
    /// differently (not red) since it isn't a failure.
    @Published var infoMessage: String?

    /// Every photo behind the current AI analysis — a screenshot's caption
    /// or map info card can name several places at once, and several
    /// screenshots may be uploaded together so the model can cross-reference
    /// them (mirrors Peragra's `AIExtractionService.extractPlaces(images:)`).
    @Published var selectedImages: [UIImage] = []
    @Published var candidateRows: [PlaceCandidateRow] = []
    /// A GPS coordinate from the current batch's original (EXIF-intact)
    /// photo data, if any — passed to Google Places as a location bias
    /// (and, when nothing else is available, as the actual ground-truth
    /// coordinate for verifying a name search — see `searchViaGoogle`)
    /// so an on-site photo's own location narrows/checks the search
    /// instead of a blind text query. Only ever set when the whole batch
    /// resolves to exactly one place — there's no reliable way to know
    /// which specific photo named which specific place when the batch
    /// yields several, so photo GPS is never used as a shared hint across
    /// rows in that case; those rows rely solely on the AI's per-photo
    /// name/text recognition. For the single-place case, `analyzeImages`
    /// averages every photo's GPS instead of just taking the first:
    /// several photos of the same place taken from slightly different
    /// spots (walking up to it, standing across the street) average out
    /// sensor/positioning noise better than any single one of them alone.
    @Published var photoLocationHint: Coordinates?

    private let storageService: StorageService
    private let boardId: String

    init(storageService: StorageService, boardId: String) {
        self.storageService = storageService
        self.boardId = boardId
    }

    var selectedRowCount: Int {
        candidateRows.filter { $0.selected && !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }

    /// Runs every selected image through the user's chosen AI provider in
    /// one request, replacing the review list with whatever places it
    /// found — a screenshot naming several places (or several screenshots
    /// handed over together) becomes several rows here, each still
    /// individually editable/deselectable before saving. `rawImageDatas`
    /// are the original, unmodified bytes as picked (not `images`'
    /// re-encoded JPEGs, which have already lost their EXIF) — read only
    /// for `photoLocationHint`.
    func analyzeImages(_ images: [UIImage], rawImageDatas: [Data], source: SourceType) async {
        isLoading = true
        errorMessage = nil
        infoMessage = nil
        defer { isLoading = false }

        selectedImages = images
        let photoCoordinates = rawImageDatas.compactMap(PhotoMetadata.extractLocation)
        // Left nil until AI confirms the batch is exactly one place (below)
        // — until then we don't know whether these photos even belong to
        // the same place, so no photo's GPS is safe to use for anything.
        photoLocationHint = nil
        guard !images.isEmpty else { return }

        let imageDatas = images.compactMap { $0.jpegData(compressionQuality: 0.8) }
        guard !imageDatas.isEmpty else {
            errorMessage = PlaceCardsError.invalidImage.localizedDescription
            return
        }

        guard AIProviderChain.hasAnyConfiguredProvider() else {
            errorMessage = PlaceCardsError.apiKeyMissing.localizedDescription
            return
        }

        do {
            let (results, provider, isFallback) = try await AIProviderChain.run {
                try await $0.analyzePlaces(imageDatas: imageDatas, prompt: defaultPlaceAnalysisPrompt())
            }
            candidateRows = results.map {
                PlaceCandidateRow(
                    name: $0.placeName, address: $0.address ?? "", scannedNote: $0.description, scannedDetails: $0.details
                )
            }
            // Only a confirmed single-place batch gets a photoLocationHint:
            // every photo in it is of the one same place, so averaging
            // their GPS (when there's more than one) is safe. A batch that
            // resolved to several places leaves it nil (set above) — rows
            // may each come from a different photo, so no single photo's
            // GPS can stand in as a shared hint/ground-truth for all of
            // them; those rows rely on the AI's per-photo name/text
            // recognition alone.
            var notes: [String] = []
            if results.count == 1 {
                let candidate = photoCoordinates.count > 1
                    ? Self.averageCoordinate(photoCoordinates)
                    : photoCoordinates.first
                if let candidate {
                    if let verified = await verifiedPhotoLocationHint(candidate, placeAddress: results.first?.address) {
                        photoLocationHint = verified
                    } else {
                        notes.append("사진의 위치 정보가 인식된 장소 주소와 너무 멀어 사진 위치는 사용하지 않았습니다.".localized)
                    }
                }
            }
            if candidateRows.isEmpty {
                errorMessage = "이미지에서 장소를 찾지 못했습니다. 아래에서 직접 추가해주세요.".localized
            } else {
                if isFallback { notes.append(provider.fallbackNoteSuffix.trimmingCharacters(in: .whitespaces)) }
                if !notes.isEmpty { infoMessage = notes.joined(separator: "\n") }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Cross-checks a candidate `photoLocationHint` (this batch's own photo
    /// GPS) against the AI-identified place's own address before trusting
    /// it — a photo's EXIF GPS can be wrong for the place it's meant to
    /// document (saved from elsewhere, taken earlier in the same trip,
    /// stale metadata carried over from an edit), so agreement with the
    /// address the AI actually read off the photo is real corroborating
    /// evidence, not a redundant check. Returns the candidate unchanged
    /// when there's no address to check it against or the address fails
    /// to geocode (nothing to contradict it, so no reason to distrust the
    /// photo), and `nil` when the two disagree by more than
    /// `maxPhotoLocationMatchDistanceMeters`.
    private func verifiedPhotoLocationHint(_ candidate: Coordinates, placeAddress: String?) async -> Coordinates? {
        let address = placeAddress?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !address.isEmpty,
            let apiKey = KeychainService.load(.googlePlacesAPIKey), !apiKey.isEmpty,
            let addressLocation = try? await GooglePlacesService(apiKey: apiKey).geocodeAddress(address)
        else { return candidate }

        let distance = CLLocation(latitude: addressLocation.latitude, longitude: addressLocation.longitude)
            .distance(from: CLLocation(latitude: candidate.latitude, longitude: candidate.longitude))
        return distance <= Self.maxPhotoLocationMatchDistanceMeters ? candidate : nil
    }

    /// A plain arithmetic mean of latitude/longitude — accurate enough at
    /// the scale this matters for (several photos of one place, taken at
    /// most a couple hundred meters apart); the sphere's curvature only
    /// meaningfully distorts a plain average over much larger distances
    /// than that, so there's no need for a proper geodesic mean here.
    private static func averageCoordinate(_ coordinates: [Coordinates]) -> Coordinates? {
        guard !coordinates.isEmpty else { return nil }
        let latitude = coordinates.map(\.latitude).reduce(0, +) / Double(coordinates.count)
        let longitude = coordinates.map(\.longitude).reduce(0, +) / Double(coordinates.count)
        return Coordinates(latitude: latitude, longitude: longitude)
    }

    func addBlankRow() {
        candidateRows.append(PlaceCandidateRow(name: "", address: ""))
    }

    func removeRow(id: UUID) {
        candidateRows.removeAll { $0.id == id }
    }

    func toggleSelected(id: UUID) {
        guard let index = candidateRows.firstIndex(where: { $0.id == id }) else { return }
        candidateRows[index].selected.toggle()
    }

    /// Also copies the result's own name/address onto the row, so the
    /// visible fields always match what will actually be saved.
    func chooseResult(_ result: PlaceSearchResult, forRowID id: UUID) {
        guard let index = candidateRows.firstIndex(where: { $0.id == id }) else { return }
        candidateRows[index].chosenResult = result
        candidateRows[index].name = result.name
        candidateRows[index].address = result.address
    }

    /// Editing the name after picking a Google result means it may no
    /// longer describe that result — clear it so saving falls back to the
    /// plain name/address (geocoded fresh) instead of the now-stale match.
    func clearChosenResult(id: UUID) {
        guard let index = candidateRows.firstIndex(where: { $0.id == id }) else { return }
        candidateRows[index].chosenResult = nil
    }

    /// Copies whichever of `tags` the row doesn't already have into it —
    /// called when the user taps "추가" on `AddPlaceCardView`'s own
    /// suggested-tags row for this candidate (see `PlaceCandidateRow.tags`'s
    /// own doc comment for why tags need this explicit accept step instead
    /// of just landing on the row already).
    func acceptSuggestedTags(_ tags: [String], forRowID id: UUID) {
        guard let index = candidateRows.firstIndex(where: { $0.id == id }) else { return }
        for tag in tags where !candidateRows[index].tags.contains(tag) {
            candidateRows[index].tags.append(tag)
        }
    }

    /// Within this distance of the row's own address, a same-named result
    /// is treated as a match — beyond it, discarded even if Google ranked
    /// it first. Name-only text search regularly surfaces a same-named
    /// place in a completely different city (a chain, or just a common
    /// name), so when an address is available it's the deciding signal,
    /// not just a ranking hint.
    private static let maxAddressMatchDistanceMeters: CLLocationDistance = 100

    /// Looser than `maxAddressMatchDistanceMeters` — a typed address or a
    /// share link's own baked-in coordinate is as precise as its source,
    /// but a photo's own EXIF GPS (`photoLocationHint`) only reflects
    /// wherever the phone happened to be standing when the shutter went
    /// off (across a parking lot, inside a large mall, at a rooftop
    /// viewpoint looking down at the place), not necessarily the place's
    /// own doorstep — a tight 100m cutoff would routinely reject the
    /// *correct* match on nothing more than ordinary GPS imprecision.
    private static let maxPhotoLocationMatchDistanceMeters: CLLocationDistance = 500

    /// Verifies one row's current name (and, when present, address) to get
    /// a verified address, rating, and contact details worth saving. A
    /// Naver Map share is checked against Naver's own local-business
    /// database (`NaverPlaceSearchService`, when its API credentials are
    /// configured) rather than Google's — since it named one specific
    /// place there, that's the source worth verifying it against. Every
    /// other row (a Google Maps share, a plain typed name, or a Naver
    /// share with no Naver Search credentials set) goes through
    /// `searchViaGoogle`, whose address/coordinates-based distance filter
    /// (`maxAddressMatchDistanceMeters`) discards any candidate that isn't
    /// actually near where the row says it should be — name text alone
    /// isn't enough to trust a result is the right place, only that it's
    /// *a* place with that name somewhere. When the row's name is itself
    /// a shared link/text, whatever `resolveSharedPlace` recovers from it
    /// (address, exact coordinates, extra notes) fills in any of those
    /// fields the row doesn't already have.
    func search(rowID: UUID) async {
        guard let index = candidateRows.firstIndex(where: { $0.id == rowID }) else { return }
        let placeName = candidateRows[index].name
        var address = candidateRows[index].address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !placeName.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        candidateRows[index].isSearching = true
        errorMessage = nil
        defer {
            if let index = candidateRows.firstIndex(where: { $0.id == rowID }) {
                candidateRows[index].isSearching = false
            }
        }

        let resolved = await Self.resolveSharedPlace(from: placeName)

        guard let filledIndex = candidateRows.firstIndex(where: { $0.id == rowID }) else { return }
        // `placeName` itself is whatever raw text seeded the row — for a
        // share/link that's the whole multi-line blob (app tag, name,
        // address, URL all together), not something worth showing the user
        // forever. `resolved.name` is what `resolveSharedPlace` actually
        // parsed out of it, so it replaces the field now that resolution
        // has run — a no-op for plain typed text, which resolves to itself.
        candidateRows[filledIndex].name = resolved.name
        if address.isEmpty, let parsedAddress = resolved.address {
            candidateRows[filledIndex].address = parsedAddress
            address = parsedAddress
        }
        if candidateRows[filledIndex].scannedNote == nil, let note = resolved.note {
            candidateRows[filledIndex].scannedNote = note
        }
        if candidateRows[filledIndex].scannedWebsite == nil, let website = resolved.website {
            candidateRows[filledIndex].scannedWebsite = website
        }
        if candidateRows[filledIndex].scannedMapURL == nil, let mapURL = resolved.mapURL {
            candidateRows[filledIndex].scannedMapURL = mapURL
        }
        if candidateRows[filledIndex].originSource == nil {
            candidateRows[filledIndex].originSource = resolved.source
        }
        let originSource = candidateRows[filledIndex].originSource

        let combinedQuery = address.isEmpty ? resolved.name : "\(resolved.name) \(address)"

        do {
            let outcome: SearchOutcome
            if originSource == .naverMapShare, let credentials = SettingsViewModel.currentNaverSearchCredentials() {
                var results = try await NaverPlaceSearchService.search(
                    query: combinedQuery,
                    clientId: credentials.clientId,
                    clientSecret: credentials.clientSecret
                )
                // Naver's local search matches more like a business-
                // directory keyword lookup than Google's free-text search
                // — a full street address (down to the unit/floor number)
                // appended to the name can fail to match even for a place
                // that came from Naver Map itself, where the plain name
                // alone would. Only retried when the combined query came
                // back empty, so this never overrides a genuine match.
                if results.isEmpty, !address.isEmpty {
                    results = try await NaverPlaceSearchService.search(
                        query: resolved.name,
                        clientId: credentials.clientId,
                        clientSecret: credentials.clientSecret
                    )
                }
                outcome = SearchOutcome(results: results, hadUnfilteredMatches: !results.isEmpty)
            } else {
                outcome = try await searchViaGoogle(query: combinedQuery, address: address, coordinateHint: resolved.coordinates)
            }

            guard let index = candidateRows.firstIndex(where: { $0.id == rowID }) else { return }
            candidateRows[index].searchResults = outcome.results
            if outcome.results.isEmpty {
                errorMessage = (!address.isEmpty && outcome.hadUnfilteredMatches)
                    ? "\"" + address + "\" 근처 100m 이내에서 찾지 못했습니다.".localized
                    : PlaceCardsError.noResults.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private struct SearchOutcome {
        var results: [PlaceSearchResult]
        /// Whether the underlying search found anything at all before any
        /// distance-from-address filtering ran — lets the caller tell
        /// "nothing exists with that name" apart from "found it, but not
        /// near that address" for a clearer error message.
        var hadUnfilteredMatches: Bool
    }

    /// Verifies against Google Places, narrowing by the row's address (or,
    /// when there is one, the exact coordinates a Google Maps share link
    /// itself already carried, or — when neither of those exist — the
    /// photo's own EXIF GPS) via the distance ground-truth filter — see
    /// `maxAddressMatchDistanceMeters`/`maxPhotoLocationMatchDistanceMeters`.
    /// The fallback path for anything that isn't a Naver-origin share
    /// with Naver Search credentials configured (see `search(rowID:)`).
    private func searchViaGoogle(query: String, address: String, coordinateHint: Coordinates?) async throws -> SearchOutcome {
        guard let apiKey = KeychainService.load(.googlePlacesAPIKey), !apiKey.isEmpty else {
            throw PlaceCardsError.apiKeyMissing
        }
        let googleService = GooglePlacesService(apiKey: apiKey)
        let locationHint = coordinateHint ?? photoLocationHint
        let rawResults = try await googleService.search(query: query, coordinates: locationHint)

        var groundTruth: CLLocation?
        var groundTruthRadius = Self.maxAddressMatchDistanceMeters
        if let coordinateHint {
            groundTruth = CLLocation(latitude: coordinateHint.latitude, longitude: coordinateHint.longitude)
        } else if !address.isEmpty, let addressLocation = try? await googleService.geocodeAddress(address) {
            groundTruth = CLLocation(latitude: addressLocation.latitude, longitude: addressLocation.longitude)
        } else if let photoLocationHint {
            // The one case this app can still verify a plain name-only
            // search against even with no address at all — a photo's own
            // GPS is real evidence of where it was taken, not a guess.
            groundTruth = CLLocation(latitude: photoLocationHint.latitude, longitude: photoLocationHint.longitude)
            groundTruthRadius = Self.maxPhotoLocationMatchDistanceMeters
        }

        guard let groundTruth else {
            return SearchOutcome(results: rawResults, hadUnfilteredMatches: !rawResults.isEmpty)
        }
        let filtered = rawResults.filter { result in
            guard let coordinates = result.coordinates else { return false }
            return groundTruth.distance(from: CLLocation(latitude: coordinates.latitude, longitude: coordinates.longitude))
                <= groundTruthRadius
        }
        return SearchOutcome(results: filtered, hadUnfilteredMatches: !rawResults.isEmpty)
    }

    private struct ResolvedSharedPlace {
        var name: String
        var address: String?
        var coordinates: Coordinates?
        var note: String?
        /// Recovered only from a plain business-homepage link (see
        /// `WebsiteBusinessInfoFetcher`) — `nil` for every other source,
        /// since a Naver/Google Maps share's own verified search result
        /// already carries a website by the time a card is saved.
        var website: String?
        /// Which app the share came from, if any — `.naverMapShare` routes
        /// `search(rowID:)` to `NaverPlaceSearchService` instead of Google
        /// (when Naver Search credentials are configured); `nil` for plain
        /// typed text, which always goes through Google as before.
        var source: SourceType?
        /// The share's own URL (a Google Maps place link, a Naver Map
        /// share link), when `SharedLinkParser` recognized one — kept
        /// verbatim so the saved card's `externalLinks` links straight
        /// back to the exact page the user shared, instead of a
        /// name/coordinate-reconstructed deep link. `nil` for plain typed
        /// text or a business-homepage link (that one already becomes
        /// `website` instead).
        var mapURL: URL?
    }

    /// Turns whatever the user pasted (or a Share Extension handed over)
    /// into a finished search query plus whatever else came with it, so
    /// pasting a Naver Map share or a Google Maps link into the place-name
    /// field "just works" the same way typing a name does — and, unlike a
    /// plain name, also recovers the address/coordinates/extra notes the
    /// share itself already carried, instead of leaving them to a second
    /// manual entry. Resolution happens fully here, in one call, so the
    /// field is only ever shown a finished query — never a raw,
    /// not-yet-resolved link.
    private static func resolveSharedPlace(from input: String) async -> ResolvedSharedPlace {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        if let parsed = SharedLinkParser.parse(trimmed) {
            if let name = parsed.name {
                return ResolvedSharedPlace(
                    name: name, address: parsed.address, coordinates: parsed.coordinates, note: parsed.note,
                    website: nil, source: parsed.source, mapURL: parsed.url
                )
            }
            // A URL-only share (a Google Maps short link, or a full one
            // whose path didn't match the expected place/coordinates
            // shape) has no name of its own to give — recovered from the
            // page itself instead, keeping whatever address/coordinates
            // the URL parse still did yield.
            if let url = parsed.url, let title = await LinkMetadataFetcher.fetchTitle(for: url) {
                return ResolvedSharedPlace(
                    name: title, address: parsed.address, coordinates: parsed.coordinates, note: parsed.note,
                    website: nil, source: parsed.source, mapURL: parsed.url
                )
            }
            return ResolvedSharedPlace(
                name: trimmed, address: parsed.address, coordinates: parsed.coordinates, note: parsed.note,
                website: nil, source: parsed.source, mapURL: parsed.url
            )
        }

        // Not a recognized Naver/Google Maps share at all — the common
        // remaining case is a plain business homepage link, for a place
        // Google Maps itself doesn't have listed. Its own schema.org JSON-LD
        // (when present) recovers name/address/phone/hours far more
        // reliably than just the page's <title>; Instagram is excluded
        // since a post/reel page never carries a business listing, only a
        // generic Instagram `Organization` block that would be a false match.
        if let url = SharedLinkParser.extractURL(from: trimmed), !SharedLinkParser.isInstagramLink(trimmed) {
            if let info = await WebsiteBusinessInfoFetcher.fetch(for: url) {
                return ResolvedSharedPlace(
                    name: info.name, address: info.address, coordinates: nil, note: info.note,
                    website: url.absoluteString, source: nil, mapURL: nil
                )
            }
            if let title = await LinkMetadataFetcher.fetchTitle(for: url) {
                return ResolvedSharedPlace(
                    name: title, address: nil, coordinates: nil, note: nil,
                    website: url.absoluteString, source: nil, mapURL: nil
                )
            }
        }

        return ResolvedSharedPlace(
            name: trimmed, address: nil, coordinates: nil, note: nil, website: nil, source: nil, mapURL: nil
        )
    }

    /// Turns a row's own share origin/URL into the `externalLinks` entry
    /// worth saving on its card — a Naver Map or Google Maps share links
    /// straight back to the exact page the user shared, a more precise
    /// "지도에서 열기" than `MapOpeners.swift`'s own name/coordinate
    /// reconstruction. Empty for anything else (plain typed text, a
    /// business-homepage link — the latter already becomes `website`).
    private static func externalLinks(source: SourceType?, mapURL: URL?) -> [ExternalLink] {
        guard let mapURL else { return [] }
        switch source {
        case .naverMapShare: return [ExternalLink(platform: "Naver Map", url: mapURL.absoluteString)]
        case .googleMapShare: return [ExternalLink(platform: "Google Maps", url: mapURL.absoluteString)]
        default: return []
        }
    }

    /// Saves every selected, named row as its own card in one pass — each
    /// gets its own copy of every attached photo (never the same file
    /// shared across cards, since `StorageService.delete` removes a card's
    /// media files from disk outright) — there's no reliable way to know
    /// which specific screenshot named which specific place when several
    /// were uploaded and analyzed together, so every screenshot from this
    /// batch is treated as a reference for every card it produced.
    func createCards(source: SourceType) async -> [PlaceCard] {
        isSaving = true
        defer { isSaving = false }

        var created: [PlaceCard] = []
        for row in candidateRows where row.selected && !row.name.trimmingCharacters(in: .whitespaces).isEmpty {
            let links = Self.externalLinks(source: row.originSource, mapURL: row.scannedMapURL)
            if let chosen = row.chosenResult {
                if let card = try? await createPlaceCard(
                    from: chosen, images: selectedImages, source: source,
                    note: row.scannedNote, website: row.scannedWebsite, details: row.scannedDetails, tags: row.tags,
                    externalLinks: links
                ) {
                    created.append(card)
                }
            } else {
                let card = await createManualPlaceCard(
                    name: row.name, address: row.address, images: selectedImages, source: source,
                    note: row.scannedNote, website: row.scannedWebsite, details: row.scannedDetails, tags: row.tags,
                    externalLinks: links
                )
                created.append(card)
            }
        }
        return created
    }

    /// `note` is whatever the AI scan found worth keeping beyond name/
    /// address (`PlaceCandidateRow.scannedNote`) — folded into `memo`
    /// here while every other field comes from `result` (the verified
    /// Google Places match), so the two sources combine instead of the
    /// scan's extra context getting lost the moment a result is chosen.
    /// `website` only ever fills in when `result` itself has none — a row
    /// resolved from a business-homepage link (`scannedWebsite`) still
    /// picking up a verified Google Places match shouldn't lose the one
    /// link it started from. `details` fills in whatever `result` itself
    /// has no field for at all (hours/closing time/holidays/amenities) —
    /// AI-sourced, when the row came from a photo scan or web search; a
    /// Google-verified result with no AI involved at all still gets its
    /// hours filled non-AI, straight from Google's own place-details
    /// lookup (`fetchGoogleHoursDetail(placeId:)` below). Similarly, a
    /// Naver-verified result that ends up with no photo at all (Naver's
    /// search API returns none) gets a best-effort Google Places lookup
    /// for one instead (`fetchGooglePhotoFallback(name:address:
    /// coordinates:)` below).
    func createPlaceCard(
        from result: PlaceSearchResult, images: [UIImage], source: SourceType,
        note: String? = nil, website: String? = nil, details: PlaceWebDetails? = nil, tags: [String] = [],
        externalLinks: [ExternalLink] = []
    ) async throws -> PlaceCard {
        var card = PlaceCard(
            boardId: boardId,
            name: result.name,
            category: result.category,
            address: result.address,
            coordinates: result.coordinates,
            googlePlaceId: result.isFromGooglePlaces ? result.id : nil,
            rating: result.rating,
            reviewCount: result.reviewCount,
            priceLevel: result.priceLevel,
            phone: result.phone,
            website: result.website ?? website,
            externalLinks: externalLinks,
            tags: tags,
            memo: PlaceCard.combinedMemo(nil, appending: note)
        )
        card.applyScannedDetails(details)

        if card.hoursDetail?.isEmpty ?? true, result.isFromGooglePlaces,
           let hoursDetail = await fetchGoogleHoursDetail(placeId: result.id), !hoursDetail.isEmpty {
            card.hoursDetail = hoursDetail
        }

        for image in images {
            let fileName = try MediaStore.saveImage(image)
            let item = MediaItem(localPath: fileName, source: source)
            switch source {
            case .naverMapScreenshot, .googleMapScreenshot, .kakaoMapScreenshot, .instagramScreenshot:
                card.media.mapScreenshots.append(item)
            case .onsitePhoto:
                card.media.onsitePhotos.append(item)
            case .receivedPhoto:
                card.media.receivedPhotos.append(item)
            case .naverMapShare, .googleMapShare, .kakaoMapShare,
                 .googleDirectLookup, .naverDirectLookup, .kakaoDirectLookup, .userManualInput,
                 .unsplashSearch:
                card.media.onsitePhotos.append(item)
            }
        }

        if let item = await fetchOfficialPhoto(googlePhotoName: result.photoName) {
            card.media.officialPhotos.append(item)
        } else if card.media.allItems.isEmpty, !result.isFromGooglePlaces,
                  let item = await fetchGooglePhotoFallback(name: result.name, address: result.address, coordinates: card.coordinates) {
            card.media.officialPhotos.append(item)
        }

        card.sources.append(SourceRecord(sourceType: source, dataProvided: ["name", "address"]))
        card.sources.append(
            SourceRecord(sourceType: .googleDirectLookup, dataProvided: ["rating", "reviewCount", "phone", "website"])
        )

        storageService.save(card)
        return card
    }

    /// Best-effort: finds a thumbnail-worthy photo for this place so the
    /// card list/gallery always have something to show — Google's own
    /// photo for the place, when Google Places found one. Silently
    /// skipped when there's no `googlePhotoName` or the fetch fails —
    /// this only ever supplements a card, never blocks saving it.
    private func fetchOfficialPhoto(googlePhotoName: String?) async -> MediaItem? {
        guard let googlePhotoName,
              let apiKey = KeychainService.load(.googlePlacesAPIKey), !apiKey.isEmpty else { return nil }
        let googleService = GooglePlacesService(apiKey: apiKey)
        guard let data = try? await googleService.photoData(photoName: googlePhotoName),
              let fileName = try? MediaStore.saveImage(data: data) else { return nil }
        return MediaItem(localPath: fileName, source: .googleDirectLookup)
    }

    /// Best-effort, entirely non-AI: `search(query:coordinates:)`'s own
    /// result never carries opening hours (only Google's separate
    /// Place Details call does), so this is the one piece a
    /// Google-verified card would otherwise only ever get from an AI
    /// photo scan or web search. Called for every Google-origin result
    /// regardless of whether any AI provider is even configured — this
    /// only needs the same Google Places API key `search`/`photoData`
    /// already use. Silently skipped (returns `nil`) on any failure,
    /// same as `fetchOfficialPhoto` above.
    private func fetchGoogleHoursDetail(placeId: String) async -> [String: String]? {
        guard let apiKey = KeychainService.load(.googlePlacesAPIKey), !apiKey.isEmpty else { return nil }
        let googleService = GooglePlacesService(apiKey: apiKey)
        return try? await googleService.details(placeId: placeId).hoursDetail
    }

    /// Used by two callers that would otherwise end up with no photo at
    /// all: a Naver-verified card (Naver's local search API returns no
    /// photos — `NaverLocalItem.toSearchResult()` always sets
    /// `photoName: nil`, so `fetchOfficialPhoto(googlePhotoName:)` above
    /// never finds anything for it) and a manually-entered card
    /// (`createManualPlaceCard`, which never went through any search at
    /// all). Both look the same place up on Google Places by name+address
    /// instead, as a fallback. Only ever called when the card has no
    /// photo of its own yet (never overrides a real photo the user
    /// picked), and only trusts a Google
    /// result that's actually within `maxAddressMatchDistanceMeters` of
    /// the card's own coordinates — the same ground-truth check
    /// `searchViaGoogle` uses, since a same-named place a few blocks
    /// over having a photo doesn't mean it's a photo *of this place*.
    /// Silently skipped (returns `nil`) on any failure — no coordinates,
    /// no Google API key, no match, no photo on the match — same as
    /// every other best-effort media step in this app.
    private func fetchGooglePhotoFallback(name: String, address: String, coordinates: Coordinates?) async -> MediaItem? {
        guard let coordinates,
              let apiKey = KeychainService.load(.googlePlacesAPIKey), !apiKey.isEmpty else { return nil }
        let googleService = GooglePlacesService(apiKey: apiKey)
        let query = address.isEmpty ? name : "\(name) \(address)"
        guard let results = try? await googleService.search(query: query, coordinates: coordinates) else { return nil }

        let groundTruth = CLLocation(latitude: coordinates.latitude, longitude: coordinates.longitude)
        guard
            let match = results.first(where: { candidate in
                guard let candidateCoordinates = candidate.coordinates else { return false }
                return groundTruth.distance(
                    from: CLLocation(latitude: candidateCoordinates.latitude, longitude: candidateCoordinates.longitude)
                ) <= Self.maxAddressMatchDistanceMeters
            }),
            let photoName = match.photoName
        else { return nil }

        guard let data = try? await googleService.photoData(photoName: photoName),
              let fileName = try? MediaStore.saveImage(data: data) else { return nil }
        return MediaItem(localPath: fileName, source: .googleDirectLookup)
    }

    /// A manually-entered place never went through `search(rowID:)`'s own
    /// Google/Naver verification, so unlike `createPlaceCard(from:)` it
    /// starts with no coordinates and no chance at an official photo —
    /// this makes a best effort at both anyway, entirely non-AI: an
    /// address geocodes to coordinates the same way
    /// `searchViaGoogle`/`GooglePlacesService.geocodeAddress(_:)` already
    /// do elsewhere, falling back to the photo's own EXIF GPS
    /// (`photoLocationHint`) when there's no address to geocode at all —
    /// the one case this app still has real location evidence for a
    /// place with nothing else identifying it. Those coordinates then feed the same
    /// distance-verified `fetchGooglePhotoFallback(name:address:
    /// coordinates:)` a Naver-origin card uses (see its own comment) —
    /// name+address alone found a same-named place a town over often
    /// enough that skipping the coordinate check wasn't worth the risk of
    /// attaching the wrong place's photo. Both best-effort: no address,
    /// no Google API key, no geocode match, or no photo on the match all
    /// just leave the card exactly as it was before this. `note` is the
    /// AI scan's leftover context (`PlaceCandidateRow.scannedNote`), same
    /// as `createPlaceCard(from:)`. `website` is only ever set this way
    /// for a row resolved from a plain business-homepage link
    /// (`PlaceCandidateRow.scannedWebsite`). `details` is the rest of
    /// what the AI scan could read off the screenshot (phone/category/
    /// hours/amenities), same as `createPlaceCard(from:)`.
    func createManualPlaceCard(
        name: String, address: String, images: [UIImage] = [], source: SourceType = .userManualInput,
        note: String? = nil, website: String? = nil, details: PlaceWebDetails? = nil, tags: [String] = [],
        externalLinks: [ExternalLink] = []
    ) async -> PlaceCard {
        var card = PlaceCard(
            boardId: boardId, name: name, address: address, website: website, externalLinks: externalLinks,
            tags: tags, memo: PlaceCard.combinedMemo(nil, appending: note)
        )
        card.applyScannedDetails(details)
        card.sources.append(SourceRecord(sourceType: source, dataProvided: ["name", "address"]))

        for image in images {
            if let fileName = try? MediaStore.saveImage(image) {
                card.media.onsitePhotos.append(MediaItem(localPath: fileName, source: source))
            }
        }

        let trimmedAddress = address.trimmingCharacters(in: .whitespaces)
        if !trimmedAddress.isEmpty, let apiKey = KeychainService.load(.googlePlacesAPIKey), !apiKey.isEmpty {
            card.coordinates = try? await GooglePlacesService(apiKey: apiKey).geocodeAddress(trimmedAddress)
        }
        // No address to geocode (or it didn't resolve to anything) — a
        // photo's own EXIF GPS is real evidence of where it was taken,
        // not a guess, so it's worth keeping even when it's the *only*
        // location info this card has. `photoLocationHint` is shared
        // across every row a batch of photos produced (see its own
        // property comment), so this can be wrong when several photos of
        // different places were analyzed together and this particular
        // row didn't come from the one photo the hint is actually from —
        // a real but narrower risk than saving the card with no location
        // at all.
        if card.coordinates == nil, let photoLocationHint {
            card.coordinates = photoLocationHint
        }

        if card.media.allItems.isEmpty, let coordinates = card.coordinates,
           let item = await fetchGooglePhotoFallback(name: name, address: address, coordinates: coordinates) {
            card.media.officialPhotos.append(item)
        }

        storageService.save(card)
        return card
    }
}
