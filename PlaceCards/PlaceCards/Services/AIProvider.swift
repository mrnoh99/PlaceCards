import Foundation

enum AIProviderType: String, Codable, CaseIterable, Identifiable {
    case claude
    case openai
    case gemini
    // Listed last, mirroring Peragra's own ordering — it's an available
    // fallback, not the first thing to reach for.
    case gateway

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude (Anthropic)"
        case .openai: return "ChatGPT (OpenAI)"
        case .gemini: return "Gemini (Google)"
        case .gateway: return "Gateway (factchat-cloud)"
        }
    }

    /// Matches the defaults Peragra ships for each provider's Vision model.
    var defaultModel: String {
        switch self {
        case .claude: return "claude-sonnet-5"
        case .openai: return "gpt-4o"
        case .gemini: return "gemini-2.0-flash"
        case .gateway: return GatewayModels.defaultModel
        }
    }
}

/// Model IDs available on the factchat-cloud.mindlogic.ai gateway, as
/// listed on its own "API Gateway" docs page (ported from Peragra, which
/// uses this same third-party gateway as its default AI provider). Not
/// necessarily exhaustive — Settings also accepts a custom ID for anything
/// not listed here, same as Peragra's own model picker.
enum GatewayModels {
    struct Model: Identifiable {
        let id: String
        let label: String
    }

    static let all: [Model] = [
        Model(id: "claude-sonnet-5", label: "Claude Sonnet 5"),
        Model(id: "claude-opus-5", label: "Claude Opus 5"),
        Model(id: "claude-fable-5-1", label: "Claude Fable 5.1"),
        Model(id: "claude-fable-5", label: "Claude Fable 5"),
        Model(id: "gpt-5.6-luna", label: "GPT-5.6 Luna"),
        Model(id: "gpt-5.6-terra", label: "GPT-5.6 Terra"),
        Model(id: "gpt-5.6-sol", label: "GPT-5.6 Sol"),
        Model(id: "gpt-5.5", label: "GPT-5.5"),
    ]

    static let defaultModel = "claude-sonnet-5"
}

struct AIAnalysisResult {
    let placeName: String
    let address: String?
    let description: String?
    let confidence: Double
}

/// A user-supplied AI account (BYOK) that can look at one or more
/// screenshots/photos and extract every place they show — a single
/// screenshot's caption or map info card often names several distinct
/// places at once, and several screenshots may be handed over together so
/// the model can cross-reference them (mirrors Peragra's
/// `AIExtractionService.extractPlaces(images:)`).
protocol AIProvider {
    func analyzePlaces(imageDatas: [Data], prompt: String) async throws -> [AIAnalysisResult]
}

enum AIProviderFactory {
    /// `SettingsViewModel.currentGatewayModel()` is main-actor-isolated
    /// (inherited from that class's `@MainActor`), and every real caller
    /// (`PlaceCardViewModel.analyzeImages`) already runs on the main actor
    /// itself, so this is too rather than hopping off it just to read a
    /// UserDefaults value.
    @MainActor
    static func create(type: AIProviderType, apiKey: String) -> AIProvider {
        switch type {
        case .claude: return ClaudeProvider(apiKey: apiKey)
        case .openai: return OpenAIProvider(apiKey: apiKey)
        case .gemini: return GeminiProvider(apiKey: apiKey)
        case .gateway: return GatewayProvider(apiKey: apiKey, model: SettingsViewModel.currentGatewayModel())
        }
    }
}

let defaultPlaceAnalysisPrompt = """
이 이미지(들)는 지도 앱 스크린샷이거나 SNS(예: 인스타그램) 게시물 스크린샷일 수 있습니다.
이미지에 등장하는 모든 장소(상호명)를 찾아 각각에 대해 아래 JSON 형식으로만 답하세요. 다른 설명은 하지 마세요.
한 이미지(또는 여러 이미지 전체)에 여러 장소가 나열되어 있으면 전부 별도 항목으로 포함하세요.
확실하지 않은 장소명은 추측해서 만들어내지 말고 제외하세요.
{"places": [{"placeName": "장소명", "address": "주소 또는 null", "description": "간단한 설명 또는 null", "confidence": 0.0에서 1.0 사이 숫자}]}
장소를 하나도 찾지 못했으면 {"places": []}로 답하세요.
"""

