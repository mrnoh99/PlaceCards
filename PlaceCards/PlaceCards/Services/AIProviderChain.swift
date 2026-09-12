import Foundation

/// Tries every AI provider the user has registered a key for, in the
/// priority order set in Settings ("AI 제공자 우선순위"), moving to the
/// next on any failure — the whole point of letting more than one
/// provider's key be registered at once is that one provider being down,
/// rate-limited, or misconfigured doesn't block every AI-backed feature
/// in this app (photo scan, web search fill-in) the way a single
/// hardcoded "active provider" used to.
@MainActor
enum AIProviderChain {
    private static func candidates() -> [(type: AIProviderType, apiKey: String)] {
        SettingsViewModel.currentProviderPriority().compactMap { type in
            guard let key = KeychainService.load(type.keychainKey), !key.isEmpty else { return nil }
            return (type, key)
        }
    }

    /// Whether at least one provider has a key registered at all — call
    /// sites check this first so a totally unconfigured setup still gets
    /// the same plain "설정에서 API 키를 먼저 등록해주세요" message it
    /// always has, distinct from `run(_:)`'s thrown error when every
    /// *registered* provider actually failed.
    static func hasAnyConfiguredProvider() -> Bool {
        !candidates().isEmpty
    }

    /// Runs `operation` against each registered provider in priority
    /// order until one succeeds or all of them have failed. `provider` is
    /// whichever one actually answered, and `isFallback` is `true` only
    /// when that wasn't the first (highest-priority) one tried, so a
    /// caller can tell the user their info came from a backup provider
    /// instead of silently switching under them. Throws the *last*
    /// candidate's error when every one fails, since that's the most
    /// likely relevant error for a shared, systemic failure (no network,
    /// say) — an earlier candidate's unrelated error (one provider's key
    /// being invalid while a later one is simply rate-limited) would be a
    /// worse steer for what to actually fix.
    static func run<T>(
        _ operation: (AIProvider) async throws -> T
    ) async throws -> (result: T, provider: AIProviderType, isFallback: Bool) {
        let candidates = candidates()
        guard !candidates.isEmpty else { throw PlaceCardsError.apiKeyMissing }

        var lastError: Error = PlaceCardsError.apiKeyMissing
        for (index, candidate) in candidates.enumerated() {
            let provider = AIProviderFactory.create(type: candidate.type, apiKey: candidate.apiKey)
            do {
                let result = try await operation(provider)
                return (result, candidate.type, index > 0)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }
}

extension AIProviderType {
    /// Appended to a "정보를 채웠습니다" message when this provider
    /// answered only because a higher-priority one failed first — makes a
    /// fallback visible instead of a silent switch.
    var fallbackNoteSuffix: String {
        " " + displayName + "로 대체해 가져왔습니다.".localized
    }
}
