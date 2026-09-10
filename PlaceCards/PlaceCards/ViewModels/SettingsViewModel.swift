import Foundation
import Combine

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var googleAPIKey: String = ""

    @Published var naverMapClientId: String = ""

    @Published var aiProviderType: AIProviderType = .claude
    @Published var aiAPIKey: String = ""
    /// The gateway's chosen model ID — either one of `GatewayModels.all` or
    /// a custom ID the user typed in, mirroring Peragra's own "pick from a
    /// list, or Custom…" model picker. Kept independent of `aiProviderType`
    /// so switching providers and back doesn't lose it.
    @Published var gatewayModel: String = ""
    /// The language AI-generated scan/search results are written in — the
    /// app's own UI text is unaffected (stays Korean everywhere), only
    /// `AIProvider.swift`'s prompts change. See `ScanResultLanguage`.
    @Published var scanResultLanguage: ScanResultLanguage = .korean {
        // Saved immediately on change (no separate "저장" button), matching
        // how the map-provider picker elsewhere in this app behaves —
        // there's no key/secret involved, so nothing to confirm first.
        didSet { scanResultLanguage.save() }
    }
    @Published var statusMessage: String?

    private static let aiProviderDefaultsKey = "aiProviderType"
    private static let gatewayModelDefaultsKey = "gatewayModel"

    init() {
        googleAPIKey = KeychainService.load(.googlePlacesAPIKey) ?? ""
        naverMapClientId = KeychainService.load(.naverMapClientId) ?? ""
        aiProviderType = Self.currentAIProviderType()
        aiAPIKey = KeychainService.load(aiProviderType.keychainKey) ?? ""
        gatewayModel = Self.currentGatewayModel()
        scanResultLanguage = ScanResultLanguage.current()
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

    /// Reads the saved Naver Maps Client ID without needing an instance,
    /// so `PlacesMapView` can look it up right before rendering
    /// `NaverMapWebView`. `nil` (not just empty) when unset.
    static func currentNaverMapClientId() -> String? {
        guard let id = KeychainService.load(.naverMapClientId), !id.isEmpty else { return nil }
        return id
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

    func saveNaverMapClientId() {
        do {
            try KeychainService.save(naverMapClientId, for: .naverMapClientId)
            statusMessage = "Naver Maps Client ID가 저장되었습니다."
        } catch {
            statusMessage = error.localizedDescription
        }
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
