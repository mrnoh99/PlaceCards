import Foundation

/// 카카오맵 공유(짧은 링크 `kko.to/…`)에서 이름·주소·좌표를 복구한다.
///
/// **왜 한 번에 안 되는가.** 카카오맵 공유는 짧은 링크(`kko.to/…`)고, 그게
/// HTTP 301로 넘어가는 곳은 `applink.map.kakao.com/place?id=…`인데 이건 앱
/// 설치를 유도하는 인터스티셜 페이지라 실제 장소 이름은 자바스크립트가
/// 그 뒤에 채운다 — `og:title`을 크롤러 UA로 읽어도 늘 "카카오맵"뿐이다
/// (실측: `kko.to/P84cAc9RFm` → 301 → 저 applink URL, 2026-09-23).
///
/// **왜 이게 되는가.** applink URL 자체의 쿼리에 `id=`로 장소 고유 번호가
/// 그대로 실려 있다. 그 번호로 `https://place.map.kakao.com/{id}`를 직접
/// 만들면 이건 서버가 완성된 HTML을 주는 옛 방식 페이지고, `og:title`이
/// 장소 이름, `og:description`이 주소, `twitter:image`의 정적 지도 URL이
/// `m=<경도>,<위도>`로 좌표까지 들고 있다. 전부 위 실측 링크를 그대로
/// 열어서 확인했다 — 짐작이 아니다(`CLAUDE.md` §4).
///
/// 카카오 Local API는 안 쓴다(`SourceType.kakaoDirectLookup`의 주석 참고 —
/// 결과를 저장하는 게 그 API 약관에 걸린다). 여기서 읽는 것은 카카오맵이
/// 공유 미리보기(카카오톡 등)를 위해 누구에게나 내주는 `og:`/`twitter:`
/// 메타 태그뿐이라, `WebsiteBusinessInfoFetcher`가 아무 웹사이트에나 하는
/// 것과 같은 종류의 일이다.
enum KakaoPlaceLinkResolver {
    /// 실제로 확인된 카카오맵 공유 호스트만 인식한다. `map.kakao.com`
    /// 자체 같은 다른 카카오 URL은 실물을 본 적이 없어서 넣지 않는다.
    static func isKakaoMapShareURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "kko.to" || host.hasSuffix(".map.kakao.com")
    }

    /// applink 인터스티셜의 `og:title`. 이게 나오면 아직 진짜 장소 페이지를
    /// 못 찾은 것이라 실패로 친다 — 이걸 그대로 이름으로 쓰면 카카오맵으로
    /// 공유된 모든 카드의 이름이 전부 "카카오맵"이 된다.
    private static let placeholderTitle = "카카오맵"

    static func resolve(_ url: URL, session: URLSession = .shared) async -> ParsedSharedPlace? {
        guard let placeURL = await canonicalPlaceURL(for: url, session: session),
              let html = await LinkMetadataFetcher.fetchHTML(for: placeURL, session: session) else {
            return nil
        }
        guard let name = metaProperty("og:title", from: html)?
                .trimmingCharacters(in: .whitespacesAndNewlines).strippingInvisibleFormatCharacters(),
              !name.isEmpty, name != placeholderTitle else {
            return nil
        }
        let address = metaProperty("og:description", from: html)?
            .trimmingCharacters(in: .whitespacesAndNewlines).strippingInvisibleFormatCharacters()
        return ParsedSharedPlace(
            name: name,
            address: (address?.isEmpty ?? true) ? nil : address,
            coordinates: coordinates(fromTwitterImageIn: html),
            note: nil,
            url: placeURL,
            source: .kakaoMapShare
        )
    }

    /// `place.map.kakao.com/{id}`를 만든다. 입력이 이미 그 모양이거나
    /// `id=`를 쿼리로 들고 있으면(applink URL) 네트워크 없이 바로 만든다.
    /// 그것도 아니면(짧은 링크) 한 번 따라가 리다이렉트가 도착한 곳에서
    /// 다시 읽는다.
    private static func canonicalPlaceURL(for url: URL, session: URLSession) async -> URL? {
        if let id = placeID(from: url) {
            return placeURL(id: id)
        }
        // 짧은 링크는 HTTP 301로 applink URL까지만 간다 — `URLSession`이
        // 그 리다이렉트는 따라가 주지만, 그다음은 자바스크립트 라우팅이라
        // 프로토콜 리다이렉트가 없다. 리다이렉트가 실제로 도착한 곳
        // (`finalURL`)에서 한 번 더 id를 읽는다.
        guard let metadata = await LinkMetadataFetcher.fetchMetadata(for: url, session: session),
              let id = placeID(from: metadata.finalURL) else {
            return nil
        }
        return placeURL(id: id)
    }

    /// `place.map.kakao.com/{id}`(경로)와 `applink.map.kakao.com/place?id={id}`
    /// (쿼리) 양쪽에서 다 읽는다 — 실제로 앞엣것으로 바로 공유되는 경우도
    /// 있어서다.
    private static func placeID(from url: URL) -> String? {
        if url.host?.lowercased() == "place.map.kakao.com" {
            let id = url.lastPathComponent
            return id.isEmpty ? nil : id
        }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "id" })?.value
    }

    private static func placeURL(id: String) -> URL? {
        URL(string: "https://place.map.kakao.com/\(id)")
    }

    /// `<meta property="…" content="…">`를 속성 순서 상관없이 읽는다 —
    /// `LinkMetadataFetcher.extractOGProperty`와 같은 모양이지만 그쪽은
    /// `private`라 여기서 다시 쓴다.
    private static func metaProperty(_ property: String, from html: String) -> String? {
        firstMatch(
            in: html,
            pattern: #"<meta[^>]*property=["']"# + property + #"["'][^>]*content=["']([^"']*)["']"#
        ) ?? firstMatch(
            in: html,
            pattern: #"<meta[^>]*content=["']([^"']*)["'][^>]*property=["']"# + property + #"["']"#
        )
    }

    /// `<meta name="twitter:image" content="…staticmap…&m=<경도>,<위도>">`의
    /// `m=` 값. 정적 지도 이미지 URL이 좌표를 그대로 들고 있는 게 이 페이지
    /// 에서 좌표를 얻을 수 있는 유일한 길이다 — `og:`에는 좌표가 없다.
    private static func coordinates(fromTwitterImageIn html: String) -> Coordinates? {
        guard let imageURLString = firstMatch(
            in: html,
            pattern: #"<meta[^>]*name=["']twitter:image["'][^>]*content=["']([^"']*)["']"#
        ) ?? firstMatch(
            in: html,
            pattern: #"<meta[^>]*content=["']([^"']*)["'][^>]*name=["']twitter:image["']"#
        ), let components = URLComponents(string: imageURLString),
        let raw = components.queryItems?.first(where: { $0.name == "m" })?.value else {
            return nil
        }
        let parts = raw.split(separator: ",")
        guard parts.count == 2, let longitude = Double(parts[0]), let latitude = Double(parts[1]) else {
            return nil
        }
        return Coordinates(latitude: latitude, longitude: longitude)
    }

    private static func firstMatch(in html: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let group = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[group])
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
