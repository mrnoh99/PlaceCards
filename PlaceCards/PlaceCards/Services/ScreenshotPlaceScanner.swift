import CoreGraphics
import Foundation
import Vision

/// Reads a place name (and, when the screenshot shows one, an address) off
/// a map-app screenshot with Apple's on-device text recognition — no API
/// key, no network, no per-scan cost, on every device this app runs on.
///
/// This is deliberately *not* a replacement for `AIProvider`'s photo scan.
/// That one reads a dozen semantic fields (추천 메뉴, 수상, 태그 …) off the
/// same image and can pick several distinct places out of one Instagram
/// post; recognized text plus a layout heuristic can do neither. It is the
/// floor underneath it: without this, a user who hasn't registered an AI
/// key gets *nothing at all* from a screenshot, and that is most users —
/// the AI key is the one thing `OnboardingView` asks people to supply
/// themselves, and asking a general audience to create an API account is
/// where a first run gets abandoned.
///
/// What makes so low a bar good enough is that **this scan's output is not
/// trusted as-is.** Every row it produces goes through exactly the same
/// Google Places verification the AI path's rows do
/// (`autoVerifyUnambiguousRows` → `search(rowID:)`, which matches on name
/// *and* address proximity before confirming anything), and a verified
/// match brings back the rating, review count, category, phone, website,
/// photo and — since the Text Search field mask started asking for
/// `regularOpeningHours` — the opening hours too. So this only has to
/// produce a plausible *name*: Google supplies the rest of the card, and a
/// name Google can't find leaves the row visible for the user to fix by
/// hand, the same as any unresolved AI row.
enum ScreenshotPlaceScanner {
    /// One place per image, never one per large text block: a map app's
    /// place screen shows exactly one place, and people screenshot places
    /// one at a time. Handing three screenshots over therefore yields up
    /// to three rows — the same shape `analyzeImages` already expects —
    /// while a single image never produces the pile of half-read map
    /// labels that "every big line is a place" would.
    ///
    /// Vision's own work happens off the main actor: recognition on a
    /// full-resolution screenshot is tens of milliseconds to a few hundred,
    /// long enough to drop frames if it ran where `analyzeImages` is
    /// suspended.
    static func extractPlaces(imageDatas: [Data]) async -> [AIAnalysisResult] {
        await Task.detached(priority: .userInitiated) {
            imageDatas.compactMap(Self.extractPlace(from:))
        }.value
    }

    /// Shown once after a successful on-device scan. Says both what just
    /// happened and what happens next, because the result genuinely is
    /// thinner than an AI scan's and the user should not be left thinking
    /// a half-filled card is all they get.
    static var resultNote: String {
        "기기에서 글자를 읽어 장소 이름을 찾았습니다. 나머지 정보는 Google 확인으로 채워집니다.".localized
    }

    /// Shown when recognition ran but nothing survived the filters below.
    /// Names the case this path is actually good at, and points at the AI
    /// key as the way to handle the rest — a dead end otherwise.
    static var emptyResultMessage: String {
        "사진에서 장소 이름을 읽지 못했습니다. 지도 앱의 장소 화면을 찍은 스크린샷에서 가장 잘 동작합니다. 설정에서 AI 키를 등록하면 인스타그램 게시물 같은 사진에서도 찾을 수 있습니다.".localized
    }

    // MARK: - One image

    private static func extractPlace(from imageData: Data) -> AIAnalysisResult? {
        let lines = recognizeLines(in: imageData)
        guard !lines.isEmpty else { return nil }

        let body = lines.filter { !$0.isInStatusBar && !isNoise($0.text) }
        guard !body.isEmpty else { return nil }

        let address = body.first { isAddress($0.text) }?.text
        let nameCandidates = body.filter { !isAddress($0.text) && isPlausibleName($0.text) }
        guard let tallest = nameCandidates.map(\.box.height).max() else { return nil }

        // A place screen renders its title larger than everything around
        // it, so height is the signal — but two boxes of the same rendered
        // size never come back exactly equal, hence a band rather than
        // `== tallest`. Within the band the topmost wins, which is where a
        // panel title sits relative to the category/rating row under it.
        let sameSize = nameCandidates.filter { $0.box.height >= tallest * heightBandRatio }
        guard let best = sameSize.max(by: { $0.box.maxY < $1.box.maxY }) else { return nil }

        return AIAnalysisResult(
            placeName: best.text.strippingTruncationEllipsis(),
            address: address,
            description: nil,
            // Capped well below what a model reports for the same field:
            // this is a layout heuristic over recognized glyphs, not
            // something that understood the image, and `confidence` ends
            // up recorded on the card's own `SourceRecord`.
            confidence: min(maxReportedConfidence, Double(best.confidence)),
            // No semantic extraction here at all — and none needed: a
            // verified card gets its hours, phone, category and website
            // from the Google Places search response instead.
            details: nil
        )
    }

    // MARK: - Recognition

    private struct TextLine {
        let text: String
        /// Vision's normalized box — origin *bottom*-left, so `maxY` near
        /// 1 is the top of the screenshot, not the bottom.
        let box: CGRect
        let confidence: Float

        /// The clock/battery/carrier strip. Its own text is filtered by
        /// `isNoise` anyway (a clock has no letters), but a carrier name
        /// is letters at a readable size and would otherwise compete.
        var isInStatusBar: Bool { box.minY > ScreenshotPlaceScanner.statusBarMinY }
    }

