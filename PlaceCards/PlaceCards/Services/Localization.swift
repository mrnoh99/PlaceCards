import Foundation
import SwiftUI

/// The app's own UI language — separate from `ScanResultLanguage`, which
/// only controls the language AI-generated scan/search text is written in.
/// Currently Korean (the app's native-written language, always available
/// with no translation lookup) and English.
enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case korean
    case english

    var id: String { rawValue }

    /// Always shown in its own language regardless of the current app
    /// language — like every language picker, this labels each choice in
    /// a way a reader of *that* language recognizes, not a translation of
    /// the label itself.
    var displayName: String {
        switch self {
        case .korean: return "한국어"
        case .english: return "English"
        }
    }

    private static let defaultsKey = "appLanguage"

    /// Reads the saved app-language choice without needing an instance —
    /// `String.localized` calls this directly (see below), so it has to
    /// work from anywhere, not just from a SwiftUI view holding
    /// `LocalizationObserver`.
    static func current() -> AppLanguage {
        if let stored = UserDefaults.standard.string(forKey: defaultsKey),
           let language = AppLanguage(rawValue: stored) {
            return language
        }
        return .korean
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey)
    }
}

/// Held at the app root (`ContentView`) purely so changing the app
/// language can force the *entire* view tree to remount via `.id(...)` —
/// simplest way to make every already-written `"...".localized` call site
/// (there's no other hook into a plain string literal's rendering) pick up
/// a change immediately, without threading `@AppStorage`/`@EnvironmentObject`
/// into every one of the ~30 view files that call `.localized`.
@MainActor
final class LocalizationObserver: ObservableObject {
    static let shared = LocalizationObserver()

    @Published private(set) var language: AppLanguage

    private init() {
        language = AppLanguage.current()
    }

    func setLanguage(_ language: AppLanguage) {
        self.language = language
        language.save()
    }
}

extension String {
    /// This Korean UI string, translated to the current `AppLanguage` —
    /// falls back to the Korean original (this string itself) when the
    /// app language is Korean, or no translation exists for it yet, so
    /// every UI string can safely call this even before full translation
    /// coverage. Reads `AppLanguage.current()` directly (not
    /// `LocalizationObserver.shared`) so it works from any context
    /// (a `View.body`, a plain service/error type, a #Preview) — the
    /// `.id(LocalizationObserver.shared.language)` remount at the app
    /// root is what makes already-rendered UI actually re-evaluate when
    /// the setting changes; this property itself is just a lookup.
    var localized: String {
        guard AppLanguage.current() == .english, let translated = Localization.englishTranslations[self] else {
            return self
        }
        return translated
    }
}

