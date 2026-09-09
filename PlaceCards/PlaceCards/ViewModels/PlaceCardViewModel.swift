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
    /// rating, and contact details worth saving.
    func search(placeName: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let apiKey = KeychainService.load(.googlePlacesAPIKey), !apiKey.isEmpty else {
            errorMessage = PlaceCardsError.apiKeyMissing.localizedDescription
            return
        }

        let resolvedQuery = await Self.resolveSearchQuery(from: placeName)
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

    func createManualPlaceCard(name: String, address: String) -> PlaceCard {
        var card = PlaceCard(name: name, address: address)
        card.sources.append(SourceRecord(sourceType: .userManualInput, dataProvided: ["name", "address"]))
        storageService.save(card)
        return card
    }
}
