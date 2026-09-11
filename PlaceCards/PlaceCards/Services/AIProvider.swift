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
    /// instance, mirroring `SettingsViewModel.currentAIProviderType()` —
    /// looked up right before building a prompt.
    static func current() -> ScanResultLanguage {
        if let stored = UserDefaults.standard.string(forKey: defaultsKey),
           let language = ScanResultLanguage(rawValue: stored) {
            return language
        }
        return .korean
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
    /// "영업시간" section, say). Reuses `PlaceWebDetails`'s exact shape
    /// since it's the same set of fields `searchWebForDetails` fills, just
    /// read off a photo instead of a web search — `note` on it is always
    /// `nil` here since `description` above already is this result's note.
    let details: PlaceWebDetails?
}

/// Whatever a web search turns up about a named place beyond what a photo
/// scan or Google Places lookup already covers — filled into a card's
/// still-blank fields only (see `EditPlaceCardSheet.applyWebDetails`),
/// never overwriting anything the user or another source already set.
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

    /// Searches the web for further details about a named place — phone,
    /// website, category, hours, amenities, anything else worth noting —
    /// via a hosted web-search tool, rather than reading a photo. Real
    /// implementations: `ClaudeProvider` (Messages API's `web_search`
    /// tool), `OpenAIProvider` (the Responses API's `web_search` tool —
    /// a different endpoint from `analyzePlaces`' Chat Completions call,
    /// since hosted web search isn't available there), `GeminiProvider`
    /// (the newer Interactions API's `google_search` tool — likewise a
    /// different endpoint from `analyzePlaces`' `generateContent` call,
    /// which as of this writing no longer documents a grounding tool of
    /// its own). `GatewayProvider` doesn't implement this at all — its
    /// shared chat-completions endpoint has no hosted search tool of its
    /// own, confirmed by an actual "tools.0.type: Input should be
    /// 'function'" error from trying to guess one (see `GatewayProvider`'s
    /// own comment) — so it always falls through to the default below.
    /// Any provider that can't identify a real hosted tool to use gets the
    /// default below and stays unsupported, rather than
    /// bolting on a guessed tool shape that risks being silently ignored
    /// — which would fill a card's fields with the model's ungrounded
    /// guesses while looking exactly like a real web search happened. A
    /// clear "not supported" error is safer than that.
    ///
    /// `knownLinks` is the card's own `externalLinks` (a Google/Naver Map
    /// listing already verified for this card, a TripAdvisor/Yelp page
    /// added by hand, ...), each formatted as `"<platform>: <url>"` —
    /// passed through into `webDetailsSearchPrompt(for:knownLinks:)` so
    /// the model checks these specific, already-trusted pages before
    /// falling back to a generic search. Empty when the card has none yet.
    func searchWebForDetails(name: String, address: String, knownLinks: [String]) async throws -> PlaceWebDetails
}

