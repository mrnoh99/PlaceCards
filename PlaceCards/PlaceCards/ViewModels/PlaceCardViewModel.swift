import Foundation
import UIKit
import Combine

/// One AI-extracted (or manually added) place awaiting review before being
/// saved as a card — mirrors Peragra's `AddPlaceSheet.CandidateRow`,
/// simplified to this app's own "AI extracts a name/address guess, then
/// verify against Google Places" flow: no category/phone/notes fields of
/// its own, since `createPlaceCard(from:)` already fills those in from
/// whichever Google result gets picked.
struct PlaceCandidateRow: Identifiable {
    let id = UUID()
    var selected = true
    var name: String
    var address: String
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
            let results = try await provider.analyzePlaces(imageDatas: imageDatas, prompt: defaultPlaceAnalysisPrompt)
            candidateRows = results.map { PlaceCandidateRow(name: $0.placeName, address: $0.address ?? "") }
            if candidateRows.isEmpty {
                errorMessage = "이미지에서 장소를 찾지 못했습니다. 아래에서 직접 추가해주세요."
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

    /// Verifies one row's current name against Google Places to get an
    /// address, rating, and contact details worth saving.
    func search(rowID: UUID) async {
        guard let index = candidateRows.firstIndex(where: { $0.id == rowID }) else { return }
        let placeName = candidateRows[index].name
        guard !placeName.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        candidateRows[index].isSearching = true
        errorMessage = nil
        defer {
            if let index = candidateRows.firstIndex(where: { $0.id == rowID }) {
                candidateRows[index].isSearching = false
            }
        }

        guard let apiKey = KeychainService.load(.googlePlacesAPIKey), !apiKey.isEmpty else {
            errorMessage = PlaceCardsError.apiKeyMissing.localizedDescription
            return
        }

        let resolvedQuery = await Self.resolveSearchQuery(from: placeName)
        let googleService = GooglePlacesService(apiKey: apiKey)

        do {
            let results = try await googleService.search(query: resolvedQuery, coordinates: photoLocationHint)
            guard let index = candidateRows.firstIndex(where: { $0.id == rowID }) else { return }
            candidateRows[index].searchResults = results
            if results.isEmpty {
                errorMessage = PlaceCardsError.noResults.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Turns whatever the user pasted into a plain search query, so pasting
    /// a Naver Map share or a Google Maps link into the place-name field
    /// "just works" the same way typing a name does. Resolution happens
    /// fully here, in one call, so the field is only ever shown a finished
    /// query — never a raw, not-yet-resolved link.
    private static func resolveSearchQuery(from input: String) async -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        if let parsed = SharedLinkParser.parse(trimmed), let name = parsed.name {
            return name
        }

        if let url = SharedLinkParser.extractURL(from: trimmed),
           let title = await LinkMetadataFetcher.fetchTitle(for: url) {
            return title
        }

        return trimmed
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
                if let card = try? await createPlaceCard(from: chosen, images: selectedImages, source: source) {
                    created.append(card)
                }
            } else {
                let card = await createManualPlaceCard(
                    name: row.name, address: row.address, images: selectedImages, source: source
                )
                created.append(card)
            }
        }
        return created
    }

    func createPlaceCard(from result: PlaceSearchResult, images: [UIImage], source: SourceType) async throws -> PlaceCard {
        var card = PlaceCard(
            boardId: boardId,
            name: result.name,
            category: result.category,
            address: result.address,
            coordinates: result.coordinates,
            rating: result.rating,
            reviewCount: result.reviewCount,
            phone: result.phone,
            website: result.website
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

        if let item = await fetchOfficialPhoto(
            hasExistingPhoto: !card.media.allItems.isEmpty,
            name: result.name, category: result.category, googlePhotoName: result.photoName
        ) {
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
    /// card list/gallery always have something to show. Tries Google's own
    /// photo for the place first (when Google Places found one) — this one
    /// runs regardless of whether the user already attached photos, since
    /// it's the preferred thumbnail either way. Only when that comes up
    /// empty (no Google photo, or the place already has no photo at all —
    /// `hasExistingPhoto`) does it fall back to a generic Unsplash search by
    /// name, and only when the user has configured an Unsplash access key
    /// in Settings. Silently skipped at any step that has nothing to offer
    /// — this only ever supplements a card, never blocks saving it.
    private func fetchOfficialPhoto(
        hasExistingPhoto: Bool, name: String, category: String?, googlePhotoName: String?
    ) async -> MediaItem? {
        if let googlePhotoName,
           let apiKey = KeychainService.load(.googlePlacesAPIKey), !apiKey.isEmpty {
            let googleService = GooglePlacesService(apiKey: apiKey)
            if let data = try? await googleService.photoData(photoName: googlePhotoName),
               let fileName = try? MediaStore.saveImage(data: data) {
                return MediaItem(localPath: fileName, source: .googleDirectLookup)
            }
        }

        guard !hasExistingPhoto, let unsplashKey = SettingsViewModel.currentUnsplashAccessKey() else { return nil }
        let query = [name, category].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        guard !query.isEmpty else { return nil }

        let unsplashService = UnsplashImageService(accessKey: unsplashKey)
        guard let data = await unsplashService.searchPhotoData(query: query),
              let fileName = try? MediaStore.saveImage(data: data) else { return nil }
        return MediaItem(localPath: fileName, source: .unsplashSearch)
    }

    /// Manually-entered places have no coordinates at all — unlike a card
    /// created from a chosen Google Places result, there's no automatic
    /// geocoding fallback here; picking "Google에서 검색" is how a manual
    /// entry gets coordinates.
    func createManualPlaceCard(name: String, address: String, images: [UIImage] = [], source: SourceType = .userManualInput) async -> PlaceCard {
        var card = PlaceCard(boardId: boardId, name: name, address: address)
        card.sources.append(SourceRecord(sourceType: source, dataProvided: ["name", "address"]))

        for image in images {
            if let fileName = try? MediaStore.saveImage(image) {
                card.media.onsitePhotos.append(MediaItem(localPath: fileName, source: source))
            }
        }

        if let item = await fetchOfficialPhoto(
            hasExistingPhoto: !card.media.allItems.isEmpty,
            name: name, category: card.category, googlePhotoName: nil
        ) {
            card.media.officialPhotos.append(item)
        }

        storageService.save(card)
        return card
    }
}
