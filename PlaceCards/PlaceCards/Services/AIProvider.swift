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

/// The language AI-generated *scan/search results* (category, memo,
/// description, etc.) are written in — independent of the app's own UI,
/// which stays Korean everywhere regardless of this setting. Exposed in
/// Settings as "AI 응답 언어".
enum ScanResultLanguage: String, Codable, CaseIterable, Identifiable {
    case korean
    case english
    case japanese
    case chinese

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .korean: return "한국어"
        case .english: return "English"
        case .japanese: return "日本語"
        case .chinese: return "中文"
        }
    }

    /// Used inside the (Korean-language) prompts below to name the target
    /// language for the model.
    private var promptLanguageName: String {
        switch self {
        case .korean: return "한국어"
        case .english: return "영어(English)"
        case .japanese: return "일본어(日本語)"
        case .chinese: return "중국어(中文)"
        }
    }

    /// Appended to a prompt to steer only its free-text *values* (never its
    /// JSON key names, which the parsing code on this side depends on
    /// staying exactly as written) into this language. `nil` for Korean,
    /// since every prompt below is already written to produce Korean text
    /// by default — appending a no-op instruction would just be noise.
    var promptInstruction: String? {
        guard self != .korean else { return nil }
        return "응답 JSON의 키 이름은 그대로 두고, 텍스트 값(description, category, note, amenities 등)은 반드시 \(promptLanguageName)로 작성하세요."
    }

    private static let defaultsKey = "scanResultLanguage"

    /// Reads the saved response-language choice without needing an
    /// instance, mirroring `SettingsViewModel.currentProviderPriority()` —
    /// looked up right before building a prompt.
    ///
    /// Until the user picks one, this follows the device rather than
    /// defaulting to Korean. It used to be Korean unconditionally, which
    /// was defensible while the app's own language also started Korean;
    /// now that the UI follows iOS (see `AppLanguage.current()`), someone
    /// on an English phone would have got an English app filling their
    /// cards with Korean categories and notes.
    static func current() -> ScanResultLanguage {
        if let stored = UserDefaults.standard.string(forKey: defaultsKey),
           let language = ScanResultLanguage(rawValue: stored) {
            return language
        }
        return AppLanguage.current() == .korean ? .korean : .english
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey)
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
    /// Whatever else the scan could read off the screenshot beyond name/
    /// address/description — phone, website, category, hours, amenities,
    /// when visible (a Google Maps info card routinely shows its own
    /// "영업시간" section, say). Reuses `PlaceWebDetails`'s shape since a
    /// Google Places lookup (`refreshFromGooglePlaceDetails`) fills the
    /// exact same set of fields — `note` on it is always `nil` here since
    /// `description` above already is this result's note.
    let details: PlaceWebDetails?
}