extension AIProvider {
    func searchWebForDetails(name: String, address: String, knownLinks: [String]) async throws -> PlaceWebDetails {
        throw PlaceCardsError.notImplemented("웹 검색 (이 AI 제공자는 아직 지원하지 않음 — 설정에서 AI 제공자를 Claude/ChatGPT/Gemini 중 하나로 바꾸거나, Gateway에서 Claude/GPT 계열 모델을 선택해주세요)")
    }
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
    이 장소를 짧게 분류할 만한 태그도 몇 개(0~5개) 제안해주세요(예: "혼밥가능", "데이트코스", "가성비", "야외석") — 이미지 내용에 근거해서만, 근거 없이 지어내지 마세요.
    {"places": [{"placeName": "장소명", "address": "주소 또는 null", "description": "이름/주소로 담기지 않는, 메모로 남길 만한 내용 또는 null", "confidence": 0.0에서 1.0 사이 숫자, "phone": "전화번호 또는 null", "website": "공식 웹사이트 URL 또는 null", "category": "업종/카테고리 또는 null", "hoursDetail": {"요일": "영업시간"} 형식의 객체 또는 null, "closingTime": "라스트오더/마감 시간 또는 null", "holidays": "정기 휴무일 또는 null", "amenities": ["편의시설", ...] 또는 빈 배열, "reservationInfo": "예약 방법/플랫폼 또는 null", "recommendedMenu": "추천 메뉴 또는 null", "tags": ["태그", ...] 또는 빈 배열}]}
    장소를 하나도 찾지 못했으면 {"places": []}로 답하세요.
    """
    guard let instruction = ScanResultLanguage.current().promptInstruction else { return base }
    return base + "\n" + instruction
}

/// Every provider below ends up with the model's raw text reply and needs
/// the same first step: pull the JSON object out of it (models don't
/// reliably skip prose/markdown fences despite being asked for none —
/// confirmed the hard way while building Peragra's equivalent extraction
/// service). Shared by `parsePlaceAnalysisResults` and `parseWebDetails`.
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
                tags: place.tags ?? [],
                note: nil
            )
        )
    }
}

/// `knownLinks` (each `"<platform>: <url>"`, e.g. `"Google Maps:
/// https://..."`) are pages already verified for this specific card —
/// checked first, ahead of a generic web search, since they're more
/// trustworthy than whatever a plain name/address search happens to turn
/// up. Even with none, the model is still steered toward checking the
/// same handful of map/review/booking platforms this app's own
/// `externalLinks` field is meant for, before a fully generic search —
/// those tend to carry more accurate, current info (hours, menus) than a
/// business's own often-stale homepage.
private func webDetailsSearchPrompt(for query: String, knownLinks: [String]) -> String {
    var base = "\"\(query)\"에 대한 정보를 웹에서 검색해서 아래 JSON 형식으로만 답하세요. 다른 설명은 하지 마세요.\n"
    if !knownLinks.isEmpty {
        base += "다음은 이 장소에 대해 이미 확인된 링크입니다 — 정보를 찾을 때 이 페이지들을 가장 먼저 확인하세요:\n"
        base += knownLinks.map { "- \($0)" }.joined(separator: "\n") + "\n"
    }
    base += """
    검색할 때는 Google Maps, Naver Map, TripAdvisor, Yelp, OpenTable, Resy, TheFork, Tabelog, Zomato 같은 지도·리뷰·예약 플랫폼에 등록된 정보를 먼저 확인하고, 그래도 부족하면 그 외 웹 페이지도 검색하세요 — 이런 플랫폼의 정보가 업체 홈페이지보다 최신이고 정확한 경우가 많습니다.
    확실하지 않은 값은 추측해서 만들어내지 말고 null로 답하세요.
    이 장소를 짧게 분류할 만한 태그도 몇 개(0~5개) 제안해주세요(예: "혼밥가능", "데이트코스", "가성비", "야외석") — 검색으로 실제 확인되는 내용에 근거해서만, 근거 없이 지어내지 마세요.
    {"phone": "전화번호 또는 null", "website": "공식 웹사이트 URL 또는 null", "category": "업종/카테고리 또는 null", "hoursDetail": {"요일": "영업시간"} 형식의 객체 또는 null, "closingTime": "라스트오더/마감 시간 또는 null", "holidays": "정기 휴무일 또는 null", "amenities": ["편의시설", ...] 또는 빈 배열, "reservationInfo": "예약 방법/플랫폼(예: 캐치테이블 예약, 전화 예약만 가능) 또는 null", "recommendedMenu": "추천 메뉴/시그니처 메뉴 또는 null", "tags": ["태그", ...] 또는 빈 배열, "note": "그 외 참고할 만한 정보(메모로 남길 만한 것) 또는 null"}
    """
    guard let instruction = ScanResultLanguage.current().promptInstruction else { return base }
    return base + "\n" + instruction
}

private func parseWebDetails(from text: String) throws -> PlaceWebDetails {
    let data = try extractJSONObjectData(from: text, errorMessage: "웹 검색 정보를 추출하지 못했습니다.")

    struct Extracted: Decodable {
        let phone: String?
        let website: String?
        let category: String?
        let hoursDetail: [String: String]?
        let closingTime: String?
        let holidays: String?
        let amenities: [String]?
        let reservationInfo: String?
        let recommendedMenu: String?
        let tags: [String]?
        let note: String?
    }

    guard let parsed = try? JSONDecoder().decode(Extracted.self, from: data) else {
        throw PlaceCardsError.decodingError("웹 검색 정보를 추출하지 못했습니다.")
    }
    return PlaceWebDetails(
        phone: parsed.phone,
        website: parsed.website,
        category: parsed.category,
        hoursDetail: parsed.hoursDetail,
        closingTime: parsed.closingTime,
        holidays: parsed.holidays,
        amenities: parsed.amenities ?? [],
        reservationInfo: parsed.reservationInfo,
        recommendedMenu: parsed.recommendedMenu,
        tags: parsed.tags ?? [],
        note: parsed.note
    )
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

    /// Uses Claude's hosted web-search tool (`web_search`) instead of
    /// reading a photo — the model runs its own searches server-side and
    /// this just reads the final answer back out. A tool-using turn's
    /// `content` interleaves `server_tool_use`/`web_search_tool_result`
    /// blocks with `text` blocks, so the *last* text block (not the
    /// first, as in `analyzePlaces`) is the model's actual final answer;
    /// `ClaudeMessageResponse.ContentBlock` already decodes those other
    /// block types fine since it only reads `type`/`text` and ignores
    /// unrecognized keys.
    func searchWebForDetails(name: String, address: String, knownLinks: [String]) async throws -> PlaceWebDetails {
        guard !apiKey.isEmpty else { throw PlaceCardsError.apiKeyMissing }

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = trimmedAddress.isEmpty ? name : "\(name), \(trimmedAddress)"

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "tools": [
                ["type": "web_search_20260209", "name": "web_search", "max_uses": 5]
            ],
            "messages": [
                ["role": "user", "content": webDetailsSearchPrompt(for: query, knownLinks: knownLinks)]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw mapHTTPError(statusCode: http.statusCode, data: data, serviceLabel: "Claude")
        }

        let decoded = try JSONDecoder().decode(ClaudeMessageResponse.self, from: data)
        guard let text = decoded.content.last(where: { $0.type == "text" })?.text else {
            throw PlaceCardsError.decodingError("Claude 응답을 해석할 수 없습니다.")
        }
        return try parseWebDetails(from: text)
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

    /// The Chat Completions endpoint `analyzePlaces` uses above has no
    /// hosted web-search tool of its own — this needs OpenAI's separate
    /// Responses API instead (`POST /v1/responses`, `tools: [{"type":
    /// "web_search"}]`), whose response shape is an `output` array of
    /// typed items rather than Chat Completions' `choices`: the model's
    /// final answer is the `content[].text` of whichever `output` item
    /// has `"type": "message"` (the array also carries a `web_search_call`
    /// item recording that the tool ran, which this ignores).
    func searchWebForDetails(name: String, address: String, knownLinks: [String]) async throws -> PlaceWebDetails {
        guard !apiKey.isEmpty else { throw PlaceCardsError.apiKeyMissing }

        let url = URL(string: "https://api.openai.com/v1/responses")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = trimmedAddress.isEmpty ? name : "\(name), \(trimmedAddress)"

        let body: [String: Any] = [
            "model": model,
            "input": webDetailsSearchPrompt(for: query, knownLinks: knownLinks),
            "tools": [["type": "web_search"]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw mapHTTPError(statusCode: http.statusCode, data: data, serviceLabel: "OpenAI")
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let output = json["output"] as? [[String: Any]],
            let messageItem = output.last(where: { ($0["type"] as? String) == "message" }),
            let content = messageItem["content"] as? [[String: Any]],
            let text = content.first(where: { ($0["type"] as? String) == "output_text" })?["text"] as? String
        else {
            throw PlaceCardsError.decodingError("OpenAI 응답을 해석할 수 없습니다.")
        }
        return try parseWebDetails(from: text)
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

    // `searchWebForDetails` is intentionally NOT overridden here — falls
    // through to `AIProvider`'s own "not supported" default. This used to
    // attach a *guessed* vendor-native hosted-search tool (Claude's
    // `web_search`, OpenAI's `web_search`) to the request, betting that a
    // gateway proxying a vendor's own model would recognize and forward
    // that vendor's own tool field. Confirmed wrong by an actual device
    // error: "API 오류 (400): ... tools.0.type: Input should be 'function'"
    // — this gateway's `/chat/completions` endpoint validates `tools`
    // strictly against the OpenAI Chat Completions *function-calling*
    // schema (every entry must be `{"type": "function", "function": {...}}`)
    // regardless of which vendor model is selected, and has no hosted
    // built-in search tool of its own at all. Implementing this for real
    // would mean defining an actual function tool, having the model request
    // a call, and this app performing a real web search itself to answer
    // it — a genuinely different, larger feature this app doesn't have the
    // pieces for yet, not a one-line fix.
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

    /// `analyzePlaces`' `generateContent` endpoint above no longer
    /// documents a Google Search grounding tool of its own — that's moved
    /// to Gemini's newer Interactions API (`POST /v1beta/interactions`,
    /// `tools: [{"type": "google_search"}]`), a different request/response
    /// shape entirely: `input` instead of `contents`/`parts`, and the
    /// model's answer lands in `steps[].content[].text` of whichever step
    /// has `"type": "model_output"` (searched from the end, same reasoning
    /// as `ClaudeProvider.searchWebForDetails`'s "last text block" — a
    /// tool-using interaction can carry more than one such step, and the
    /// final one is the actual answer).
    func searchWebForDetails(name: String, address: String, knownLinks: [String]) async throws -> PlaceWebDetails {
        guard !apiKey.isEmpty else { throw PlaceCardsError.apiKeyMissing }

        var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/interactions")
        components?.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components?.url else {
            throw PlaceCardsError.networkError("Gemini 요청 URL을 만들 수 없습니다.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = trimmedAddress.isEmpty ? name : "\(name), \(trimmedAddress)"

        let body: [String: Any] = [
            "model": model,
            "input": webDetailsSearchPrompt(for: query, knownLinks: knownLinks),
            "tools": [["type": "google_search"]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw mapHTTPError(statusCode: http.statusCode, data: data, serviceLabel: "Gemini")
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let steps = json["steps"] as? [[String: Any]]
        else {
            throw PlaceCardsError.decodingError("Gemini 응답을 해석할 수 없습니다.")
        }
        let text = steps
            .filter { ($0["type"] as? String) == "model_output" }
            .compactMap { step -> String? in
                (step["content"] as? [[String: Any]])?.last { ($0["type"] as? String) == "text" }?["text"] as? String
            }
            .last

        guard let text else {
            throw PlaceCardsError.decodingError("Gemini 응답을 해석할 수 없습니다.")
        }
        return try parseWebDetails(from: text)
    }
}
