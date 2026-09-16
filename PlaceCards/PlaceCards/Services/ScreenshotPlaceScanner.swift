import CoreGraphics
import Foundation
import Vision

/// Reads places off a screenshot with Apple's on-device text recognition —
/// no API key, no network, no per-scan cost, on every device this app runs
/// on. The fallback for a user who hasn't registered an AI key, which is
/// most users: the AI key is the one thing `OnboardingView` asks people to
/// supply themselves, and asking a general audience to create an API
/// account is where a first run gets abandoned.
///
/// **This scan requires a visible address.** It finds the address first and
/// works back to the name, rather than guessing at the name by its size —
/// and when an image has no address in it, it returns nothing at all and
/// says so, instead of returning a guess.
///
/// That is a deliberate narrowing, measured rather than assumed. The
/// earlier version picked "the tallest line" on a single-place screen and
/// "the repeated run of same-size lines" for a list. Against eleven real
/// screenshots (Instagram place posts, a Blue Ribbon table, a numbered
/// Incheon list) both rules lost to the same three failures:
///
/// * A line holding **both** a name and an address (`함흥곰보냉면 | 안양시
///   동안구 귀인로190번길 23`) was classified as an address outright, so the
///   name vanished and the marketing blurb under it won the size contest
///   instead. That shape is the *best* input this scanner gets, and it was
///   the one it handled worst.
/// * A table's middle column (`커피전문점`, `소갈비`) is the same size as
///   the name column, so size cannot separate them.
/// * A list's category badge (`쫄볶이`, `메밀우동`) sits directly above the
///   address, so walking upward by position alone picks the badge.
///
/// All three are decided by **where the text sits**, not by how big it is,
/// which is why the rules below work in row/column terms. Vision hands back
/// a `boundingBox` per observation; a table's columns and a list's rows are
/// plainly separated in it.
///
/// What is left to the AI path (`AIProvider`) is everything without an
/// address: an Instagram list that names places and nothing else, a caption
/// full of hashtags, signage photographed inside a picture. Recognized
/// glyphs plus a layout rule cannot tell a restaurant's name from a
/// headline there, and a wrong card costs the user more than an honest
/// empty-handed message.
///
/// The names this does produce are still not trusted as-is. Every row goes
/// through the same Google Places verification the AI path's rows do
/// (`autoVerifyUnambiguousRows` → `search(rowID:)`, matching on name *and*
/// address proximity), and now actually reaches it: that check requires a
/// row to carry both a name and an address, which is exactly the pair this
/// produces.
enum ScreenshotPlaceScanner {
    /// Reads every image and returns whatever places they show, in the
    /// order they were listed.
    ///
    /// Vision's own work happens off the main actor: recognition on a
    /// full-resolution screenshot is tens of milliseconds to a few hundred,
    /// long enough to drop frames if it ran where `analyzeImages` is
    /// suspended.
    static func extractPlaces(imageDatas: [Data]) async -> [AIAnalysisResult] {
        await Task.detached(priority: .userInitiated) {
            imageDatas.flatMap(Self.extractPlaces(from:))
        }.value
    }

    /// Shown once after a successful on-device scan. Says both what just
    /// happened and what happens next, because the result genuinely is
    /// thinner than an AI scan's and the user should not be left thinking
    /// a half-filled card is all they get.
    static var resultNote: String {
        "기기에서 글자를 읽어 장소 이름과 주소를 찾았습니다. 나머지 정보는 Google 확인으로 채워집니다.".localized
    }

    /// Shown when recognition ran but no address was found. Names the one
    /// thing that decides whether this path can work at all — the old text
    /// pointed at "지도 앱의 장소 화면이나 번호 목록", which is not the
    /// distinction that matters and left users retrying shapes that could
    /// never succeed.
    static var emptyResultMessage: String {
        "사진에서 주소를 찾지 못했습니다. 기기 내 읽기는 가게 이름과 주소가 함께 보이는 사진에서만 동작합니다. 주소가 없는 목록 이미지는 설정에서 AI 키를 등록하면 읽을 수 있습니다.".localized
    }

    // MARK: - One image

    private static func extractPlaces(from imageData: Data) -> [AIAnalysisResult] {
        let lines = recognizeLines(in: imageData).filter { !$0.isInStatusBar }
        guard !lines.isEmpty else { return [] }
        return places(in: rows(of: lines))
    }

