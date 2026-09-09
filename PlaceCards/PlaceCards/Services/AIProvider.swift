import Foundation

enum AIProviderType: String, Codable, CaseIterable, Identifiable {
    case claude
    case openai
    case gemini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude (Anthropic)"
        case .openai: return "ChatGPT (OpenAI)"
        case .gemini: return "Gemini (Google)"
        }
    }
}

struct AIAnalysisResult {
    let placeName: String
    let address: String?
    let description: String?
    let confidence: Double
}

/// A user-supplied AI account (BYOK) that can look at a screenshot or photo
/// and guess the place it shows.
protocol AIProvider {
    func analyzeImage(imageData: Data, prompt: String) async throws -> AIAnalysisResult
}

enum AIProviderFactory {
    static func create(type: AIProviderType, apiKey: String) -> AIProvider {
        switch type {
        case .claude: return ClaudeProvider(apiKey: apiKey)
        case .openai: return OpenAIProvider(apiKey: apiKey)
        case .gemini: return GeminiProvider(apiKey: apiKey)
        }
    }
}

let defaultPlaceAnalysisPrompt = """
이 이미지는 지도 앱 스크린샷이거나 SNS(예: 인스타그램) 게시물일 수 있습니다.
이미지에서 알아볼 수 있는 장소(상호명)를 찾아 아래 JSON 형식으로만 답하세요. 다른 설명은 하지 마세요.
{"placeName": "장소명", "address": "주소 또는 null", "description": "간단한 설명 또는 null", "confidence": 0.0에서 1.0 사이 숫자}
"""

// MARK: - Claude

final class ClaudeProvider: AIProvider {
    private let apiKey: String
    private let session: URLSession
    private let model: String

    init(apiKey: String, model: String = "claude-sonnet-5", session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    func analyzeImage(imageData: Data, prompt: String) async throws -> AIAnalysisResult {
        guard !apiKey.isEmpty else { throw PlaceCardsError.apiKeyMissing }

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let base64Image = imageData.base64EncodedString()
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ],
                        [
                            "type": "text",
                            "text": prompt
                        ]
                    ]
                ]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "알 수 없는 오류"
            throw PlaceCardsError.apiError(message, statusCode: http.statusCode)
        }

        let decoded = try JSONDecoder().decode(ClaudeMessageResponse.self, from: data)
        guard let text = decoded.content.first(where: { $0.type == "text" })?.text else {
            throw PlaceCardsError.decodingError("Claude 응답을 해석할 수 없습니다.")
        }
        return try Self.parseAnalysisResult(from: text)
    }

    private static func parseAnalysisResult(from text: String) throws -> AIAnalysisResult {
        guard let jsonStart = text.firstIndex(of: "{"), let jsonEnd = text.lastIndex(of: "}") else {
            throw PlaceCardsError.decodingError("장소 정보를 추출하지 못했습니다.")
        }
        let jsonSubstring = text[jsonStart...jsonEnd]
        guard let data = jsonSubstring.data(using: .utf8) else {
            throw PlaceCardsError.decodingError("장소 정보를 추출하지 못했습니다.")
        }
        let parsed = try JSONDecoder().decode(ClaudeExtractedPlace.self, from: data)
        return AIAnalysisResult(
            placeName: parsed.placeName,
            address: parsed.address,
            description: parsed.description,
            confidence: parsed.confidence ?? 0.5
        )
    }
}

private struct ClaudeMessageResponse: Decodable {
    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }
    let content: [ContentBlock]
}

private struct ClaudeExtractedPlace: Decodable {
    let placeName: String
    let address: String?
    let description: String?
    let confidence: Double?
}

// MARK: - OpenAI / Gemini

/// Not implemented yet — the app currently ships a working Claude Vision
/// integration only. These exist so Settings can offer the provider choice
/// described in the product spec without pretending the calls work today.
final class OpenAIProvider: AIProvider {
    private let apiKey: String
    init(apiKey: String) { self.apiKey = apiKey }

    func analyzeImage(imageData: Data, prompt: String) async throws -> AIAnalysisResult {
        throw PlaceCardsError.notImplemented("OpenAI 연동은 아직 지원되지 않습니다.")
    }
}

final class GeminiProvider: AIProvider {
    private let apiKey: String
    init(apiKey: String) { self.apiKey = apiKey }

    func analyzeImage(imageData: Data, prompt: String) async throws -> AIAnalysisResult {
        throw PlaceCardsError.notImplemented("Gemini 연동은 아직 지원되지 않습니다.")
    }
}
