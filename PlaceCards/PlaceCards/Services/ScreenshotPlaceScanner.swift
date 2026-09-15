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
    /// Reads every image and returns whatever places they show, in the
    /// order they were listed.
    ///
    /// Two shapes of screenshot, one rule. A map app's place screen shows
    /// exactly one place, with its title rendered larger than anything
    /// around it. A shared list — the kind that actually gets screenshotted
    /// off Instagram — shows six or twenty-five places, each at the *same*
    /// size, under a headline that is larger than all of them. Picking
    /// "the tallest line" therefore gets the map screen right and the list
    /// exactly backwards: it returns the headline, and one place where
    /// there are twenty-five.
    ///
    /// So the rule is the repetition, not the size: lines of a common
    /// height, repeated `minListItems` times or more, are a list. A
    /// headline is only ever one or two lines, so it can never win that
    /// test, and a map screen has no such repetition at all and falls
    /// through to the single-place reading.
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
        "기기에서 글자를 읽어 장소 이름을 찾았습니다. 나머지 정보는 Google 확인으로 채워집니다.".localized
    }

    /// Shown when recognition ran but nothing survived the filters below.
    /// Names the case this path is actually good at, and points at the AI
    /// key as the way to handle the rest — a dead end otherwise.
    static var emptyResultMessage: String {
        "사진에서 장소 이름을 읽지 못했습니다. 지도 앱의 장소 화면이나, 장소를 번호로 나열한 목록 이미지에서 가장 잘 동작합니다. 설정에서 AI 키를 등록하면 더 복잡한 사진도 읽을 수 있습니다.".localized
    }

    // MARK: - One image

    private static func extractPlaces(from imageData: Data) -> [AIAnalysisResult] {
        let lines = recognizeLines(in: imageData)
        guard !lines.isEmpty else { return [] }

        let body = lines.filter { !$0.isInStatusBar && !isNoise($0.text) }
        guard !body.isEmpty else { return [] }

        let addresses = body.filter { isAddress($0.text) }
        let candidates = body.filter { !isAddress($0.text) && isPlausibleName($0.text) }
        guard !candidates.isEmpty else { return [] }

        if let items = listItems(among: candidates) {
            return items.map { result(for: $0, addresses: addresses) }
        }
        guard let best = singlePlace(among: candidates) else { return [] }
        return [result(for: best, addresses: addresses)]
    }

    /// The repeated run of same-size lines that makes up a list, or `nil`
    /// when the image doesn't look like one.
    private static func listItems(among candidates: [TextLine]) -> [TextLine]? {
        // Walk from the tallest down, dropping each line into the first
        // group whose height it's within a band of. Two boxes of the same
        // rendered size never come back exactly equal, hence a band.
        var groups: [[TextLine]] = []
        for line in candidates.sorted(by: { $0.box.height > $1.box.height }) {
            if let index = groups.firstIndex(where: {
                abs(line.box.height - $0[0].box.height) <= $0[0].box.height * heightBand
            }) {
                groups[index].append(line)
            } else {
                groups.append([line])
            }
        }

        // Of the groups big enough to be a list, take the one set in the
        // largest type — not the one with the most lines. A card-style
        // list captions each place with two lines of description, so the
        // descriptions outnumber the names two to one and would win a
        // headcount outright; they are never the larger type, though.
        guard var items = groups.filter({ $0.count >= minListItems })
            .max(by: { $0[0].box.height < $1[0].box.height }) else { return nil }

        // The group was seeded by its tallest line, so a headline sitting
        // at the very edge of the band can have been swept in with it.
        // Re-centre on the median — the list is the majority, a headline
        // never more than a line or two — and re-filter tightly.
        let heights = items.map(\.box.height).sorted()
        let median = heights[heights.count / 2]
        items = items.filter { abs($0.box.height - median) <= median * heightBand * medianBandRatio }
        guard items.count >= minListItems else { return nil }

        // Ordered by the list's own numbering where it was read, so a
        // two-column list stays 1…13, 14…25 rather than zig-zagging across
        // the columns; by position otherwise.
        return items.sorted {
            let left = listMarkerNumber($0.text) ?? Int.max
            let right = listMarkerNumber($1.text) ?? Int.max
            if left != right { return left < right }
            if $0.box.maxY != $1.box.maxY { return $0.box.maxY > $1.box.maxY }
            return $0.box.minX < $1.box.minX
        }
    }

    /// A map app's place screen: the title is simply the biggest thing on
    /// it. Within the band the topmost wins, which is where a panel title
    /// sits relative to the category/rating row under it.
    private static func singlePlace(among candidates: [TextLine]) -> TextLine? {
        guard let tallest = candidates.map(\.box.height).max() else { return nil }
        return candidates
            .filter { $0.box.height >= tallest * (1 - heightBand) }
            .max { $0.box.maxY < $1.box.maxY }
    }

    private static func result(for line: TextLine, addresses: [TextLine]) -> AIAnalysisResult {
        var name = strippingListMarker(line.text).strippingTruncationEllipsis()
        var note: String?

        // "우래옥 — 을지로": a list that names a neighbourhood rather than
        // a street. Split on a spaced dash only, so a house number like
        // "3-8" is never mistaken for one.
        if let dash = name.range(of: dashSeparator, options: .regularExpression) {
            let head = String(name[..<dash.lowerBound]).trimmingCharacters(in: .whitespaces)
            let tail = String(name[dash.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !head.isEmpty, !tail.isEmpty {
                name = head
                note = tail
            }
        }

        // Only a line that actually parses as an address goes in the
        // address field, and a neighbourhood name does not. That is a
        // deliberate cost rule as much as a correctness one: a row with
        // both a name and an address is auto-verified against Google
        // (`autoVerifyUnambiguousRows`), which spends a geocode *and* a
        // search on it, and then filters the results to within
        // `maxAddressMatchDistanceMeters` of whatever the geocode
        // returned. Geocoding "을지로" lands somewhere along a kilometre
        // of street, so the real place is thrown out by that filter —
        // paying twice to end up with nothing. Carried as a note instead:
        // the user still sees it, and can search the row by hand.
        let address = note == nil
            ? nearestAddress(below: line, among: addresses)
            : nil

        return AIAnalysisResult(
            placeName: name,
            address: address,
            description: note,
            // Capped well below what a model reports for the same field:
            // this is a layout heuristic over recognized glyphs, not
            // something that understood the image, and `confidence` ends
            // up recorded on the card's own `SourceRecord`.
            confidence: min(maxReportedConfidence, Double(line.confidence)),
            // No semantic extraction here at all — and none needed: a
            // verified card gets its hours, phone, category and website
            // from the Google Places search response instead.
            details: nil
        )
    }

    /// The address line belonging to this item: the closest one sitting
    /// just under it and roughly sharing its left edge, so a grid of cards
    /// pairs each place with its own address instead of the first one on
    /// the screen.
    private static func nearestAddress(below line: TextLine, among addresses: [TextLine]) -> String? {
        addresses
            .filter {
                $0.box.maxY < line.box.minY
                    && line.box.minY - $0.box.maxY < line.box.height * addressSearchHeights
                    && abs($0.box.minX - line.box.minX) < addressColumnTolerance
            }
            .max { $0.box.maxY < $1.box.maxY }?
            .text
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
        "parking", "updates", "add", "edit",
        // Instagram's own furniture, which is in frame on every capture
        // taken from the app rather than from a map.
        "팔로우", "팔로잉", "좋아요", "답글", "답글 달기", "번역 보기", "원본 오디오",
        "게시물", "스토리", "릴스", "더 보기", "공유하기", "보관", "instagram",
        "follow", "following", "likes", "like", "reply", "translation",
        "see translation", "original audio", "posts", "reels", "story"
    ]

    /// Chrome that carries a trailing ellipsis or a count, so it never
    /// matches `chromeWords` exactly — "댓글 추가...", "좋아요 1,234개".
    private static let chromePrefixes = [
        "댓글 추가", "답글 달기", "번역 보기", "원본 오디오", "좋아요 ",
        "add a comment", "view all", "see all"
    ]

    private static func isNoise(_ text: String) -> Bool {
        if text.count < 2 { return true }
        let folded = text.lowercased()
        if chromeWords.contains(folded) { return true }
        if chromePrefixes.contains(where: folded.hasPrefix) { return true }
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
        // A 시/도 name followed by a 시/군/구. Both halves are needed: the
        // prefix alone also opens a headline ("제주 맛집 6곳", "서울 노포
        // 맛집 25") and a description ("제주 대표 고기국수 맛집"), and
        // reading those as addresses hid them from the name candidates.
        // Requiring the administrative token after it costs nothing —
        // a real street address that somehow omits 시/군/구 still matches
        // the 로/길 or 동/읍/면/리 rules above.
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
        + #"(특별시|광역시|특별자치시|특별자치도|자치도|도)?\s+\S*(시|군|구)\s"#

    private static func isPlausibleName(_ text: String) -> Bool {
        // Long enough to be worth searching for, short enough not to be a
        // sentence lifted off a caption or a review body. Measured after
        // the list marker comes off, so "① 담소요" isn't judged on glyphs
        // that are about to be thrown away.
        let stripped = strippingListMarker(text)
        return (minNameLength...maxNameLength).contains(stripped.count)
            && stripped.contains(where: \.isLetter)
    }

    // MARK: - List markers

    /// ①–⑳, ㉑–㉟, and the parenthesized ⑴–⒇ that recognition sometimes
    /// returns in place of a circled digit.
    private static let circledNumbers: [Character: Int] = {
        var map: [Character: Int] = [:]
        for index in 0..<20 {
            if let scalar = UnicodeScalar(0x2460 + index) { map[Character(scalar)] = index + 1 }
            if let scalar = UnicodeScalar(0x2474 + index) { map[Character(scalar)] = index + 1 }
        }
        for index in 0..<15 {
            if let scalar = UnicodeScalar(0x3251 + index) { map[Character(scalar)] = index + 21 }
        }
        return map
    }()

    /// The item's own number, when the list numbered itself in a form that
    /// survived recognition. Used only for ordering.
    private static func listMarkerNumber(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let first = trimmed.first, let number = circledNumbers[first] { return number }
        guard let match = trimmed.range(of: plainMarkerPattern, options: .regularExpression) else { return nil }
        return Int(trimmed[match].filter(\.isNumber))
    }

    private static func strippingListMarker(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespaces)
        if let first = trimmed.first, circledNumbers[first] != nil {
            trimmed.removeFirst()
        } else if let match = trimmed.range(of: plainMarkerPattern, options: .regularExpression) {
            trimmed.removeSubrange(match)
        } else if let first = trimmed.first, bulletMarkers.contains(first) {
            trimmed.removeFirst()
        }
        return trimmed.trimmingCharacters(in: .whitespaces)
    }

    private static let plainMarkerPattern = #"^\(?\d{1,2}[.)\]]"#
    private static let bulletMarkers: Set<Character> = ["•", "▪", "▶", "➡", "→", "*"]
    /// A dash with space on both sides. Unspaced dashes are left alone so
    /// a house number ("3-8") or a hyphenated name survives.
    private static let dashSeparator = #"\s+[—–-]\s+"#

    // MARK: - Tuning

    private static let preferredLanguages = ["ko-KR", "en-US"]
    private static let statusBarMinY: CGFloat = 0.96
    /// How far two lines' heights may differ and still count as the same
    /// size — Vision's boxes for identically rendered text vary by a few
    /// percent.
    private static let heightBand: CGFloat = 0.08
    /// The tighter band applied once a group is re-centred on its median.
    private static let medianBandRatio: CGFloat = 0.75
    /// Below this, repetition isn't evidence of a list — two same-size
    /// lines happen by chance on any screen.
    private static let minListItems = 3
    private static let addressSearchHeights: CGFloat = 2.5
    private static let addressColumnTolerance: CGFloat = 0.06
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