/// The three providers below all end up with the model's raw text reply and
/// need the same last step: pull the JSON object out of it (models don't
/// reliably skip prose/markdown fences despite the prompt asking for none —
/// confirmed the hard way while building Peragra's equivalent extraction
/// service) and decode it into a list of `AIAnalysisResult`s.
private func parsePlaceAnalysisResults(from text: String) throws -> [AIAnalysisResult] {
    var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if let fenceRange = trimmed.range(of: "```(?:json)?\\s*([\\s\\S]*?)\\s*```", options: .regularExpression) {
        trimmed = trimmed[fenceRange]
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    guard let jsonStart = trimmed.firstIndex(of: "{"), let jsonEnd = trimmed.lastIndex(of: "}") else {
        throw PlaceCardsError.decodingError("장소 정보를 추출하지 못했습니다.")
    }
    guard let data = trimmed[jsonStart...jsonEnd].data(using: .utf8) else {
        throw PlaceCardsError.decodingError("장소 정보를 추출하지 못했습니다.")
    }

    struct ExtractedPlace: Decodable {
        let placeName: String
        let address: String?
        let description: String?
        let confidence: Double?
    }
    struct ExtractedPlacesResponse: Decodable {
        let places: [ExtractedPlace]
    }

    guard let parsed = try? JSONDecoder().decode(ExtractedPlacesResponse.self, from: data) else {
        throw PlaceCardsError.decodingError("장소 정보를 추출하지 못했습니다.")
    }
    return parsed.places.map { place in
        AIAnalysisResult(
            placeName: place.placeName,
            address: place.address,
            description: place.description,
            confidence: place.confidence ?? 0.5
        )
    }
}

/// Maps a failed HTTP response to a typed error the same way across every
/// provider — 401 and 429 are common enough (a bad key, a burst of
/// requests) to deserve their own messages rather than a generic one.
private func mapHTTPError(statusCode: Int, data: Data, serviceLabel: String) -> PlaceCardsError {
    if statusCode == 401 || statusCode == 403 { return .apiKeyInvalid }
    if statusCode == 429 { return .rateLimited(serviceLabel) }
    let message = String(data: data, encoding: .utf8) ?? "알 수 없는 오류"
    return .apiError(message, statusCode: statusCode)
}

/// OpenAI itself and the factchat-cloud gateway both speak the same
/// OpenAI-compatible chat-completions API, so `OpenAIProvider` and
/// `GatewayProvider` share this one request/response path (mirroring how
/// Peragra's AIExtractionService shares its equivalent helper across every
/// OpenAI-compatible provider it supports).
private func performOpenAICompatibleChatRequest(
    endpoint: URL,
    apiKey: String,
    model: String,
    prompt: String,
    imageDatas: [Data],
    serviceLabel: String,
    session: URLSession
) async throws -> [AIAnalysisResult] {
    guard !apiKey.isEmpty else { throw PlaceCardsError.apiKeyMissing }

    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

    var content: [[String: Any]] = [["type": "text", "text": prompt]]
    for imageData in imageDatas {
        let imageDataURL = "data:image/jpeg;base64,\(imageData.base64EncodedString())"
        content.append(["type": "image_url", "image_url": ["url": imageDataURL]])
    }
    let body: [String: Any] = [
        "model": model,
        "messages": [
            ["role": "user", "content": content]
        ]
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await session.data(for: request)
    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
        throw mapHTTPError(statusCode: http.statusCode, data: data, serviceLabel: serviceLabel)
    }

    guard
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let choices = json["choices"] as? [[String: Any]],
        let message = choices.first?["message"] as? [String: Any],
        let text = message["content"] as? String
    else {
        throw PlaceCardsError.decodingError("\(serviceLabel) 응답을 해석할 수 없습니다.")
    }
    return try parsePlaceAnalysisResults(from: text)
}

// MARK: - Claude (Anthropic Messages API)

final class ClaudeProvider: AIProvider {
    private let apiKey: String
    private let session: URLSession
    private let model: String

    init(apiKey: String, model: String = AIProviderType.claude.defaultModel, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    func analyzePlaces(imageDatas: [Data], prompt: String) async throws -> [AIAnalysisResult] {
        guard !apiKey.isEmpty else { throw PlaceCardsError.apiKeyMissing }

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var content: [[String: Any]] = imageDatas.map { imageData in
            [
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": imageData.base64EncodedString()
                ]
            ]
        }
        content.append(["type": "text", "text": prompt])

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "messages": [
                ["role": "user", "content": content]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw mapHTTPError(statusCode: http.statusCode, data: data, serviceLabel: "Claude")
        }

        let decoded = try JSONDecoder().decode(ClaudeMessageResponse.self, from: data)
        guard let text = decoded.content.first(where: { $0.type == "text" })?.text else {
            throw PlaceCardsError.decodingError("Claude 응답을 해석할 수 없습니다.")
        }
        return try parsePlaceAnalysisResults(from: text)
    }
}

private struct ClaudeMessageResponse: Decodable {
    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }
    let content: [ContentBlock]
}

