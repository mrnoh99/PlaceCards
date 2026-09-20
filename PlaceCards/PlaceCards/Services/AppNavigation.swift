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
    case gallery
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
    /// What the user last picked from Home, or `.all` — Gallery and Map
    /// read this to scope themselves the same way, so the tabs stay in
    /// sync about "which places" without the user having to pick again in
    /// each one. Set by `HomeView`'s rows (a board row, "모든 카드",
    /// "가져오기" — each also switches to the Gallery tab); put back to
    /// `.all` by Gallery's own "전체 보기" button (`GalleryView`) — not by
    /// any Home lifecycle event, since Home's own root view now never goes
    /// away just because a board was picked (there's no more push into a
    /// per-board screen to pop back out of).
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

    func showInGallery(category: String) {
        galleryCategoryFilter = category
        selectedTab = .gallery
    }

    /// Home's "모든 카드" row — the counterpart to `showBoardInGallery(_:)`.
    /// Clears the board scope rather than setting one, so Gallery opens on
    /// every card again. Until now the only way back out of a board scope
    /// was Gallery's own "전체 보기" button, which is invisible from Home.
    func showAllInGallery() {
        galleryScope = .all
        selectedTab = .gallery
    }

    /// 홈의 "가져오기" 줄 — 다른 앱이 공유해 준 정보로 만들어진 카드만
    /// 갤러리에 띄운다.
    func showImportedInGallery() {
        galleryScope = .imported
        selectedTab = .gallery
    }

    /// A board row tap on Home — scopes Gallery (and Map) to just that
    /// board's places and switches to the Gallery tab, replacing the old
    /// "push into a per-board list screen" flow.
    func showBoardInGallery(_ boardID: String) {
        galleryScope = .board(boardID)
        selectedTab = .gallery
    }

    /// A single card was just created from shared-in info (see
    /// `AddPlaceCardView`'s "추가" action) — jump to Gallery and have it
    /// push straight to that card.
    func showCardDetail(_ cardID: String) {
        pendingDetailCardID = cardID
        selectedTab = .gallery
    }
}