    /// Recognized lines grouped into visual rows, ordered top to bottom and
    /// each ordered left to right.
    ///
    /// Two observations belong to the same row when their vertical centres
    /// are within most of a line height of each other. Vision reports a
    /// table's cells and a list item's name-plus-badge at very slightly
    /// different `y` even when they are drawn on one line, so an exact
    /// comparison would split every row it is meant to join.
    private static func rows(of lines: [TextLine]) -> [[TextLine]] {
        // `maxY` near 1 is the *top* of the image (Vision's origin is
        // bottom-left), so descending `midY` reads down the page.
        let ordered = lines.sorted { $0.box.midY > $1.box.midY }
        var grouped: [[TextLine]] = []
        var current: [TextLine] = [ordered[0]]
        for line in ordered.dropFirst() {
            guard let reference = current.first else { continue }
            let tolerance = max(reference.box.height, line.box.height) * rowTolerance
            if abs(line.box.midY - reference.box.midY) <= tolerance {
                current.append(line)
            } else {
                grouped.append(current.sorted { $0.box.minX < $1.box.minX })
                current = [line]
            }
        }
        grouped.append(current.sorted { $0.box.minX < $1.box.minX })
        return grouped
    }

    /// One result per row that contains an address, with the name resolved
    /// by the three rules below in order.
    private static func places(in rows: [[TextLine]]) -> [AIAnalysisResult] {
        var results: [AIAnalysisResult] = []
        // A row already spent as some place's name can't be reused as the
        // next one's — without this a run of rows whose own name failed to
        // recognize all fall back onto the same line above them.
        var claimed = Set<Int>()

        for (index, row) in rows.enumerated() {
            guard let anchor = row.first(where: { AddressPattern.match(in: $0.text) != nil }),
                  let address = AddressPattern.match(in: anchor.text) else { continue }

            // 1. A column to the left of the address, on the same row —
            //    a table ("가보정 | 소갈비 | 수원시 팔달구 장다리로 282")
            //    or a list item whose badge sits to the right of its name.
            //    The gap requirement keeps a name that merely shares the
            //    address's own cell out of this rule.
            var name = row
                .first { $0.box.maxX < anchor.box.minX - columnGap }
                .flatMap { PlaceName.from($0.text) }

            // 2. The part of the address's own line that precedes it —
            //    "함흥곰보냉면 | 안양시 동안구 귀인로190번길 23". Text after
            //    a location marker ("◎안양시 …") is an ad line, not a name.
            if name == nil {
                let head = String(anchor.text[..<address.range.lowerBound])
                if head.rangeOfCharacter(from: Self.locationMarkers) == nil {
                    name = PlaceName.from(head)
                }
            }

            // 3. The nearest row above that reads like a name — a list
            //    laid out vertically ("마부시" over its address).
            //
            //    Known limitation: a map app's place screen puts a
            //    category line between the title and the address ("스타벅스
            //    강남대로점" / "카페" / "서울 강남구 강남대로 390"), and this
            //    picks "카페". Preferring the *tallest* candidate above
            //    instead fixes that one and breaks a numbered list, whose
            //    section headline ("인천") is set larger than any of its
            //    items — so nearest wins, measured on both. The row still
            //    carries the right address, so Google's own verification
            //    declines to confirm it and leaves it for the user rather
            //    than saving a wrong card.
            if name == nil {
                for above in stride(from: index - 1, through: 0, by: -1) where !claimed.contains(above) {
                    var candidate: String?
                    for line in rows[above] where AddressPattern.match(in: line.text) == nil {
                        if let resolved = PlaceName.from(line.text) {
                            candidate = resolved
                            break
                        }
                    }
                    guard let candidate else { continue }
                    name = candidate
                    claimed.insert(above)
                    break
                }
            }

            guard let placeName = name else { continue }
            results.append(
                AIAnalysisResult(
                    placeName: placeName,
                    address: address.text,
                    description: nil,
                    // Capped well below what a model reports for the same
                    // field: this is a layout rule over recognized glyphs,
                    // not something that understood the image, and
                    // `confidence` ends up recorded on the card's own
                    // `SourceRecord`.
                    confidence: min(maxReportedConfidence, Double(anchor.confidence)),
                    // No semantic extraction here at all — and none needed:
                    // a verified card gets its hours, phone, category and
                    // website from the Google Places search response.
                    details: nil
                )
            )
        }
        return results
    }

    // MARK: - Recognition

    private struct TextLine {
        let text: String
        /// Vision's normalized box — origin *bottom*-left, so `maxY` near
        /// 1 is the top of the screenshot, not the bottom.
        let box: CGRect
        let confidence: Float

        /// The clock/battery/carrier strip, which is letters at a readable
        /// size and would otherwise compete with the page's own text.
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

    // MARK: - Tuning

