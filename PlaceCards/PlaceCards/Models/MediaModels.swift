import Foundation

/// Where a piece of information or media about a place came from.
enum SourceType: String, Codable, CaseIterable {
    case naverMapScreenshot
    case googleMapScreenshot
    case kakaoMapScreenshot

    case naverMapShare
    case googleMapShare
    case kakaoMapShare

    case googleDirectLookup
    case naverDirectLookup
    /// Never produced, and never will be: this app talks to no Kakao API.
    /// Kakao's local API forbids persisting its structured results, which
    /// is why the plan dropped it, and Kakao support here is limited to
    /// opening a place in Kakao Map by deep link (`KakaoMapOpener`) —
    /// which stores nothing and is outside that restriction.
    ///
    /// Kept rather than deleted for the same reason as `unsplashSearch`
    /// below: removing a case from this enum is how a saved card stops
    /// decoding. Nothing in any version ever assigned this one, so no
    /// stored card can carry it, but the rule holds for the enum as a
    /// whole and a never-rendered case costs nothing. `kakaoMapScreenshot`
    /// and `kakaoMapShare` above are unassigned for the same reason.
    case kakaoDirectLookup

    case onsitePhoto
    case receivedPhoto

    case instagramScreenshot
    case userManualInput

    /// Legacy only — the Unsplash fallback-photo feature this case was
    /// for has been removed. Kept as a case (never delete it) purely for
    /// decode safety: `MediaItem.source` is a non-optional `SourceType`,
    /// so a still-saved card with a photo from when this feature existed
    /// would fail to decode — silently wiping every card in storage,
    /// since `StorageService.loadPlaceCards()` discards the whole array
    /// on any decode error — if this raw value ever stopped resolving.
    case unsplashSearch

    var displayName: String {
        switch self {
        case .naverMapScreenshot: return "네이버 지도 스크린샷".localized
        case .googleMapScreenshot: return "구글 지도 스크린샷".localized
        case .kakaoMapScreenshot: return "카카오맵 스크린샷".localized
        case .naverMapShare: return "네이버 지도 공유".localized
        case .googleMapShare: return "구글 지도 공유".localized
        case .kakaoMapShare: return "카카오맵 공유".localized
        case .googleDirectLookup: return "Google Places API"
        case .naverDirectLookup: return "Naver API"
        // Unreachable — see the case's own comment. Named for what it
        // would have meant, not for anything this app does.
        case .kakaoDirectLookup: return "Kakao API"
        case .onsitePhoto: return "현장 촬영".localized
        case .receivedPhoto: return "전달받은 사진".localized
        case .instagramScreenshot: return "인스타그램 스크린샷".localized
        case .userManualInput: return "직접 입력".localized
        case .unsplashSearch: return "Unsplash 검색".localized
        }
    }
}

struct MediaItem: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    /// File name of the image inside the app's local media directory (see `MediaStore`).
    var localPath: String
    var url: String?
    var caption: String?
    var uploadedAt: Date = Date()
    var source: SourceType
}

/// Groups a place's media by where it came from, matching the four
/// categories the product spec tracks separately.
struct MediaBundle: Codable, Equatable {
    var mapScreenshots: [MediaItem] = []
    var officialPhotos: [MediaItem] = []
    var onsitePhotos: [MediaItem] = []
    var receivedPhotos: [MediaItem] = []

    var allItems: [MediaItem] {
        mapScreenshots + officialPhotos + onsitePhotos + receivedPhotos
    }

    /// Whether this card has any photo besides a map/social screenshot
    /// uploaded purely so AI could read text off it (`mapScreenshots` —
    /// see `MapScreenshotImportSheet`, which feeds these straight into
    /// `analyzePlaces`, never meant as an actual picture of the place).
    /// Used to decide whether an automatic Google-photo fetch
    /// (`EditPlaceCardSheet.refreshFromGooglePlaceDetails()`,
    /// `MapLinkImportSheet.enrichFromGooglePlaces()`) should still run —
    /// a card whose only "photo" is really just an OCR input shouldn't
    /// block fetching a real one.
    var hasNonScreenshotPhoto: Bool {
        !officialPhotos.isEmpty || !onsitePhotos.isEmpty || !receivedPhotos.isEmpty
    }
}
