import Foundation
import Security

/// Keys under which BYOK API keys are stored in the Keychain. Never store
/// these in UserDefaults, and never sync them via iCloud.
enum KeychainKey: String {
    case googlePlacesAPIKey
    case claudeAPIKey
    case openAIAPIKey
    case geminiAPIKey
    case gatewayAPIKey
    /// NCP Maps Client ID — used only to render the "지도" tab's Naver
    /// option (`NaverMapWebView`), not any REST API, so no secret is
    /// needed alongside it.
    case naverMapClientId
    /// Search API (`openapi.naver.com`) credentials — a separate NAVER
    /// API HUB Application from the NCP Maps one above (see
    /// `NaverPlaceSearchService`'s own doc comment for exactly where to
    /// register it and find these), issued as a Client ID *and* Secret.
    /// Used by `NaverPlaceSearchService` to verify a place shared from
    /// Naver Map against Naver's own business listings, the same way
    /// `googlePlacesAPIKey` verifies a Google Maps share against Google's.
    case naverSearchClientId
    case naverSearchClientSecret
}

struct KeychainService {
    private static let service = "com.placecards.app"

    /// Trims surrounding whitespace/newlines from `value` before storing —
    /// copying a key/secret from a developer console's web page commonly
    /// picks up a trailing newline or space, which silently doesn't match
    /// the real key and gets rejected by the server as invalid, with
    /// nothing in the app to suggest why.
    static func save(_ value: String, for key: KeychainKey) throws {
        let data = Data(value.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        SecItemDelete(query as CFDictionary)

        var newItem = query
        newItem[kSecValueData as String] = data
        newItem[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(newItem as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw PlaceCardsError.keychainError("저장 실패 (코드 ".localized + "\(status))")
        }
    }

    static func load(_ key: KeychainKey) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: KeychainKey) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        SecItemDelete(query as CFDictionary)
    }
}
