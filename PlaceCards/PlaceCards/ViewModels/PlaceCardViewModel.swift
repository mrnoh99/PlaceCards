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

    /// Every photo behind the current AI analysis — a screenshot's caption
    /// or map info card can name several places at once, and several
    /// screenshots may be uploaded together so the model can cross-reference
    /// them (mirrors Peragra's `AIExtractionService.extractPlaces(images:)`).
    @Published var selectedImages: [UIImage] = []
    @Published var candidateRows: [PlaceCandidateRow] = []
    /// The first GPS coordinate found among the current batch's original
    /// (EXIF-intact) photo data, if any — passed to Google Places as a
    /// location bias so an on-site photo's own location narrows the
    /// search instead of a blind text query. Shared across every row in
    /// the batch for the same reason their media is: there's no reliable
    /// way to know which specific photo named which specific place.
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
        defer { isLoading = false }

        selectedImages = images
        photoLocationHint = rawImageDatas.lazy.compactMap(PhotoMetadata.extractLocation).first
        guard !images.isEmpty else { return }

        let imageDatas = images.compactMap { $0.jpegData(compressionQuality: 0.8) }
        guard !imageDatas.isEmpty else {
            errorMessage = PlaceCardsError.invalidImage.localizedDescription
            return
        }

        let providerType = SettingsViewModel.currentAIProviderType()
        guard let apiKey = KeychainService.load(providerType.keychainKey), !apiKey.isEmpty else {
            errorMessage = PlaceCardsError.apiKeyMissing.localizedDescription
            return
        }

        let provider = AIProviderFactory.create(type: providerType, apiKey: apiKey)

        do {
            let results = try await provider.analyzePlaces(imageDatas: imageDatas, prompt: defaultPlaceAnalysisPrompt())
            candidateRows = results.map {
                PlaceCandidateRow(name: $0.placeName, address: $0.address ?? "", scannedNote: $0.description)
            }
            if candidateRows.isEmpty {
                errorMessage = "이미지에서 장소를 찾지 못했습니다. 아래에서 직접 추가해주세요.".localized
            }
        } catch {
            errorMessage = error.localizedDescription
        }
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

    /// Within this distance of the row's own address, a same-named result
    /// is treated as a match — beyond it, discarded even if Google ranked
    /// it first. Name-only text search regularly surfaces a same-named
    /// place in a completely different city (a chain, or just a common
    /// name), so when an address is available it's the deciding signal,
    /// not just a ranking hint.
    private static let maxAddressMatchDistanceMeters: CLLocationDistance = 100

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
        if address.isEmpty, let parsedAddress = resolved.address {
            candidateRows[filledIndex].address = parsedAddress
            address = parsedAddress
        }
        if candidateRows[filledIndex].scannedNote == nil, let note = resolved.note {
            candidateRows[filledIndex].scannedNote = note
        }

        let combinedQuery = address.isEmpty ? resolved.name : "\(resolved.name) \(address)"

        do {
            let outcome: SearchOutcome
            if resolved.source == .naverMapShare, let credentials = SettingsViewModel.currentNaverSearchCredentials() {
                let results = try await NaverPlaceSearchService.search(
                    query: combinedQuery,
                    clientId: credentials.clientId,
                    clientSecret: credentials.clientSecret
                )
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
    /// itself already carried) via the distance ground-truth filter — see
    /// `maxAddressMatchDistanceMeters`. The fallback path for anything
    /// that isn't a Naver-origin share with Naver Search credentials
    /// configured (see `search(rowID:)`).
    private func searchViaGoogle(query: String, address: String, coordinateHint: Coordinates?) async throws -> SearchOutcome {
        guard let apiKey = KeychainService.load(.googlePlacesAPIKey), !apiKey.isEmpty else {
            throw PlaceCardsError.apiKeyMissing
        }
        let googleService = GooglePlacesService(apiKey: apiKey)
        let locationHint = coordinateHint ?? photoLocationHint
        let rawResults = try await googleService.search(query: query, coordinates: locationHint)

        var groundTruth: CLLocation?
        if let coordinateHint {
            groundTruth = CLLocation(latitude: coordinateHint.latitude, longitude: coordinateHint.longitude)
        } else if !address.isEmpty, let addressLocation = try? await googleService.geocodeAddress(address) {
            groundTruth = CLLocation(latitude: addressLocation.latitude, longitude: addressLocation.longitude)
        }

        guard let groundTruth else {
            return SearchOutcome(results: rawResults, hadUnfilteredMatches: !rawResults.isEmpty)
        }
        let filtered = rawResults.filter { result in
            guard let coordinates = result.coordinates else { return false }
            return groundTruth.distance(from: CLLocation(latitude: coordinates.latitude, longitude: coordinates.longitude))
                <= Self.maxAddressMatchDistanceMeters
        }
        return SearchOutcome(results: filtered, hadUnfilteredMatches: !rawResults.isEmpty)
    }

    private struct ResolvedSharedPlace {
        var name: String
        var address: String?
        var coordinates: Coordinates?
        var note: String?
        /// Which app the share came from, if any — `.naverMapShare` routes
        /// `search(rowID:)` to `NaverPlaceSearchService` instead of Google
        /// (when Naver Search credentials are configured); `nil` for plain
        /// typed text, which always goes through Google as before.
        var source: SourceType?
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
                    name: name, address: parsed.address, coordinates: parsed.coordinates, note: parsed.note, source: parsed.source
                )
            }
            // A URL-only share (a Google Maps short link, or a full one
            // whose path didn't match the expected place/coordinates
            // shape) has no name of its own to give — recovered from the
            // page itself instead, keeping whatever address/coordinates
            // the URL parse still did yield.
            if let url = parsed.url, let title = await LinkMetadataFetcher.fetchTitle(for: url) {
                return ResolvedSharedPlace(
                    name: title, address: parsed.address, coordinates: parsed.coordinates, note: parsed.note, source: parsed.source
                )
            }
        }

        return ResolvedSharedPlace(name: trimmed, address: nil, coordinates: nil, note: nil, source: nil)
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
            if let chosen = row.chosenResult {
                if let card = try? await createPlaceCard(
                    from: chosen, images: selectedImages, source: source, note: row.scannedNote
                ) {
                    created.append(card)
                }
            } else {
                let card = createManualPlaceCard(
                    name: row.name, address: row.address, images: selectedImages, source: source, note: row.scannedNote
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
    func createPlaceCard(
        from result: PlaceSearchResult, images: [UIImage], source: SourceType, note: String? = nil
    ) async throws -> PlaceCard {
        var card = PlaceCard(
            boardId: boardId,
            name: result.name,
            category: result.category,
            address: result.address,
            coordinates: result.coordinates,
            rating: result.rating,
            reviewCount: result.reviewCount,
            phone: result.phone,
            website: result.website,
            memo: PlaceCard.combinedMemo(nil, appending: note)
        )

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

    /// Manually-entered places have no coordinates at all — unlike a card
    /// created from a chosen Google Places result, there's no automatic
    /// geocoding fallback here; picking "Google에서 검색" is how a manual
    /// entry gets coordinates. `note` is the AI scan's leftover context
    /// (`PlaceCandidateRow.scannedNote`), same as `createPlaceCard(from:)`.
    func createManualPlaceCard(
        name: String, address: String, images: [UIImage] = [], source: SourceType = .userManualInput, note: String? = nil
    ) -> PlaceCard {
        var card = PlaceCard(boardId: boardId, name: name, address: address, memo: PlaceCard.combinedMemo(nil, appending: note))
        card.sources.append(SourceRecord(sourceType: source, dataProvided: ["name", "address"]))

        for image in images {
            if let fileName = try? MediaStore.saveImage(image) {
                card.media.onsitePhotos.append(MediaItem(localPath: fileName, source: source))
            }
        }

        storageService.save(card)
        return card
    }
}
