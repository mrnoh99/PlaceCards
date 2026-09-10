import Foundation
import Combine

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var googleAPIKey: String = ""

    @Published var naverClientId: String = ""
    @Published var naverClientSecret: String = ""
    @Published var naverGeocodingClientId: String = ""
    @Published var naverGeocodingClientSecret: String = ""

    @Published var aiProviderType: AIProviderType = .claude
    @Published var aiAPIKey: String = ""
    /// The gateway's chosen model ID — either one of `GatewayModels.all` or
    /// a custom ID the user typed in, mirroring Peragra's own "pick from a
    /// list, or Custom…" model picker. Kept independent of `aiProviderType`
    /// so switching providers and back doesn't lose it.
    @Published var gatewayModel: String = ""
    @Published var mapProvider: MapProvider = .apple
    @Published var statusMessage: String?

    private static let aiProviderDefaultsKey = "aiProviderType"
    private static let gatewayModelDefaultsKey = "gatewayModel"
    private static let mapProviderDefaultsKey = "mapProvider"

    init() {
        googleAPIKey = KeychainService.load(.googlePlacesAPIKey) ?? ""
        naverClientId = KeychainService.load(.naverClientId) ?? ""
        naverClientSecret = KeychainService.load(.naverClientSecret) ?? ""
        naverGeocodingClientId = KeychainService.load(.naverGeocodingClientId) ?? ""
        naverGeocodingClientSecret = KeychainService.load(.naverGeocodingClientSecret) ?? ""
        aiProviderType = Self.currentAIProviderType()
        aiAPIKey = KeychainService.load(aiProviderType.keychainKey) ?? ""
        gatewayModel = Self.currentGatewayModel()
        mapProvider = Self.currentMapProvider()
        // A previously-saved Naver default stops being valid if the device's
        // region is no longer Korea (e.g. the user travelled, or changed
        // their region in iOS Settings) — fall back to Apple rather than
        // keep a choice that's no longer offered in the picker.
        if !mapProvider.isAvailableAsDefault {
            mapProvider = .apple
            saveMapProvider()
        }
    }

    /// Reads the saved AI provider choice without needing an instance, so
    /// `PlaceCardViewModel` can look it up right before analyzing an image.
    static func currentAIProviderType() -> AIProviderType {
        if let stored = UserDefaults.standard.string(forKey: aiProviderDefaultsKey),
           let provider = AIProviderType(rawValue: stored) {
            return provider
        }
        return .claude
    }

    /// Reads the saved gateway model choice without needing an instance, so
    /// `AIProviderFactory` can look it up right before creating a
    /// `GatewayProvider`. Not a secret, so plain UserDefaults (like the
    /// provider choice above) rather than Keychain.
    static func currentGatewayModel() -> String {
        UserDefaults.standard.string(forKey: gatewayModelDefaultsKey) ?? GatewayModels.defaultModel
    }

    /// Reads the saved default map app without needing an instance, so
    /// `PlaceCardDetailView` can look it up right before opening "지도에서
    /// 열기". Not a secret, so plain UserDefaults, like the choices above.
    static func currentMapProvider() -> MapProvider {
        if let stored = UserDefaults.standard.string(forKey: mapProviderDefaultsKey),
           let provider = MapProvider(rawValue: stored) {
            return provider
        }
        return .apple
    }

    /// Reads the saved Naver Local Search credentials without needing an
    /// instance, mirroring `currentAIProviderType()`.
    static func currentNaverLocalSearchCredentials() -> (clientId: String, clientSecret: String)? {
        guard let clientId = KeychainService.load(.naverClientId), !clientId.isEmpty,
              let clientSecret = KeychainService.load(.naverClientSecret), !clientSecret.isEmpty else {
            return nil
        }
        return (clientId, clientSecret)
    }

    /// Reads the saved NCP Geocoding credentials the same way. Kept separate
    /// from the Local Search pair above — they're two different Naver
    /// developer consoles (openapi.naver.com vs. NAVER Cloud Platform).
    static func currentNaverGeocodingCredentials() -> (clientId: String, clientSecret: String)? {
        guard let clientId = KeychainService.load(.naverGeocodingClientId), !clientId.isEmpty,
              let clientSecret = KeychainService.load(.naverGeocodingClientSecret), !clientSecret.isEmpty else {
            return nil
        }
        return (clientId, clientSecret)
    }

    func loadAIKey(for provider: AIProviderType) {
        aiAPIKey = KeychainService.load(provider.keychainKey) ?? ""
    }

    func saveGoogleAPIKey() {
        do {
            try KeychainService.save(googleAPIKey, for: .googlePlacesAPIKey)
            statusMessage = "Google API 키가 저장되었습니다."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func saveNaverLocalSearchCredentials() {
        do {
            try KeychainService.save(naverClientId, for: .naverClientId)
            try KeychainService.save(naverClientSecret, for: .naverClientSecret)
            statusMessage = "Naver 검색 API 키가 저장되었습니다."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func saveNaverGeocodingCredentials() {
        do {
            try KeychainService.save(naverGeocodingClientId, for: .naverGeocodingClientId)
            try KeychainService.save(naverGeocodingClientSecret, for: .naverGeocodingClientSecret)
            statusMessage = "Naver Geocoding API 키가 저장되었습니다."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    /// Saves immediately on selection, unlike the API key sections above —
    /// there's no key to enter alongside it, so a separate "저장" button
    /// would just be an extra tap for nothing.
    func saveMapProvider() {
        UserDefaults.standard.set(mapProvider.rawValue, forKey: Self.mapProviderDefaultsKey)
    }

    func saveAIProviderSettings() {
        UserDefaults.standard.set(aiProviderType.rawValue, forKey: Self.aiProviderDefaultsKey)
        let trimmedModel = gatewayModel.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(
            trimmedModel.isEmpty ? GatewayModels.defaultModel : trimmedModel,
            forKey: Self.gatewayModelDefaultsKey
        )
        do {
            try KeychainService.save(aiAPIKey, for: aiProviderType.keychainKey)
            statusMessage = "\(aiProviderType.displayName) API 키가 저장되었습니다."
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}

extension AIProviderType {
    var keychainKey: KeychainKey {
        switch self {
        case .claude: return .claudeAPIKey
        case .openai: return .openAIAPIKey
        case .gemini: return .geminiAPIKey
        case .gateway: return .gatewayAPIKey
        }
    }
}
