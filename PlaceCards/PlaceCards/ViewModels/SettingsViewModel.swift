import Foundation
import Combine

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var googleAPIKey: String = ""

    @Published var naverMapClientId: String = ""
    /// Search API (`openapi.naver.com`) credentials — see
    /// `KeychainKey.naverSearchClientId`'s doc comment for how this
    /// differs from `naverMapClientId` above.
    @Published var naverSearchClientId: String = ""
    @Published var naverSearchClientSecret: String = ""

    /// Every provider's own API key, keyed by provider — unlike the old
    /// single `aiProviderType`/`aiAPIKey` pair (one "active" provider at a
    /// time), all four can be registered at once now, so
    /// `AIProviderChain.run(_:)` has more than one to fall back through.
    /// Loaded from Keychain per-provider in `init()`; `nil`/missing keys
    /// read back as `""`.
    @Published var providerAPIKeys: [AIProviderType: String] = [:]
    /// The order `AIProviderChain.run(_:)` tries registered providers in —
    /// edited via the up/down buttons in `SettingsView`'s "AI 제공자
    /// 우선순위" section. A provider with no key registered is still
    /// listed (so its position is preserved for whenever a key is added)
    /// but is skipped when actually running a request.
    @Published var providerPriority: [AIProviderType] = AIProviderType.allCases
    /// The gateway's chosen model ID — either one of `GatewayModels.all` or
    /// a custom ID the user typed in, mirroring Peragra's own "pick from a
    /// list, or Custom…" model picker. Independent of which provider(s)
    /// are registered/prioritized, since Gateway either has a key
    /// registered or it doesn't.
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

    private static let providerPriorityDefaultsKey = "aiProviderPriority"
    private static let gatewayModelDefaultsKey = "gatewayModel"

    init() {
        googleAPIKey = KeychainService.load(.googlePlacesAPIKey) ?? ""
        naverMapClientId = KeychainService.load(.naverMapClientId) ?? ""
        naverSearchClientId = KeychainService.load(.naverSearchClientId) ?? ""
        naverSearchClientSecret = KeychainService.load(.naverSearchClientSecret) ?? ""
        for provider in AIProviderType.allCases {
            providerAPIKeys[provider] = KeychainService.load(provider.keychainKey) ?? ""
        }
        providerPriority = Self.currentProviderPriority()
        gatewayModel = Self.currentGatewayModel()
        scanResultLanguage = ScanResultLanguage.current()
    }

    /// Reads the saved provider priority order without needing an
    /// instance, so `AIProviderChain.run(_:)` can look it up right before
    /// trying providers one by one. Any provider missing from a
    /// stored-but-incomplete list (a case added after the user last
    /// reordered, or no priority ever saved at all) is appended at the
    /// end in `AIProviderType`'s own declaration order, so a new provider
    /// is still reachable rather than silently dropped from the chain.
    static func currentProviderPriority() -> [AIProviderType] {
        guard let stored = UserDefaults.standard.array(forKey: providerPriorityDefaultsKey) as? [String] else {
            return AIProviderType.allCases
        }
        let known = stored.compactMap(AIProviderType.init(rawValue:))
        let missing = AIProviderType.allCases.filter { !known.contains($0) }
        return known + missing
    }

    private static func saveProviderPriority(_ order: [AIProviderType]) {
        UserDefaults.standard.set(order.map(\.rawValue), forKey: providerPriorityDefaultsKey)
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

    /// Reads the saved Search API credentials without needing an instance,
    /// so `PlaceCardViewModel` can look them up right before verifying a
    /// Naver-origin shared link. `nil` unless *both* the ID and secret are
    /// actually set — `NaverPlaceSearchService` needs both or neither.
    static func currentNaverSearchCredentials() -> (clientId: String, clientSecret: String)? {
        guard
            let id = KeychainService.load(.naverSearchClientId), !id.isEmpty,
            let secret = KeychainService.load(.naverSearchClientSecret), !secret.isEmpty
        else { return nil }
        return (id, secret)
    }

    func saveGoogleAPIKey() {
        do {
            try KeychainService.save(googleAPIKey, for: .googlePlacesAPIKey)
            statusMessage = "Google API 키가 저장되었습니다.".localized
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func saveNaverMapClientId() {
        do {
            try KeychainService.save(naverMapClientId, for: .naverMapClientId)
            statusMessage = "Naver Maps Client ID가 저장되었습니다.".localized
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func saveNaverSearchCredentials() {
        do {
            try KeychainService.save(naverSearchClientId, for: .naverSearchClientId)
            try KeychainService.save(naverSearchClientSecret, for: .naverSearchClientSecret)
            statusMessage = "Naver 검색 API 정보가 저장되었습니다.".localized
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    /// Saves one provider's key (and, for Gateway, its model choice too —
    /// there's no separate "저장" step for that) without touching any
    /// other provider's — each row in `SettingsView`'s "AI 이미지 분석"
    /// section has its own independent "저장" button calling this.
    func saveProviderAPIKey(_ provider: AIProviderType) {
        if provider == .gateway {
            let trimmedModel = gatewayModel.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(
                trimmedModel.isEmpty ? GatewayModels.defaultModel : trimmedModel,
                forKey: Self.gatewayModelDefaultsKey
            )
        }
        do {
            try KeychainService.save(providerAPIKeys[provider] ?? "", for: provider.keychainKey)
            statusMessage = provider.displayName + " API 키가 저장되었습니다.".localized
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    /// Moves `provider` one slot earlier in `providerPriority` and
    /// persists the new order immediately (no separate "저장" step,
    /// matching how the map-provider picker elsewhere in this app
    /// behaves) — a no-op if it's already first.
    func moveProviderUp(_ provider: AIProviderType) {
        guard let index = providerPriority.firstIndex(of: provider), index > 0 else { return }
        providerPriority.swapAt(index, index - 1)
        Self.saveProviderPriority(providerPriority)
    }

    /// The downward counterpart to `moveProviderUp(_:)` — a no-op if
    /// `provider` is already last.
    func moveProviderDown(_ provider: AIProviderType) {
        guard let index = providerPriority.firstIndex(of: provider), index < providerPriority.count - 1 else { return }
        providerPriority.swapAt(index, index + 1)
        Self.saveProviderPriority(providerPriority)
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
