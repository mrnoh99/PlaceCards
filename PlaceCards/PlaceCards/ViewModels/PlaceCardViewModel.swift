import Foundation
import UIKit
import Combine

@MainActor
final class PlaceCardViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?

    @Published var selectedImage: UIImage?
    @Published var extractedPlaceName: String = ""
    @Published var extractedAddress: String = ""
    @Published var candidateResults: [PlaceSearchResult] = []

    private let storageService: StorageService

    init(storageService: StorageService) {
        self.storageService = storageService
    }

    /// Runs the selected image through the user's chosen AI provider and
    /// fills in a first guess at the place name/address for confirmation.
    func analyzeImage(_ image: UIImage, source: SourceType) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        selectedImage = image

        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
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
            let result = try await provider.analyzeImage(imageData: imageData, prompt: defaultPlaceAnalysisPrompt)
            extractedPlaceName = result.placeName
            extractedAddress = result.address ?? ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Verifies a place name against Google Places to get an address,
    /// rating, and contact details worth saving. When Naver Local Search
    /// credentials are configured, the name is resolved against Naver
    /// first — the documented "Naver 발견 + Google 상세정보" hybrid
    /// strategy, since Naver's Korean place-name matching is generally
    /// better than Google's, while Google still supplies the rating/hours
    /// Naver's Local Search doesn't return.
    func search(placeName: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let apiKey = KeychainService.load(.googlePlacesAPIKey), !apiKey.isEmpty else {
            errorMessage = PlaceCardsError.apiKeyMissing.localizedDescription
            return
        }

        let resolvedQuery = await Self.refineWithNaver(Self.resolveSearchQuery(from: placeName))
        let googleService = GooglePlacesService(apiKey: apiKey)

        do {
            candidateResults = try await googleService.search(query: resolvedQuery, coordinates: nil)
            if candidateResults.isEmpty {
                errorMessage = PlaceCardsError.noResults.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Best-effort: if the user has entered Naver Local Search credentials
    /// in Settings, look the query up there first and use its top match's
    /// name in place of the raw query. Silently falls back to the original
    /// query when no credentials are set or Naver has nothing for it — this
    /// is a refinement step, not a required one, so it should never block
    /// or fail the search outright.
    private static func refineWithNaver(_ query: String) async -> String {
        guard let credentials = SettingsViewModel.currentNaverLocalSearchCredentials() else { return query }
        let naverService = NaverLocalSearchService(clientId: credentials.clientId, clientSecret: credentials.clientSecret)
        guard let topResult = try? await naverService.search(query: query, display: 1).first else { return query }
        return topResult.name
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

    func createPlaceCard(from result: PlaceSearchResult, image: UIImage?, source: SourceType) throws -> PlaceCard {
        var card = PlaceCard(
            name: result.name,
            category: result.category,
            address: result.address,
            coordinates: result.coordinates,
            rating: result.rating,
            reviewCount: result.reviewCount,
            phone: result.phone,
            website: result.website
        )

        if let image {
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
                 .googleDirectLookup, .naverDirectLookup, .kakaoDirectLookup, .userManualInput:
                card.media.onsitePhotos.append(item)
            }
        }

        card.sources.append(SourceRecord(sourceType: source, dataProvided: ["name", "address"]))
        card.sources.append(
            SourceRecord(sourceType: .googleDirectLookup, dataProvided: ["rating", "reviewCount", "phone", "website"])
        )

        storageService.save(card)
        return card
    }

    /// Manually-entered places have no coordinates at all, so this makes a
    /// best-effort attempt to fill them in via Naver's Geocoding API (see
    /// `NaverGeocodingService`) when the user has entered NCP credentials
    /// in Settings — the same "geocode an address that came with no
    /// coordinates" role that API plays in Peragra. Silently skipped (not
    /// an error) when no credentials are set or the address can't be
    /// geocoded.
    func createManualPlaceCard(name: String, address: String) async -> PlaceCard {
        var card = PlaceCard(name: name, address: address)
        card.sources.append(SourceRecord(sourceType: .userManualInput, dataProvided: ["name", "address"]))

        if !address.trimmingCharacters(in: .whitespaces).isEmpty,
           let credentials = SettingsViewModel.currentNaverGeocodingCredentials(),
           let geocoded = await NaverGeocodingService.geocode(
               query: address, clientId: credentials.clientId, clientSecret: credentials.clientSecret
           ) {
            card.coordinates = Coordinates(latitude: geocoded.latitude, longitude: geocoded.longitude)
        }

        storageService.save(card)
        return card
    }
}
