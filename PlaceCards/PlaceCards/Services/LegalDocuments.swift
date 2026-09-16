import Foundation

/// The privacy policy and the terms of service, as text the app can show
/// without a network connection or a hosted page.
///
/// Carried in full here, rather than as a link, for two reasons. The App
/// Store requires a reachable policy URL, but a link is the one form of
/// disclosure that fails exactly when someone goes looking for it — on a
/// plane, behind a captive portal, after the page moves. And the fact
/// most worth disclosing (an AI scan uploads the chosen image to whichever
/// provider the user configured) is something they should be able to check
/// from inside the screen that offers the scan. `PRIVACY_POLICY.md` and
/// `TERMS_OF_SERVICE.md` at the repository root carry the same text for
/// hosting; changing one means changing the other.
///
/// Deliberately *not* routed through `String.localized`. That dictionary
/// exists for UI chrome — short strings, one line, looked up by their own
/// Korean text as the key. Whole paragraphs of a legal document keyed by
/// a paragraph would make the table unreadable and the two languages
/// impossible to diff against each other; parallel documents keep each
/// language readable as a document, which is how anyone actually checks a
/// policy for accuracy.
struct LegalDocument {
    struct Section {
        let heading: String
        let body: String
    }

    let title: String
    /// Shown under the title. A policy with no date can't be compared
    /// against the version someone read before.
    let lastUpdated: String
    let sections: [Section]
}

enum LegalDocuments {
    /// Bumped whenever either document below changes in substance.
    /// Written out in both languages rather than formatted from a `Date`,
    /// since it names the day the text was written, not today.
    private static let lastUpdatedKorean = "2026년 9월 16일"
    private static let lastUpdatedEnglish = "16 September 2026"

    /// Left for the developer to fill in before submitting to the App
    /// Store — a policy has to name a way to reach someone, and guessing
    /// an address here would publish a contact route that may not be
    /// monitored. `SettingsView` shows this verbatim, so an unfilled
    /// placeholder is visible rather than silent.
    private static let contactKorean = "문의: (배포 전 연락처를 입력하세요)"
    private static let contactEnglish = "Contact: (add a contact address before release)"

    static func privacyPolicy(for language: AppLanguage) -> LegalDocument {
        switch language {
        case .korean: return koreanPrivacyPolicy
        case .english: return englishPrivacyPolicy
        }
    }

    static func termsOfService(for language: AppLanguage) -> LegalDocument {
        switch language {
        case .korean: return koreanTerms
        case .english: return englishTerms
        }
    }

    // MARK: - 개인정보 처리방침