    private static let preferredLanguages = ["ko-KR", "en-US"]
    private static let statusBarMinY: CGFloat = 0.96
    /// How far two lines' vertical centres may differ, as a share of the
    /// taller one's height, and still count as the same row.
    private static let rowTolerance: CGFloat = 0.8
    /// The clear space that has to separate a left-hand column from the
    /// address column, as a share of image width — wide enough that words
    /// inside one cell are never read as two columns.
    private static let columnGap: CGFloat = 0.05
    private static let maxReportedConfidence = 0.6
    /// Symbols a caption uses to introduce an address ("◎안양시 만안구 …").
    /// Whatever precedes one is ad copy, not a name.
    private static let locationMarkers = CharacterSet(charactersIn: "◎◉📍🏠⌂")
}

// MARK: - Address

/// Finds a Korean address inside a line, and says *where* it starts.
///
/// Knowing the position is the whole point: the previous version only
/// asked whether a line contained an address, and a line holding a name
/// and an address together ("함흥곰보냉면 | 안양시 동안구 귀인로190번길
/// 23") was therefore discarded whole, taking the name with it.
private enum AddressPattern {
    struct Match {
        let text: String
        let range: Range<String.Index>
    }

    /// The most specific pattern that matches wins, and within it the
    /// longest match — a short 로/길 fragment would otherwise beat the
    /// full "시 구 로 번지" form that surrounds it and leave the leading
    /// "안양시 동안구" stranded outside the address, where it reads as a
    /// name.
    static func match(in text: String) -> Match? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let full = NSRange(text.startIndex..., in: text)
            let longest = regex.matches(in: text, range: full)
                .compactMap { Range($0.range, in: text) }
                .max { text[$0].count < text[$1].count }
            if let longest {
                return Match(
                    text: String(text[longest]).trimmingCharacters(in: .whitespaces),
                    range: longest
                )
            }
        }
        return nil
    }

    private static let sido =
        "(?:서울|부산|대구|인천|광주|대전|울산|세종|경기|강원|충북|충남|전북|전남|경북|경남|제주)"
        + "(?:특별시|광역시|특별자치시|특별자치도|자치도|도)?"
    /// One or two 시/군/구 levels ("안양시 동안구"), optionally followed by
    /// a 읍/면 ("여주시 강천면"). 읍/면 is only allowed *after* a 시/군/구
    /// on purpose: matched on its own, the 면 in "평양냉면" reads as an
    /// administrative district and swallows the dish name into the address.
    private static let district = "(?:[가-힣]+(?:시|군|구)\\s+){1,2}(?:[가-힣]+(?:읍|면)\\s+)?"

    private static let patterns = [
        // 도로명 — "안양시 동안구 관악대로 415", "고양시 일산서구 호수로856번길 7-7"
        "(?:\(sido)\\s+)?\(district)\\S*[가-힣0-9]+(?:대로|로|길)\\s?\\d+(?:-\\d+)?(?:번길\\s?\\d+)?",
        // 지번 — "남동구 논현동 450", "경기 안양시 동안구 관양동 1591-11"
        "(?:\(sido)\\s+)?\(district)[가-힣]+(?:동|읍|면|리)\\s?\\d+(?:-\\d+)?",
        // 시/군/구 없이 도로명만 보이는 줄
        "[가-힣0-9]+(?:대로|로|길)\\s?\\d+(?:-\\d+)?",
        "[가-힣]{2,}(?:동|읍|면|리)\\s?\\d+(?:-\\d+)?"
    ]
}

// MARK: - Name

/// Turns one recognized line into a usable place name, or rejects it.
private enum PlaceName {
    static func from(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // A hashtag line is ad copy ("#줄서서 먹는 탕수육,짬뽕맛집"), never
        // the name itself.
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
        // A quoted run *is* the name when the line wraps one —
        // "인덕원 '비소원'" names 비소원, with 인덕원 as the neighbourhood.
        if let quoted = quotedName(in: trimmed) { return quoted }

        let cleaned = strippingDecoration(trimmed)
        guard (minLength...maxLength).contains(cleaned.count),
              cleaned.contains(where: \.isLetter),
              !isSentence(cleaned),
              !chromeWords.contains(cleaned.lowercased()),
              !isAdministrativeFragment(cleaned)
        else { return nil }
        return cleaned
    }