/// English translations for every Korean UI string in the app, keyed by
/// that exact Korean source text. Deliberately a flat dictionary (not a
/// String Catalog / `.xcstrings` resource) — this project has no Xcode to
/// generate or validate one against, and a plain Swift literal is
/// something this environment's own tooling (brace/paren balance,
/// duplicate-declaration checks) can actually verify.
///
/// A handful of entries translate to an empty string or a short fragment
/// on purpose — they're the constant half of a call site built as
/// `"고정 문구".localized + dynamicValue` (splitting a Korean sentence
/// that has interpolation or an escaped quote in it, since those can't be
/// a single dictionary key). Search the call sites for the exact Korean
/// text if a translation here looks incomplete on its own.
enum Localization {
    static let englishTranslations: [String: String] = [
        "앱 언어": "App Language",
        "카드 검색": "Search cards",
        "카테고리 검색": "Search categories",
        "카테고리별 보기": "Browse by Category",
        "앱 화면 전체에서 사용하는 언어입니다. 사진 스캔·웹 검색 결과의 언어는 아래 \"AI 응답 언어\"에서 따로 정합니다.": "This is the language used throughout the app's screens. The language of photo-scan and web-search results is set separately below, under \"AI Response Language\".",
        " API 키가 저장되었습니다.": " API key saved.",
        " 정보를 채웠습니다.": " filled in.",
        "\" 근처 100m 이내에서 찾지 못했습니다.": "\" — nothing found within 100m of that address.",
        "\"(으)로 병합": "\" merge",
        "\"(으)로 보이는데, 현재 이름 \"": "\", but the current name is \"",
        "\"과 다릅니다. 이름을 바꿀까요?": "\". Change the name?",
        "\"을 삭제할까요?": "\"?",
        "\"지도\" 탭에서 Naver 지도를 선택했을 때만 사용됩니다. NAVER Cloud Platform Maps 애플리케이션의 Client ID이며, Secret은 필요 없습니다.": "Only used when Naver Maps is selected in the \"Map\" tab. This is the Client ID of a NAVER Cloud Platform Maps application — no Secret is needed.",
        "\"지도에서 열기\"로 최근에 연 카드예요. 방금 공유한 사진을 이 카드에 추가하고, AI로 읽어 비어 있는 이름·주소를 채웁니다.": "This card was recently opened via \"Open in Map\". The photo you just shared will be added to it, and AI will read it to fill in a blank name/address.",
        ")가 발견되어 적용하지 않았습니다. 한 장소가 나온 사진으로 다시 시도해주세요.": ") were found, so nothing was applied. Try again with a photo showing one place.",
        ")가 발견되어 정보는 채우지 않았습니다.": ") were found, so no info was filled in.",
        "+ 요일 추가": "+ Add day",
        "+ 장소 추가": "+ Add place",
        "2026년 4월": "April 2026",
        "AI 응답 언어": "AI Response Language",
        "AI 이미지 분석 (BYOK)": "AI Image Analysis (BYOK)",
        "AI가 읽은 정보를 채웠습니다.": "Filled in what AI read.",
        "AI가 찾은 장소를 검토·수정하거나 직접 추가하세요. \"Google에서 검색\"으로 정확한 주소·평점·연락처를 채울 수 있습니다.": "Review or edit the places AI found, or add your own. Use \"Search on Google\" to fill in the exact address, rating, and contact info.",
        "AI로 장소 분석하기 (": "Analyze photos with AI (",
        "AI로 정보 읽어오기": "Read info with AI",
        "API 오류 (": "API error (",
        "API 키": "API Key",
        "API 키 저장 방식": "How API keys are stored",
        "API 키는 내 것만": "Only your own API keys",
        "Apple 지도": "Apple Maps",
        "Google API 키가 저장되었습니다.": "Google API key saved.",
        "Google API 키가 필요합니다": "A Google API key is required",
        "Google Maps에서 열기": "Open in Google Maps",
        "Google 지도를 불러오지 못했습니다 — 설정의 API 키를 확인해주세요.": "Couldn't load Google Maps — please check the API key in Settings.",
        "Google 지도에서 확인됨": "Confirmed on Google Maps",
        "Google, Claude/ChatGPT/Gemini API 키를 설정에서 등록하세요. 키는 이 기기의 키체인에만 저장됩니다.": "Register your Google and Claude/ChatGPT/Gemini API keys in Settings. Keys are stored only in this device's Keychain.",
        "Google에서 검색": "Search on Google",
        "Kakao Map에서 열기": "Open in Kakao Map",
        "Naver Client ID가 필요합니다": "A Naver Client ID is required",
        "Naver Maps Client ID가 저장되었습니다.": "Naver Maps Client ID saved.",
        "Naver Map에서 열기": "Open in Naver Map",
        "Naver 지도 페이지에 연결할 수 없습니다 — 인터넷 연결을 확인해주세요.": "Couldn't connect to the Naver Maps page — please check your internet connection.",
        "Naver 지도 표시 (선택)": "Naver Map Display (Optional)",
        "Naver 지도에서 확인됨": "Confirmed on Naver Map",
        "Naver 검색 API (선택)": "Naver Search API (Optional)",
        "Naver 검색 API 정보가 저장되었습니다.": "Naver Search API credentials saved.",
        "Naver에서 검색": "Search on Naver",
        "PlaceCards 백업 파일이 아닙니다.": "This isn't a PlaceCards backup file.",
        "PlaceCards는 사용자가 등록한 API 키로 직접 Google/Naver/AI 서비스를 호출합니다(BYOK). 키는 iCloud와 동기화되지 않으며 이 기기에만 저장됩니다.": "PlaceCards calls Google/Naver/AI services directly using the API keys you register (BYOK). Keys are not synced via iCloud and are stored only on this device.",
        "Tmap에서 열기": "Open in Tmap",
        "Unsplash 검색": "Unsplash Search",
        "iCloud에서 복원됨": "Restored from iCloud",
        "iCloud에서 이전 백업을 찾아 게시판과 장소를 자동으로 복원했습니다.": "Found a previous backup in iCloud and automatically restored your boards and places.",
        "iOS 키체인 (기기 내)": "iOS Keychain (on-device)",
        "✅ 방문 (": "✅ Visited (",
        "⭐ 즐겨찾기 (": "⭐ Favorites (",
        "가져오기": "Import",
        "가져올 내용": "What will be imported",
        "같은 장소가 두 번 이상 저장된 것으로 보이는 ": "Found ",
        "개": "",
        "개 그룹을 찾았습니다. 남길 카드를 고른 뒤 병합하세요 — 나머지의 전화번호·링크·사진은 남는 카드로 옮겨진 뒤 삭제됩니다.": " group(s) that look like the same place saved more than once. Pick the card to keep, then merge — the others' phone numbers, links, and photos will be moved to the kept card before they're deleted.",
        "개 삭제": " selected — Delete",
        "개 선택)": " selected)",
        "개 선택됨": " selected",
        "개 장소를 삭제할까요?": " place(s)?",
        "개 카테고리를 이 이름으로 합칩니다.": " categories will be merged into this name.",
        "갤러리": "Gallery",
        "갤러리 · ": "Gallery · ",
        "갤러리에서 사진 선택 (여러 장 가능)": "Choose photos from gallery (multiple allowed)",
        "검색 결과가 없습니다.": "No search results.",
        "게시물을 캡처(스크린샷)해서 \"장소 추가\"의 사진 선택으로 다시 추가해주세요.": "Capture (screenshot) the post and add it again using photo picker in \"Add Place\".",
        "게시판": "Board",
        "게시판 가져오기": "Import Board",
        "게시판 수정": "Edit Board",
        "게시판 이동": "Move Board",
        "게시판 파일이 아닙니다.": "This isn't a board file.",
        "게시판이 없습니다": "No Boards",
        "경도": "Longitude",
        "공유": "Share",
        "공유로 사진 가져오기": "Importing shared photos",
        "공유한 링크를 추가할 게시판": "Board to add the shared link to",
        "공유한 사진을 추가할 게시판": "Board to add the shared photo to",
        "구글 지도 공유": "Google Maps share",
        "구글 지도 스크린샷": "Google Maps screenshot",
        "그 파일에서 복원하지 못했습니다.": "Couldn't restore from that file.",
        "기기의 위치 서비스가 꺼져 있지 않은지 확인하거나, 위치 신호를 받을 수 있는 곳에서 다시 시도해주세요.": "Check that Location Services is turned on for this device, or try again somewhere you can get a location signal.",
        "기본 정보": "Basic Info",
        "기존 게시판·장소는 그대로 두고, 새 게시판으로 추가됩니다.": "Existing boards and places are left as-is — this is added as a new board.",
        "기준: ": "From: ",
        "기준: 현재 위치": "From: Current Location",
        "내보내기": "Export",
        "네이버 지도 공유": "Naver Map share",
        "네이버 지도 스크린샷": "Naver Map screenshot",
        "네이버 지도에서 공유받은 장소는 Google 대신 이 API로 검증합니다. 위 \"Naver 지도 표시\"와는 별개의 애플리케이션입니다 — NAVER Cloud Platform 콘솔(console.ncloud.com)에서 Menu → All Services → Application Services → NAVER API HUB로 들어가 Application을 등록할 때 \"검색\" API를 선택하고, 등록된 Application의 \"인증 정보\"에서 Client ID/Secret을 확인해 입력하세요. 설정하지 않으면 지금처럼 Google로 검증합니다.":
            "A place shared from Naver Map is verified with this API instead of Google. Separate application from \"Naver Map Display\" above — in the NAVER Cloud Platform console (console.ncloud.com), go to Menu → All Services → Application Services → NAVER API HUB, register an Application selecting the \"Search\" API, then check the Client ID/Secret under that Application's \"Authentication Information\" and enter them here. If unset, verification falls back to Google as before.",
        "네트워크 오류: ": "Network error: ",
        "다른 앱에서 공유한 사진을 못 받아오는 상태입니다. Xcode에서 PlaceCards와 PlaceCardsShare 두 타겟 모두 Signing & Capabilities에 팀을 지정하고 \"App Groups\" 항목에 group.com.mrnoh99.PlaceCards가 켜져 있는지 확인해주세요.": "Photos shared from other apps can't be received right now. In Xcode, make sure both the PlaceCards and PlaceCardsShare targets have a team set under Signing & Capabilities, and that \"App Groups\" includes group.com.mrnoh99.PlaceCards.",
        "다음": "Next",
        "닫기": "Close",
        "대표사진": "Cover Photo",
        "대표사진으로 설정": "Set as Cover Photo",
        "데이터": "Data",
        "데이터 처리 오류: ": "Data processing error: ",
        "도쿄 봄 여행": "Tokyo Spring Trip",
        "되돌릴 수 없습니다.": "This can't be undone.",
        "둘 다 비우면 좌표가 삭제됩니다. 하나만 채워지면 원래 값이 그대로 유지됩니다.": "Leaving both blank removes the coordinate. Filling in only one keeps the original value.",
        "또는 파일에서": "Or from a file",
        "리뷰 ": "",
        "리뷰 수": "Review count",
        "마감 ": "Closes ",
        "마감 시간": "Closing time",
        "마지막 공유 시도": "Last share attempt",
        "마지막 백업: ": "Last backup: ",
        "만들기": "Create",
        "매일": "Daily",
        "매주": "Weekly",
        "먼저 게시판을 만들고, 그 안에 장소 카드를 추가해보세요.": "Create a board first, then add place cards to it.",
        "먼저 홈에서 게시판을 만들어주세요.": "Please create a board on Home first.",
        "메모": "Memo",
        "메모 (선택)": "Memo (optional)",
        "메모 없음": "No memo",
        "모델": "Model",
        "모두 병합했습니다": "Everything Merged",
        "모든 게시판·장소를 직접 고른 파일로 백업하거나, 백업 파일에서 복원합니다 — 복원하면 지금 앱에 있는 모든 데이터가 그 파일 내용으로 교체됩니다. 사진 자체는 백업에 포함되지 않고, 같은 기기에서 복원할 때만 정상적으로 보입니다.": "Back up every board and place to a file you choose, or restore from a backup file — restoring replaces everything currently in the app with that file's contents. Photos themselves aren't included in the backup, and only appear correctly when restoring on the same device.",
        "방문함": "Visited",
        "백업 폴더 선택…": "Choose Backup Folder…",
        "백업 폴더를 설정하지 못했습니다.": "Couldn't set the backup folder.",
        "백업에서 복원": "Restore from Backup",
        "백업에서 복원했습니다.": "Restored from backup.",
        "백업을 저장하지 못했습니다.": "Couldn't save the backup.",
        "백업을 저장했습니다.": "Backup saved.",
        "백업을 준비하지 못했습니다.": "Couldn't prepare the backup.",
        "변경": "Change",
        "병합": "Merge",
        "병합 (": "Merge (",
        "병합할 카테고리 이름": "Name for the Merged Category",
        "복원": "Restore",
        "부제목 (예: 2026년 4월 · 도쿄)": "Subtitle (e.g. April 2026 · Tokyo)",
        "붙여넣은 텍스트 확인": "Check Pasted Text",
        "비어있는 게시판 \"": "Delete the empty board \"",
        "사용자가 취소했습니다.": "Cancelled by user.",
        "사진": "Photos",
        "사진 가져오기": "Import Photo",
        "사진 더 추가": "Add More Photos",
        "사진 선택": "Choose Photos",
        "사진 스캔·웹 검색으로 채워지는 카테고리·메모 같은 텍스트를 어떤 언어로 작성할지 정합니다. 앱 화면 자체의 언어(한국어)에는 영향을 주지 않습니다.": "Sets the language for text filled in by photo scanning and web search, like category and memo. This doesn't affect the app's own screen language.",
        "사진 추가": "Add Photo",
        "사진에서 여러 장소(": "Several places found in the photo (",
        "사진에서 장소 정보를 찾지 못했습니다.": "Couldn't find place info in the photo.",
        "사진에서 새로 채울 정보를 찾지 못했습니다.": "Found nothing new to fill in from the photo.",
        "사진에서는 \"": "The photo looks like \"",
        "사진으로 바로 추가": "Add straight from a photo",
        "사진은 저장 시 카드에 추가됩니다. \"AI로 정보 읽어오기\"는 비어 있는 이름·주소를 채우는데, 사진에서 여러 장소가 발견되면 적용하지 않고 알려드리고, 이름이 바뀌는 경우엔 확인 후 적용됩니다.": "The photo is added to the card when you save. \"Read Info with AI\" fills in a blank name/address — if several places are found in the photo, nothing is applied and you're told; if the name would change, it's applied only after you confirm.",
        "사진을 카드에 추가했습니다.": "Added the photo to the card.",
        "사진을 카드에 추가했습니다. (장소 정보는 찾지 못했습니다.)": "Added the photo to the card. (No place info was found.)",
        "사진을 카드에 추가했습니다. (정보 읽기 실패: ": "Added the photo to the card. (Failed to read info: ",
        "사진을 카드에 추가했습니다. 사진에서 여러 장소(": "Added the photo to the card. Several places were found in the photo (",
        "삭제": "Delete",
        "상태": "Status",
        "새 게시판": "New Board",
        "샘플 카페": "Sample Cafe",
        "서울시 강남구": "Gangnam-gu, Seoul",
        "선택": "Select",
        "선택한 ": "Selected ",
        "선택한 장소": "Selected Places",
        "선택한 폴더에 백업했습니다.": "Backed up to the chosen folder.",
        "설정": "Settings",
        "설정 열기": "Open Settings",
        "설정에서 API 키를 먼저 등록해주세요.": "Please register an API key in Settings first.",
        "설정에서 Google Places API 키를 등록해주세요.": "Please register a Google Places API key in Settings.",
        "설정에서 Naver 지도 표시용 NCP Client ID를 등록해주세요.": "Please register an NCP Client ID for Naver Map display in Settings.",
        "수정": "Edit",
        "수정한 날짜: ": "Edited: ",
        "수정할 장소를 선택하세요": "Select places to edit",
        "쉼표로 구분": "Comma-separated",
        "스크린샷이나 사진을 넣으면 AI가 장소명을 찾아주고, Google 지도 정보로 자동 보강됩니다.": "Add a screenshot or photo and AI will find the place name, then fill in the details automatically from Google Maps.",
        "시작하기": "Get Started",
        "식당": "Restaurant",
        "아이콘": "Icon",
        "아직 공유 시도 기록이 없습니다. 사진 공유 시트에서 PlaceCards를 선택하면 여기에 결과가 표시됩니다.": "No share attempts recorded yet. Choose PlaceCards from a photo share sheet and the result will show up here.",
        "아직 지원하지 않는 기능입니다: ": "Not supported yet: ",
        "알 수 없는 오류": "Unknown error",
        "알림": "Notice",
        "연결 안 됨": "Not Connected",
        "연결됨": "Connected",
        "연락처": "Contact",
        "영업 정보": "Business Info",
        "영업시간": "Hours",
        "영업시간 (예: 09:00-18:00)": "Hours (e.g. 09:00-18:00)",
        "영업시간(홈페이지): ": "Hours (from homepage): ",
        "예약": "Reserve",
        "예약 ": "Reservation ",
        "예약 방법": "Reservation method",
        "예약 방법 (예: 캐치테이블 예약)": "Reservation method (e.g. Catch Table booking)",
        "완료": "Done",
        "요일": "Day",
        "요청 시간이 초과되었습니다.": "The request timed out.",
        "웹 검색에서 새로 채울 정보를 찾지 못했습니다.": "The web search didn't find any new info to fill in.",
        "웹 검색으로 채우기": "Fill In via Web Search",
        "웹사이트": "Website",
        "웹사이트 URL": "Website URL",
        "위 항목 어디에도 맞지 않는 정보를 자유롭게 적어두는 곳입니다.": "A free-form spot for anything that doesn't fit the fields above.",
        "위도": "Latitude",
        "위치 권한이 꺼져 있습니다": "Location Permission Is Off",
        "유효하지 않은 API 키입니다.": "That API key isn't valid.",
        "의 호출 한도를 초과했습니다. 잠시 후 다시 시도해주세요.": "'s call limit was exceeded. Please try again shortly.",
        "이 백업으로 모든 게시판·장소를 교체할까요?": "Replace every board and place with this backup?",
        "이 사진을 삭제할까요?": "Delete this photo?",
        "이 카드에 추가할까요?": "Add to this card?",
        "이 폴더에 대한 접근 권한이 끊어졌습니다. 아래에서 폴더를 다시 선택해주세요.": "Access to this folder was lost. Please choose the folder again below.",
        "이름": "Name",
        "이름 (예: 도쿄 봄 여행)": "Name (e.g. Tokyo Spring Trip)",
        "이름·주소로 AI가 웹을 검색해 전화번호·웹사이트·영업시간 등 비어 있는 항목만 채웁니다. 이미 값이 있는 항목은 바뀌지 않습니다.": "AI searches the web using the name and address to fill in only the blank fields — phone, website, hours, and so on. Fields that already have a value are left unchanged.",
        "이름은 유지": "Keep the Name",
        "이름이 같고 위치나 주소가 가까워야 중복으로 표시됩니다.": "Shown as a duplicate only when the name matches and the location or address is close.",
        "이름이 다릅니다": "Name Doesn't Match",
        "이미지를 처리할 수 없습니다.": "Couldn't process the image.",
        "이미지에서 장소를 찾지 못했습니다. 아래에서 직접 추가해주세요.": "No places were found in the image. Please add one manually below.",
        "인스타그램": "Instagram",
        "인스타그램 URL": "Instagram URL",
        "인스타그램 링크는 자동으로 인식할 수 없어요": "Instagram links can't be recognized automatically",
        "인스타그램 스크린샷": "Instagram screenshot",
        "읽을 수 없는 텍스트입니다.": "Couldn't read that text.",
        "입력 오류: ": "Input error: ",
        "자동 백업": "Auto Backup",
        "자동 백업 끄기": "Turn Off Auto Backup",
        "자동으로 백업": "Back Up Automatically",
        "잘못된 검색어입니다.": "Invalid search query.",
        "잘못된 사진 URL": "Invalid photo URL",
        "장)": " photos)",
        "장소 ": "",
        "장소 검색": "Search places",
        "장소 선택…": "Choose a Place…",
        "장소 정보 수정": "Edit Place Info",
        "장소 추가": "Add Place",
        "장소명": "Place name",
        "저장": "Save",
        "저장 실패 (코드 ": "Save failed (code ",
        "저장 실패: ": "Save failed: ",
        "전달받은 사진": "Received Photo",
        "전체": "All",
        "전체 (": "All (",
        "전체 백업": "Full Backup",
        "전체 보기": "Show All",
        "전체 선택": "Select All",
        "전체 해제": "Deselect All",
        "전화": "Call",
        "전화번호": "Phone",
        "전화번호: ": "Phone: ",
        "정렬: ": "Sort: ",
        "정보": "Info",
        "제공자": "Provider",
        "좌표": "Coordinates",
        "주기": "Frequency",
        "주소": "Address",
        "중복 찾기": "Find Duplicates",
        "중복이 없습니다": "No Duplicates",
        "즐겨찾기": "Favorite",
        "지금 백업": "Back Up Now",
        "지도": "Map",
        "지도 앱, SNS, 직접 찍은 사진에서 발견한 장소를 하나의 카드로 모아보세요.": "Gather places you found in map apps, social media, or photos you took, into a single card.",
        "지도에서 보기": "View on Map",
        "지도에서 열기": "Open in Map",
        "직접 입력": "Enter manually",
        "직접 입력…": "Enter manually…",
        "찾아낸 중복을 모두 병합했습니다.": "All the duplicates found have been merged.",
        "첫 게시판 만들기": "Create First Board",
        "추가": "Add",
        "추가 (": "Add (",
        "추가하기": "Add",
        "추가할 장소 (": "Places to add (",
        "취소": "Cancel",
        "카드 보기": "View Card",
        "카카오맵 공유": "Kakao Map share",
        "카카오맵 스크린샷": "Kakao Map screenshot",
        "카테고리": "Category",
        "카테고리 변경": "Change Category",
        "카테고리 이름": "Category Name",
        "카테고리 입력": "Enter Category",
        "카테고리: ": "Category: ",
        "카페": "Cafe",
        "키체인 오류: ": "Keychain error: ",
        "태그": "Tag",
        "태그 추가": "Add tag",
        "특정 예약 플랫폼으로 바로 연결되는 링크는 지원하지 않아, 상세보기의 \"예약\" 버튼은 여기 적은 내용으로 웹 검색을 열어줍니다.": "Direct links to a specific reservation platform aren't supported — the detail view's \"Reserve\" button opens a web search for whatever you write here instead.",
        "텍스트 붙여넣기": "Paste Text",
        "텍스트로 복사": "Copy as Text",
        "파일 선택…": "Choose File…",
        "파일로 공유": "Share as File",
        "파일을 읽지 못했습니다.": "Couldn't read the file.",
        "편의시설": "Amenities",
        "편집": "Edit",
        "평가": "Rating",
        "평점 (0~5)": "Rating (0-5)",
        "폴더": "Folder",
        "폴더 변경…": "Change Folder…",
        "폴더를 한 번 선택해두면, 앱을 열 때마다(위 주기당 최대 한 번) PlaceCards가 그 폴더에 새 백업을 저장합니다.": "Once you choose a folder, PlaceCards saves a new backup there each time you open the app (at most once per the interval above).",
        "폴더에 쓰지 못했습니다 — 아래에서 폴더를 다시 선택해주세요.": "Couldn't write to the folder — please choose the folder again below.",
        "현장 촬영": "Taken on-site",
        "현재 위치": "Current Location",
        "현재 위치를 가져오지 못했습니다": "Couldn't get your current location",
        "현재 위치에서의 거리를 표시하려면 설정 앱에서 PlaceCards의 위치 권한을 허용해주세요.": "To show distance from your current location, allow location access for PlaceCards in the Settings app.",
        "호텔": "Hotel",
        "홈": "Home",
        "확인": "OK",
        "휴무일": "Closed on",
        "휴무일 ": "Closed on ",
        "📋 카드 보기": "📋 View Card",
    ]
}