    private static let koreanPrivacyPolicy = LegalDocument(
        title: "개인정보 처리방침",
        lastUpdated: lastUpdatedKorean,
        sections: [
            .init(
                heading: "요약",
                body: """
                PinSpots는 계정이 없고, 개발자가 운영하는 서버도 없습니다. 저장한 장소와 사진은 이 기기 안에 있습니다.

                다만 앱이 하는 일 중 일부는 외부 서비스를 부릅니다. 무엇이 언제 어디로 나가는지 아래에 전부 적었습니다. 그중 가장 중요한 것은 이것입니다 — AI로 사진을 스캔하면 그 사진이 사용자가 설정한 AI 제공자에게 업로드됩니다.
                """
            ),
            .init(
                heading: "기기에 저장되는 정보",
                body: """
                아래 정보는 이 앱의 저장 공간 안에만 있으며, 개발자는 볼 수 없습니다.

                • 게시판과 장소 카드 — 이름, 주소, 좌표, 카테고리, 평점, 연락처, 웹사이트, 영업시간, 메모, 태그, 방문 기록 등 사용자가 저장하거나 앱이 채운 모든 항목
                • 사진 — 사용자가 추가한 사진과 Google Places에서 받아온 장소 사진
                • API 키 — iOS 키체인에 저장되며 iCloud로 동기화되지 않습니다
                • 앱 설정 — 언어, AI 제공자 순서, 백업 폴더 위치, 사용량 카운터
                """
            ),
            .init(
                heading: "외부로 전송되는 정보",
                body: """
                아래는 이 앱이 연결하는 곳 전부입니다. 모두 사용자가 직접 등록한 API 키로, 사용자 본인의 계정으로 호출됩니다.

                1. Google Places API (places.googleapis.com)
                장소를 확인하거나 평점·사진·영업시간을 채울 때. 검색어(장소 이름과 주소)와 앱의 번들 식별자가 전송되며, 현재 위치를 사용할 수 있는 경우 검색 기준점으로 좌표가 함께 전송됩니다.

                2. Google Maps JavaScript API (maps.googleapis.com)
                "지도" 탭에서 Google 지도를 선택했을 때. 저장한 장소의 좌표가 지도에 표시됩니다.

                3. AI 제공자 — 사용자가 설정한 곳
                사진 스캔을 실행할 때 선택한 이미지가 업로드됩니다. 설정에 등록한 제공자에 따라 아래 중 한 곳입니다.
                • Anthropic (api.anthropic.com)
                • OpenAI (api.openai.com)
                • Google (generativelanguage.googleapis.com)
                • factchat-cloud.mindlogic.ai — 제3자가 운영하는 게이트웨이입니다. 이 앱이나 개발자가 운영하지 않으며, 선택한 경우에만 사용됩니다.
                업로드된 이미지가 그곳에서 어떻게 처리·보관되는지는 각 제공자의 정책을 따릅니다. 사진 스캔을 실행하지 않으면 사진은 기기를 떠나지 않습니다.

                4. Naver 검색 API (naverapihub.apigw.ntruss.com) — 선택
                Naver 자격 정보를 등록한 경우, 장소 이름이 검색어로 전송됩니다.

                5. Naver 지도 표시 페이지 (mrnoh99.github.io)
                "지도" 탭에서 Naver 지도를 선택하면 GitHub Pages에 호스팅된 지도 페이지를 불러옵니다. 표시할 좌표가 그 페이지로 전달됩니다.
                """
            ),
            .init(
                heading: "위치 정보",
                body: """
                위치 권한은 "앱 사용 중"만 사용하며, 두 가지에만 쓰입니다.

                • 저장한 장소를 현재 위치에서 가까운 순으로 정렬
                • Google 장소 검색 시 검색 기준점으로 사용 — 이 경우 좌표가 Google로 전송됩니다

                위치 기록을 남기거나 이동 경로를 저장하지 않습니다. 권한을 거부해도 정렬 기능만 사용할 수 없고 나머지는 정상 동작합니다.
                """
            ),
            .init(
                heading: "iCloud 보관",
                body: """
                "iCloud에 자동 보관"이 켜져 있으면, 앱을 열고 닫을 때마다 게시판·장소·사진 전체의 사본이 사용자 본인의 iCloud 계정 안, 이 앱 전용 공간에 저장됩니다. 기기를 바꾸거나 앱을 다시 설치했을 때 복구하기 위한 것입니다.

                이 사본은 사용자의 iCloud에 있으며 개발자는 접근할 수 없습니다. 설정에서 끌 수 있고, 끄면 이미 저장된 사본도 함께 삭제됩니다.
                """
            ),
            .init(
                heading: "수집하지 않는 것",
                body: """
                • 분석 도구, 광고, 추적 SDK를 일절 사용하지 않습니다
                • 개발자가 운영하는 서버가 없으므로 사용 기록이 전송되는 곳도 없습니다
                • 계정이 없고 이메일·이름·전화번호를 요구하지 않습니다
                • 설정 화면의 사용량 카운터는 이 기기 안에서만 계산되며 어디로도 전송되지 않습니다
                """
            ),
            .init(
                heading: "데이터 삭제",
                body: """
                앱을 삭제하면 기기에 저장된 장소·사진·설정·API 키가 함께 삭제됩니다.

                iCloud 사본은 설정에서 "iCloud에 자동 보관"을 끄면 삭제됩니다. 앱을 먼저 삭제한 경우에는 iOS 설정 앱의 iCloud 저장공간 관리에서 지울 수 있습니다.

                외부 서비스로 이미 전송된 내용(예: AI 제공자에 업로드된 이미지)의 삭제는 각 제공자에게 요청해야 합니다.
                """
            ),
            .init(
                heading: "아동의 개인정보",
                body: "이 앱은 아동을 대상으로 하지 않으며, 연령 정보를 포함해 어떤 개인정보도 수집하지 않습니다."
            ),
            .init(
                heading: "변경 및 문의",
                body: """
                이 방침이 바뀌면 앱 업데이트와 함께 이 화면의 내용이 갱신되고 상단 날짜가 바뀝니다.

                \(contactKorean)
                """
            )
        ]
    )

