import Foundation

/// 갤러리가 지금 무엇으로 좁혀져 있는지.
///
/// 예전에는 보드 id 하나(`currentHomeBoardID`)로만 나타냈다. 홈에 보드가
/// 아닌 모음("가져오기")이 생기면서 그것으로는 표현이 안 된다 — 보드 id를
/// 받는 자리에 보드가 아닌 것을 끼워 넣는 대신, 무엇으로 좁혔는지를 그대로
/// 적는다.
enum GalleryScope: Hashable {
    /// 모든 카드.
    case all
    case board(String)
    /// 다른 앱이 공유해 준 정보로 만들어진 카드만.
    case imported

    /// 보드로 좁혀져 있을 때만 그 id. 지도 탭처럼 보드만 아는 화면이
    /// 쓴다 — 가져오기로 좁혀져 있으면 nil이라 좁히지 않는다.
    var boardID: String? {
        if case .board(let id) = self { return id }
        return nil
    }
}

enum AppTab: Hashable {
    case home
    // 갤러리 탭은 없앴다. 홈이 두 칸으로 갈라지면서 오른쪽 칸이 곧
    // 갤러리이고, 탭으로 또 두면 같은 것이 두 군데가 된다.
    case map
    case settings
}

/// Cross-tab navigation state, injected once at the root (`MainTabView`)
/// so any screen further down a tab's navigation stack can reach it via
/// `@EnvironmentObject` — used by a board's "지도에서 보기" bulk action to
/// jump to the Map tab narrowed to just the selected cards. PlaceCards'
/// map is one app-wide tab shared by every board (unlike Peragra's
/// per-trip in-screen map view), so this has to reach across tabs rather
/// than just flip a local picker the way Peragra's `TripDetailView` does.
@MainActor
final class AppNavigation: ObservableObject {
    @Published var selectedTab: AppTab = .home
    /// Place card ids the Map tab should show exclusively — nil means
    /// show everything, as usual.
    @Published var mapFilterIDs: Set<String>?
    /// What the user last picked from Home's own list, or `.all` — Gallery
    /// and Map read this to scope themselves the same way, so the tabs stay
    /// in sync about "which places" without the user having to pick again
    /// in each one.
    ///
    /// 홈이 두 칸으로 갈라지면서, 이 값을 바꾸는 곳은 홈 왼쪽 목록의
    /// 선택 하나뿐이다. 예전에는 줄을 누르면 갤러리 탭으로 건너뛰는
    /// 함수들이 이 값을 바꿨는데, 이제 홈이 오른쪽 칸에 스스로 펼치므로
    /// 건너뛸 일이 없어 그 함수들은 지웠다.
    ///
    /// 지도 탭은 보드만 안다. `.imported`로 좁혀져 있으면 `boardID`가
    /// nil이라 지도는 좁히지 않고 전부 보여 준다.
    @Published var galleryScope: GalleryScope = .all

    /// Set by `HomeView`'s own category chips (browsing "by category"
    /// rather than by board) — `GalleryView` consumes this once, via
    /// `.onChange` rather than `.onAppear` (so merely revisiting the tab
    /// doesn't keep reapplying a filter the user has since cleared), and
    /// resets it back to nil right after, the same one-shot shape as
    /// `mapFilterIDs`/`showOnMap(_:)` below.
    @Published var galleryCategoryFilter: String?

    /// A card just created from info handed to the app from outside it (a
    /// shared link, a shared photo) — `GalleryView` consumes this once, the
    /// same one-shot `.onChange`-then-clear shape as `galleryCategoryFilter`,
    /// pushing straight to that card's `PlaceCardDetailView` so the user
    /// lands on the very place they just shared in, instead of back on
    /// whatever screen they started from with no visible confirmation.
    @Published var pendingDetailCardID: String?

    func showOnMap(_ ids: Set<String>) {
        mapFilterIDs = ids
        selectedTab = .map
    }

    /// 홈의 "카테고리별 보기" 칩 — 그 카테고리만 남긴 갤러리를 띄운다.
    /// 갤러리는 홈 오른쪽 칸에 있으므로 홈으로 간다.
    func showInGallery(category: String) {
        galleryCategoryFilter = category
        selectedTab = .home
    }

    /// A single card was just created from shared-in info (see
    /// `AddPlaceCardView`'s "추가" action) — jump to Gallery and have it
    /// push straight to that card.
    func showCardDetail(_ cardID: String) {
        pendingDetailCardID = cardID
        selectedTab = .home
    }
}