/// Whatever a photo scan or Google Places lookup turns up about a named
/// place — filled into a card's still-blank fields only (see
/// `EditPlaceCardSheet.fillBlankFields(from:)`), never overwriting anything
/// the user or another source already set.
struct PlaceWebDetails {
    let phone: String?
    let website: String?
    let category: String?
    let hoursDetail: [String: String]?
    let closingTime: String?
    let holidays: String?
    let amenities: [String]
    /// How to reserve a table, e.g. "캐치테이블 예약" — free text naming the
    /// method/platform, not a link (see `PlaceCard.reservationSearchURL`'s
    /// own comment for why this app doesn't attempt a direct deep link).
    let reservationInfo: String?
    /// What to order — e.g. "시그니처 라떼, 크로플".
    let recommendedMenu: String?
    /// Third-party recognition — Michelin stars/Bib Gourmand, TripAdvisor
    /// "Travelers' Choice", 블루리본서베이, and the like.
    let awards: [String]
    /// Expected visit length, e.g. "1~2시간" — mainly relevant for
    /// attractions/museums, not restaurants.
    let suggestedDuration: String?
    /// Entry ticket pricing, e.g. "성인 15,000원 / 청소년 10,000원".
    let admissionFee: String?
    /// Dietary accommodations, e.g. "비건 옵션", "글루텐프리", "할랄".
    let dietaryOptions: [String]
    /// Short folksonomy-style tags the AI thinks fit this place (e.g.
    /// "혼밥가능", "데이트코스", "가성비") — unlike every other field on
    /// this struct, `EditPlaceCardSheet` deliberately does NOT auto-apply
    /// these the same way it fills a blank phone/category/hours: tags are
    /// closer to the user's own personal categorization than an objective
    /// fact a photo/search either does or doesn't confirm, so a wrong
    /// guess landing here silently would be more annoying than a wrong
    /// guess in most other fields. Instead these are staged and shown for
    /// the user to accept or dismiss as a batch.
    let tags: [String]
    /// Anything else worth keeping that doesn't fit a specific field —
    /// folded into the card's `memo` the same way a photo scan's
    /// `AIAnalysisResult.description` is.
    let note: String?
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

/// Built fresh (rather than a plain constant) so it always reflects the
/// current "AI 응답 언어" setting (`ScanResultLanguage.current()`) — the
/// prompt text itself stays Korean either way, only the appended
/// instruction (and therefore the model's `description` output) changes.
func defaultPlaceAnalysisPrompt() -> String {
    let base = """
    이 이미지(들)는 지도 앱 스크린샷이거나 SNS(예: 인스타그램) 게시물 스크린샷일 수 있습니다.
    이미지에 등장하는 모든 장소(상호명)를 찾아 각각에 대해 아래 JSON 형식으로만 답하세요. 다른 설명은 하지 마세요.
    한 이미지(또는 여러 이미지 전체)에 여러 장소가 나열되어 있으면 전부 별도 항목으로 포함하세요.
    확실하지 않은 장소명은 추측해서 만들어내지 말고 제외하세요.
    스캔의 목적은 이 장소에 대한 정보를 최대한 모으는 것입니다 — 이름·주소 외에도 이미지에 함께 적힌, 나중에 참고할 만한 내용(해시태그, 한줄평·추천 이유·특이사항 등, 예: "#한끼식사됨")이 있으면 description에 그대로 담아주세요. 그런 내용이 없으면 null로 답하세요.
    지도 앱 스크린샷의 정보 카드에 전화번호·웹사이트·업종/카테고리·영업시간·라스트오더(마감 시간)·정기 휴무일·편의시설(예: 주차, 반려동물 동반, 포장 등)·예약 방법(예: 캐치테이블 예약, 테이블링 예약, 전화 예약만 가능)·추천 메뉴(리뷰나 게시물에 언급된 대표 메뉴/추천 메뉴) 중 실제로 보이는 값이 있으면 아래 해당 필드에 채워주세요. 이미지에 없는 값은 추측하지 말고 null(또는 빈 배열)로 답하세요.
    화면에 수상/인증(미쉐린 별점·빕구르망, TripAdvisor Travelers' Choice, 블루리본서베이 등)·추천 소요 시간(관광지/박물관류에서 흔함)·입장료·식이 옵션(비건, 글루텐프리, 할랄 등)이 보이면 각각 awards/suggestedDuration/admissionFee/dietaryOptions에 채워주세요. 안 보이면 추측하지 말고 null(또는 빈 배열)로 답하세요.
    이 장소를 짧게 분류할 만한 태그도 몇 개(0~5개) 제안해주세요(예: "혼밥가능", "데이트코스", "가성비", "야외석") — 이미지 내용에 근거해서만, 근거 없이 지어내지 마세요.
    {"places": [{"placeName": "장소명", "address": "주소 또는 null", "description": "이름/주소로 담기지 않는, 메모로 남길 만한 내용 또는 null", "confidence": 0.0에서 1.0 사이 숫자, "phone": "전화번호 또는 null", "website": "공식 웹사이트 URL 또는 null", "category": "업종/카테고리 또는 null", "hoursDetail": {"요일": "영업시간"} 형식의 객체 또는 null, "closingTime": "라스트오더/마감 시간 또는 null", "holidays": "정기 휴무일 또는 null", "amenities": ["편의시설", ...] 또는 빈 배열, "reservationInfo": "예약 방법/플랫폼 또는 null", "recommendedMenu": "추천 메뉴 또는 null", "awards": ["수상/인증", ...] 또는 빈 배열, "suggestedDuration": "추천 소요 시간 또는 null", "admissionFee": "입장료 또는 null", "dietaryOptions": ["식이 옵션", ...] 또는 빈 배열, "tags": ["태그", ...] 또는 빈 배열}]}
    장소를 하나도 찾지 못했으면 {"places": []}로 답하세요.
    """
    guard let instruction = ScanResultLanguage.current().promptInstruction else { return base }
    return base + "\n" + instruction
}

/// Every provider below ends up with the model's raw text reply and needs
/// the same first step: pull the JSON object out of it (models don't
/// reliably skip prose/markdown fences despite being asked for none —
/// confirmed the hard way while building Peragra's equivalent extraction
/// service). Used by `parsePlaceAnalysisResults`.
private func extractJSONObjectData(from text: String, errorMessage: String) throws -> Data {
    var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if let fenceRange = trimmed.range(of: "```(?:json)?\\s*([\\s\\S]*?)\\s*```", options: .regularExpression) {
        trimmed = trimmed[fenceRange]
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    guard let jsonStart = trimmed.firstIndex(of: "{"), let jsonEnd = trimmed.lastIndex(of: "}") else {
        throw PlaceCardsError.decodingError(errorMessage)
    }
    guard let data = trimmed[jsonStart...jsonEnd].data(using: .utf8) else {
        throw PlaceCardsError.decodingError(errorMessage)
    }
    return data
}

private func parsePlaceAnalysisResults(from text: String) throws -> [AIAnalysisResult] {
    let data = try extractJSONObjectData(from: text, errorMessage: "장소 정보를 추출하지 못했습니다.")

    struct ExtractedPlace: Decodable {
        let placeName: String
        let address: String?
        let description: String?
        let confidence: Double?
        let phone: String?
        let website: String?
        let category: String?
        let hoursDetail: [String: String]?
        let closingTime: String?
        let holidays: String?
        let amenities: [String]?
        let reservationInfo: String?
        let recommendedMenu: String?
        let awards: [String]?
        let suggestedDuration: String?
        let admissionFee: String?
        let dietaryOptions: [String]?
        let tags: [String]?
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
            confidence: place.confidence ?? 0.5,
            details: PlaceWebDetails(
                phone: place.phone,
                website: place.website,
                category: place.category,
                hoursDetail: place.hoursDetail,
                closingTime: place.closingTime,
                holidays: place.holidays,
                amenities: place.amenities ?? [],
                reservationInfo: place.reservationInfo,
                recommendedMenu: place.recommendedMenu,
                awards: place.awards ?? [],
                suggestedDuration: place.suggestedDuration,
                admissionFee: place.admissionFee,
                dietaryOptions: place.dietaryOptions ?? [],
                tags: place.tags ?? [],
                note: nil
            )
        )
    }
}

/// Maps a failed HTTP response to a typed error the same way across every
/// provider — 401 and 429 are common enough (a bad key, a burst of
/// requests) to deserve their own messages rather than a generic one.
///
/// 403 deliberately falls through to the generic `.apiError` branch below
/// instead of also being treated as `.apiKeyInvalid` — 401 means "this key
/// didn't authenticate at all" (genuinely wrong/revoked), but 403 means
/// "this key authenticated fine, it just isn't allowed to do *this specific
/// request*" (a different problem with a different fix — e.g. a key
/// entitled to some models/endpoints but not others). Showing "유효하지
/// 않은 API 키입니다" for that case sends the user re-typing a key that
/// was never the problem; surfacing the provider's own 403 message instead
/// (via `.apiError`) actually tells them what's wrong.
private func mapHTTPError(statusCode: Int, data: Data, serviceLabel: String) -> PlaceCardsError {
    if statusCode == 401 { return .apiKeyInvalid }
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