    private static let englishPrivacyPolicy = LegalDocument(
        title: "Privacy Policy",
        lastUpdated: lastUpdatedEnglish,
        sections: [
            .init(
                heading: "Summary",
                body: """
                PinSpots has no accounts and no server run by its developer. The places and photos you save stay on this device.

                Some of what the app does calls external services, though. Everything that leaves the device is listed below. The most important one: running an AI scan uploads that photo to whichever AI provider you configured.
                """
            ),
            .init(
                heading: "Stored on this device",
                body: """
                The following lives only inside this app's own storage. The developer cannot see any of it.

                • Boards and place cards — name, address, coordinates, category, rating, contacts, website, opening hours, notes, tags, visit history, and everything else you save or the app fills in
                • Photos — the ones you add, and place photos fetched from Google Places
                • API keys — kept in the iOS Keychain and never synced to iCloud
                • App settings — language, AI provider order, backup folder location, usage counters
                """
            ),
            .init(
                heading: "What leaves the device",
                body: """
                This is every destination the app connects to. All of them are called with the API key you registered yourself, on your own account.

                1. Google Places API (places.googleapis.com)
                When confirming a place or filling in its rating, photo or hours. Sends the search text (place name and address) and the app's bundle identifier, plus your coordinates as a search bias when a current location is available.

                2. Google Maps JavaScript API (maps.googleapis.com)
                When you pick the Google map in the "Map" tab. Your saved places' coordinates are drawn on it.

                3. Your configured AI provider
                When you run a photo scan, the selected image is uploaded. Depending on which provider you registered, that is one of:
                • Anthropic (api.anthropic.com)
                • OpenAI (api.openai.com)
                • Google (generativelanguage.googleapis.com)
                • factchat-cloud.mindlogic.ai — a gateway operated by a third party. Neither this app nor its developer runs it, and it is used only if you select it.
                How an uploaded image is handled and retained there is governed by that provider's own policy. If you never run a photo scan, your photos never leave the device.

                4. Naver Search API (naverapihub.apigw.ntruss.com) — optional
                If you registered Naver credentials, a place name is sent as the search query.

                5. Naver map page (mrnoh99.github.io)
                Picking the Naver map in the "Map" tab loads a map page hosted on GitHub Pages. The coordinates to display are passed to it.
                """
            ),
            .init(
                heading: "Location",
                body: """
                Location access is "while using the app" only, and is used for exactly two things:

                • Sorting your saved places by distance from where you are
                • Biasing a Google place search toward you — in this case your coordinates are sent to Google

                No location history or movement track is kept. Denying the permission disables only the distance sort; everything else works as normal.
                """
            ),
            .init(
                heading: "iCloud copy",
                body: """
                While "Keep a copy in iCloud" is on, a copy of all your boards, places and photos is written into this app's own area of your personal iCloud account each time you open and leave the app. It exists so you can recover after changing phones or reinstalling.

                That copy lives in your iCloud, and the developer cannot reach it. You can turn it off in Settings, and doing so also deletes the copy already stored.
                """
            ),
            .init(
                heading: "What is never collected",
                body: """
                • No analytics, advertising or tracking SDK of any kind
                • No developer-run server exists, so there is nowhere for usage data to be sent
                • No account, and no request for your email, name or phone number
                • The usage counter in Settings is computed on this device only and is never transmitted
                """
            ),
            .init(
                heading: "Deleting your data",
                body: """
                Deleting the app removes the places, photos, settings and API keys stored on the device with it.

                The iCloud copy is deleted when you turn "Keep a copy in iCloud" off in Settings. If you removed the app first, you can delete it from iCloud storage management in the iOS Settings app.

                Anything already sent to an external service — an image uploaded to an AI provider, for instance — has to be deleted by asking that provider.
                """
            ),
            .init(
                heading: "Children's privacy",
                body: "This app is not directed at children and collects no personal information at all, age included."
            ),
            .init(
                heading: "Changes and contact",
                body: """
                If this policy changes, this screen is updated along with the app and the date at the top changes with it.

                \(contactEnglish)
                """
            )
        ]
    )

    // MARK: - 이용약관