    private static func recognizeLines(in imageData: Data) -> [TextLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Off on purpose. Language correction exists to fix ordinary
        // words, and every string this cares about is a proper noun —
        // correction is precisely the thing that would turn a brand name
        // into the dictionary word it resembles.
        request.usesLanguageCorrection = false
        // Korean text recognition exists from iOS 16 on, but asking for a
        // language the installed revision doesn't support throws at
        // `perform` time and would take the whole scan down with it, so
        // the list is intersected with what this device actually offers
        // rather than assumed.
        if let supported = try? request.supportedRecognitionLanguages() {
            let wanted = preferredLanguages.filter { supported.contains($0) }
            if !wanted.isEmpty { request.recognitionLanguages = wanted }
        }

        let handler = VNImageRequestHandler(data: imageData, options: [:])
        guard (try? handler.perform([request])) != nil else { return [] }

        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            // Same invisible-bidi-mark strip every other externally
            // sourced string in this app gets — see
            // `String.strippingInvisibleFormatCharacters()`.
            let text = candidate.string
                .strippingInvisibleFormatCharacters()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return TextLine(text: text, box: observation.boundingBox, confidence: candidate.confidence)
        }
    }

    // MARK: - Filters

    /// Text belonging to the map app's own chrome rather than to the place.
    /// Matched whole-string against a case-folded line, so a place whose
    /// name merely *contains* one of these keeps it; only a line that is
    /// nothing but the word is dropped.
    private static let chromeWords: Set<String> = [
        "저장", "저장됨", "공유", "길찾기", "출발", "도착", "리뷰", "리뷰쓰기",
        "사진", "예약", "전화", "홈", "검색", "지도", "주변", "즐겨찾기",
        "더보기", "정보", "메뉴", "영업시간", "편의시설", "위치", "상세정보",
        "완료", "취소", "닫기", "목록", "내비게이션", "거리뷰", "블로그",
        "쿠폰", "주차", "문의", "길안내", "영업 중", "영업중", "영업 종료",
        "영업종료", "오늘", "지금 영업 중",
        "save", "saved", "share", "directions", "start", "review", "reviews",
        "photo", "photos", "call", "website", "menu", "home", "search",
        "nearby", "overview", "about", "book", "order", "more", "done",
        "cancel", "close", "list", "open", "closed", "open now", "hours",
        "parking", "updates", "add", "edit"
    ]

    private static func isNoise(_ text: String) -> Bool {
        if text.count < 2 { return true }
        if chromeWords.contains(text.lowercased()) { return true }
        // Ratings ("4.5"), review counts ("(1,234)"), phone numbers, prices
        // in figures, the status-bar clock — anything with no letter in it
        // at all is never a place name.
        if !text.contains(where: \.isLetter) { return true }
        // A leading clock/opening time, e.g. "09:00 - 22:00", "오후 9:41".
        if text.range(of: #"^(오전|오후)?\s?\d{1,2}:\d{2}"#, options: .regularExpression) != nil { return true }
        // A distance chip: "1.2 km", "350m".
        if text.range(of: #"^\d+(\.\d+)?\s?(m|km|mi|ft)$"#, options: [.regularExpression, .caseInsensitive]) != nil { return true }
        // "리뷰 1,234", "후기 52" — a count row, not a name.
        if text.range(of: #"^(리뷰|후기|방문자리뷰|블로그리뷰)\s?\d"#, options: .regularExpression) != nil { return true }
        return false
    }

    /// A line that reads like a street address rather than a name. Checked
    /// before the name is picked, because a Naver/Kakao info card renders
    /// its address at nearly the size of its title and would otherwise win
    /// the height contest outright on some layouts.
    private static func isAddress(_ text: String) -> Bool {
        // 도로명 ("…대로 152", "…4길 7") and 지번 ("…동 100-1").
        if text.range(of: #"[가-힣A-Za-z0-9]\s?(로|길)\s?\d"#, options: .regularExpression) != nil { return true }
        if text.range(of: #"[가-힣]{2,}(동|읍|면|리)\s?\d"#, options: .regularExpression) != nil { return true }
        // A 시/도 name *at a word boundary* — the suffix-or-space is what
        // keeps a restaurant called "광주해장국" from reading as a Gwangju
        // address.
        if text.range(of: administrativePrefixPattern, options: .regularExpression) != nil { return true }
        // "12 Baker Street", "500 Terry Francois Blvd"
        if text.range(
            of: #"^\d+\s+\S+.*\b(st|street|rd|road|ave|avenue|blvd|boulevard|ln|lane|dr|drive)\b\.?$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil { return true }
        return false
    }

    private static let administrativePrefixPattern =
        #"^(서울|부산|대구|인천|광주|대전|울산|세종|경기|강원|충북|충남|전북|전남|경북|경남|제주)"#
        + #"(특별시|광역시|특별자치시|특별자치도|자치도|도|시)?[\s,]"#

    private static func isPlausibleName(_ text: String) -> Bool {
        // Long enough to be worth searching for, short enough not to be a
        // sentence lifted off a caption or a review body.
        (minNameLength...maxNameLength).contains(text.count) && text.contains(where: \.isLetter)
    }

    // MARK: - Tuning

    private static let preferredLanguages = ["ko-KR", "en-US"]
    private static let statusBarMinY: CGFloat = 0.96
    private static let heightBandRatio: CGFloat = 0.92
    private static let maxReportedConfidence = 0.6
    private static let minNameLength = 2
    private static let maxNameLength = 40
}

private extension String {
    /// A map app truncates a long title in place ("스타벅스 강남대로…"),
    /// and the ellipsis it draws is recognized as text. Left on, it goes
    /// into the Google Places query verbatim and costs the match.
    func strippingTruncationEllipsis() -> String {
        var trimmed = self
        while let last = trimmed.last, last == "…" || last == "." {
            trimmed.removeLast()
        }
        return trimmed.trimmingCharacters(in: .whitespaces)
    }
}