    /// Leading and trailing symbols, emoji and separators come off —
    /// "스시미우 ♬★.˚" goes into a Google query verbatim otherwise, and
    /// nothing matches it. Letters and digits inside are untouched.
    private static func strippingDecoration(_ text: String) -> String {
        var trimmed = text[...]
        while let first = trimmed.first, !first.isLetter, !first.isNumber { trimmed = trimmed.dropFirst() }
        while let last = trimmed.last, !last.isLetter, !last.isNumber { trimmed = trimmed.dropLast() }
        var result = String(trimmed).trimmingCharacters(in: .whitespaces)
        // A branch suffix loses its closing bracket to the pass above —
        // "노티드 (도산점)" would leave "노티드 (도산점". Put it back rather
        // than carry an unbalanced one into the query.
        for (opener, closer) in [("(", ")"), ("（", "）")]
        where result.components(separatedBy: opener).count > result.components(separatedBy: closer).count {
            result += closer
        }
        return result
    }

    private static func quotedName(in text: String) -> String? {
        guard let range = text.range(of: quotedPattern, options: .regularExpression) else { return nil }
        let inner = text[range].dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
        return inner.isEmpty ? nil : inner
    }

    /// A marketing blurb rather than a name. Across eleven real
    /// screenshots every actual business name held at most one space
    /// ("우판등심 인천점", "인덕원 '비소원'") while every caption line held
    /// three or more ("쫄깃한 냉면과 깊은 맛의 손만두가 환상의 조화를 이루는
    /// 맛집"), so this separates them cleanly and still leaves room for an
    /// English name like "Blue Bottle Coffee".
    private static func isSentence(_ text: String) -> Bool {
        text.filter(\.isWhitespace).count >= maxSpacesInName + 1
    }

    /// What is left over when an address's leading district doesn't make it
    /// into the match — "안양시 동안구", "경기". Only ever applied to two or
    /// more tokens, plus a bare 시도 name: a single token is checked no
    /// further, because "함흥곰보냉면", "마부시" and "양수면옥" all end in an
    /// administrative suffix and are perfectly good names.
    private static func isAdministrativeFragment(_ text: String) -> Bool {
        if text.range(of: "^\(bareSido)$", options: .regularExpression) != nil { return true }
        let tokens = text.split(separator: " ")
        guard tokens.count >= 2 else { return false }
        return tokens.allSatisfy {
            String($0).range(of: districtTokenPattern, options: .regularExpression) != nil
        }
    }

    private static let quotedPattern = "['\"\u{2018}\u{2019}\u{201C}\u{201D}][^'\"\u{2018}\u{2019}\u{201C}\u{201D}]{2,20}['\"\u{2018}\u{2019}\u{201C}\u{201D}]"
    private static let bareSido =
        "(?:서울|부산|대구|인천|광주|대전|울산|세종|경기|강원|충북|충남|전북|전남|경북|경남|제주)"
        + "(?:특별시|광역시|특별자치시|특별자치도|자치도|도)?"
    private static let districtTokenPattern = "^(?:\(bareSido)|[가-힣]+(?:시|군|구|동|읍|면|리))$"

    private static let minLength = 2
    private static let maxLength = 40
    private static let maxSpacesInName = 2

    /// App furniture that sits at name-like size and would otherwise be
    /// picked up by the backtracking rule. Matched whole-string against a
    /// case-folded line, so a place whose name merely *contains* one of
    /// these keeps it.
    private static let chromeWords: Set<String> = [
        "저장", "저장됨", "공유", "길찾기", "출발", "도착", "리뷰", "리뷰쓰기",
        "사진", "예약", "전화", "홈", "검색", "지도", "주변", "즐겨찾기",
        "더보기", "정보", "메뉴", "영업시간", "편의시설", "위치", "상세정보",
        "완료", "취소", "닫기", "목록", "내비게이션", "거리뷰", "블로그",
        "쿠폰", "주차", "문의", "길안내", "영업 중", "영업중", "영업 종료",
        "영업종료", "오늘", "지금 영업 중", "식당이름", "음식종류", "지역",
        "save", "saved", "share", "directions", "start", "review", "reviews",
        "photo", "photos", "call", "website", "menu", "home", "search",
        "nearby", "overview", "about", "book", "order", "more", "done",
        "cancel", "close", "list", "open", "closed", "open now", "hours",
        "parking", "updates", "add", "edit",
        // Instagram's own furniture, in frame on every capture taken from
        // the app rather than from a map.
        "팔로우", "팔로잉", "좋아요", "답글", "답글 달기", "번역 보기", "원본 오디오",
        "게시물", "스토리", "릴스", "더 보기", "공유하기", "보관", "instagram",
        "follow", "following", "likes", "like", "reply", "translation",
        "see translation", "original audio", "posts", "reels", "story"
    ]
}