    private static let koreanTerms = LegalDocument(
        title: "이용약관",
        lastUpdated: lastUpdatedKorean,
        sections: [
            .init(
                heading: "이 앱이 하는 일",
                body: """
                PinSpots는 지도 앱·SNS·직접 찍은 사진에서 발견한 장소를 카드로 모아 기기 안에 저장하는 앱입니다. 계정이 없고, 개발자가 운영하는 서버가 없으며, 저장한 내용은 사용자의 기기에 있습니다.
                """
            ),
            .init(
                heading: "API 키와 비용",
                body: """
                이 앱은 외부 서비스 키를 내장하지 않습니다. 장소 확인, 지도 표시, AI 사진 스캔은 사용자가 직접 발급받아 등록한 키로, 사용자 본인의 계정으로 호출됩니다.

                따라서 그 호출에 대한 요금은 전적으로 사용자가 각 제공자에게 부담합니다. 앱은 불필요한 호출을 줄이도록 만들어져 있고(설정에서 사용량을 볼 수 있습니다) 한 번의 조작으로 나가는 요청 수에 상한을 두고 있지만, 실제 청구 금액을 보증하지는 않습니다.

                각 제공자 콘솔에서 일일 할당량과 예산 알림을 직접 설정하시기를 권합니다. 키 관리와 그 키로 발생한 요금은 사용자의 책임입니다.
                """
            ),
            .init(
                heading: "장소 정보의 정확성",
                body: """
                카드에 채워지는 평점·영업시간·연락처 등은 Google·Naver 같은 외부 서비스가 제공한 값이거나 AI가 사진에서 읽어낸 값입니다. 둘 다 틀릴 수 있습니다.

                특히 사진에서 읽어낸 정보는 확인된 사실이 아니라 추정입니다. 방문·예약·결제처럼 정확성이 중요한 판단은 반드시 해당 장소에 직접 확인하세요.
                """
            ),
            .init(
                heading: "사용자의 책임",
                body: """
                • 저장하고 스캔하는 이미지에 대한 권리를 확보할 것. 타인의 저작물이나 사생활이 담긴 이미지를 외부 AI 제공자로 업로드할 때는 특히 주의가 필요합니다.
                • 각 외부 서비스(Google, Naver, AI 제공자)의 이용약관을 함께 준수할 것.
                • 중요한 데이터는 백업할 것 — 설정에서 파일로 내보내거나 iCloud 보관을 사용할 수 있습니다.
                """
            ),
            .init(
                heading: "보증의 부인과 책임의 제한",
                body: """
                이 앱은 "있는 그대로" 제공되며, 특정 목적에의 적합성이나 무결성을 보증하지 않습니다.

                관련 법이 허용하는 범위에서, 개발자는 이 앱의 사용 또는 사용 불능으로 인한 손해(데이터 손실, 외부 서비스 요금, 잘못된 장소 정보로 인한 손해를 포함)에 대해 책임지지 않습니다. 외부 서비스의 중단·정책 변경·요금 변경에 대해서도 책임지지 않습니다.
                """
            ),
            .init(
                heading: "약관 변경 및 문의",
                body: """
                약관이 바뀌면 앱 업데이트와 함께 이 화면의 내용이 갱신되고 상단 날짜가 바뀝니다. 변경 후 앱을 계속 사용하면 변경된 약관에 동의한 것으로 봅니다.

                \(contactKorean)
                """
            )
        ]
    )

    private static let englishTerms = LegalDocument(
        title: "Terms of Service",
        lastUpdated: lastUpdatedEnglish,
        sections: [
            .init(
                heading: "What this app does",
                body: """
                PinSpots collects places you find in map apps, on social media, or in your own photos into cards stored on your device. There are no accounts, there is no server run by the developer, and what you save stays on your device.
                """
            ),
            .init(
                heading: "API keys and costs",
                body: """
                This app embeds no third-party service keys. Place verification, map display and AI photo scanning all run on keys you obtain and register yourself, billed to your own account.

                Charges for those calls are therefore entirely between you and each provider. The app is built to avoid unnecessary calls (Settings shows you the count) and caps how many requests a single action can spend, but it makes no guarantee about what you will be billed.

                Setting daily quotas and budget alerts in each provider's console is strongly recommended. Managing your keys, and any charges incurred with them, is your responsibility.
                """
            ),
            .init(
                heading: "Accuracy of place information",
                body: """
                Ratings, opening hours, contact details and the like are either supplied by an external service such as Google or Naver, or read out of a photo by an AI. Both can be wrong.

                Information read from a photo in particular is an estimate, not a confirmed fact. For anything where accuracy matters — visiting, booking, paying — confirm directly with the place itself.
                """
            ),
            .init(
                heading: "Your responsibilities",
                body: """
                • Have the rights to the images you save and scan. Take particular care before uploading someone else's work, or images containing other people's private information, to an external AI provider.
                • Comply with the terms of each external service you use (Google, Naver, your AI provider).
                • Back up anything important — Settings can export to a file, and the iCloud copy is available.
                """
            ),
            .init(
                heading: "Disclaimer and limitation of liability",
                body: """
                This app is provided "as is", without warranty of fitness for any particular purpose or of freedom from defects.

                To the extent permitted by applicable law, the developer is not liable for damages arising from use of or inability to use this app — including data loss, charges from external services, and harm resulting from incorrect place information. Nor is the developer responsible for external services being discontinued, or changing their policies or pricing.
                """
            ),
            .init(
                heading: "Changes and contact",
                body: """
                If these terms change, this screen is updated along with the app and the date at the top changes with it. Continuing to use the app after a change means accepting the revised terms.

                \(contactEnglish)
                """
            )
        ]
    )
}