// MARK: - OpenAI (Chat Completions API)

final class OpenAIProvider: AIProvider {
    private let apiKey: String
    private let session: URLSession
    private let model: String

    init(apiKey: String, model: String = AIProviderType.openai.defaultModel, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    func analyzePlaces(imageDatas: [Data], prompt: String) async throws -> [AIAnalysisResult] {
        try await performOpenAICompatibleChatRequest(
            endpoint: URL(string: "https://api.openai.com/v1/chat/completions")!,
            apiKey: apiKey,
            model: model,
            prompt: prompt,
            imageDatas: imageDatas,
            serviceLabel: "OpenAI",
            session: session
        )
    }
}

// MARK: - Gateway (factchat-cloud.mindlogic.ai, ported from Peragra)

/// Routes through a third-party OpenAI-compatible gateway
/// (factchat-cloud.mindlogic.ai) instead of any provider's own API —
/// Peragra's default AI provider, offering Claude/GPT models through one
/// endpoint and one API key. Its actual feature support (vision
/// passthrough, JSON mode) is undocumented from here, so — same as every
/// other provider in this file — this prompts for JSON in plain
/// chat-completion form and decodes the response manually rather than
/// relying on any provider-specific structured-output extension.
final class GatewayProvider: AIProvider {
    private let apiKey: String
    private let session: URLSession
    private let model: String

    init(apiKey: String, model: String = GatewayModels.defaultModel, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    func analyzePlaces(imageDatas: [Data], prompt: String) async throws -> [AIAnalysisResult] {
        // Trailing slash matters — the gateway's documented endpoint is
        // "/v1/gateway/chat/completions/" and a request without one risks
        // a 404 or a broken POST-to-GET redirect on a Django-style backend
        // that enforces trailing slashes (this is exactly why Peragra's
        // own client keeps it).
        try await performOpenAICompatibleChatRequest(
            endpoint: URL(string: "https://factchat-cloud.mindlogic.ai/v1/gateway/chat/completions/")!,
            apiKey: apiKey,
            model: model,
            prompt: prompt,
            imageDatas: imageDatas,
            serviceLabel: "Gateway",
            session: session
        )
    }
}

// MARK: - Gemini (Google Generative Language API)

final class GeminiProvider: AIProvider {
    private let apiKey: String
    private let session: URLSession
    private let model: String

    init(apiKey: String, model: String = AIProviderType.gemini.defaultModel, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    func analyzePlaces(imageDatas: [Data], prompt: String) async throws -> [AIAnalysisResult] {
        guard !apiKey.isEmpty else { throw PlaceCardsError.apiKeyMissing }

        var components = URLComponents(
            string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
        )
        components?.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components?.url else {
            throw PlaceCardsError.networkError("Gemini 요청 URL을 만들 수 없습니다.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var parts: [[String: Any]] = [["text": prompt]]
        for imageData in imageDatas {
            parts.append(["inline_data": ["mime_type": "image/jpeg", "data": imageData.base64EncodedString()]])
        }

        let body: [String: Any] = [
            "contents": [
                ["role": "user", "parts": parts]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw mapHTTPError(statusCode: http.statusCode, data: data, serviceLabel: "Gemini")
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = json["candidates"] as? [[String: Any]],
            let content = candidates.first?["content"] as? [String: Any],
            let responseParts = content["parts"] as? [[String: Any]],
            let text = responseParts.first?["text"] as? String
        else {
            throw PlaceCardsError.decodingError("Gemini 응답을 해석할 수 없습니다.")
        }
        return try parsePlaceAnalysisResults(from: text)
    }
}
