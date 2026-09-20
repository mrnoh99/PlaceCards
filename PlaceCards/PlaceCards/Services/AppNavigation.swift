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
    /// 지금 고르고 있는 카드들. **지도를 좁히는 유일한 길이다.**
    ///
    /// 거는 곳이 둘이고, 둘 다 "지금 이것을 보고 있다"는 뜻이다.
    ///
    /// - 갤러리의 선택 모드 — 고르는 동안에만 값이 있고 선택을 놓으면 비워진다.
    /// - 카드 하나를 열어 둔 것(`GalleryView.selectedCard`) — 카드 하나도
    ///   "하나를 고른 것"으로 친다.
    ///
    /// 둘 다 `GalleryView.syncLiveSelection`이 한곳에서 맞추고, **화면이 뜨고
    /// 지는 것에는 기대지 않는다.** `TabView`는 탭을 옮길 때 떠나는 탭에
    /// `.onDisappear`를 주므로, 거기서 놓으면 지도 탭을 누른 바로 그 순간 —
    /// 이 값이 쓰이는 유일한 순간에 — 먼저 사라진다. 한 번 그렇게 만들었다가
    /// 되돌렸다.
    ///
    /// 어느 쪽이든 고른 채로 지도 탭을 열면 고른 것만 보인다. 예전에는
    /// "지도에서 보기" 단추를 눌러야 했고, 그 단추는 `mapFilterIDs`를 한 번
    /// 걸어 두는 방식이었다. 둘 다 없앴다 — 지도를 좁히는 길이 둘이면 한쪽을
    /// 풀어도 다른 쪽이 남아 "전체 해제를 눌렀는데 전부가 안 보인다"가 된다.
    ///
    /// 그래서 **새로 좁히는 길을 만들지 말고 이 값에 얹을 것.**
    @Published var liveSelection: Set<String>?
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

    /// 홈의 "카테고리별 보기" 칩이 맡겨 두는 카테고리. `GalleryView`가
    /// 한 번 꺼내 쓰고 바로 nil로 되돌린다 — 한 번 쓰고 비우는 우편함이다.
    ///
    /// 꺼내 쓰는 쪽(`consumePendingCategoryFilter`)이 **범위와 필터를 함께**
    /// 맞춘다. 범위가 바뀌면 카테고리 필터를 비우는 규칙이 따로 있어서,
    /// 둘을 나눠 두면 그 둘이 서로 다른 갱신에 실려 비우는 쪽이 방금 건
    /// 필터를 지워 버린다. 이 값이 차 있는 동안 비우는 쪽은 비켜선다.
    @Published var galleryCategoryFilter: String?

    /// A card just created from info handed to the app from outside it (a
    /// shared link, a shared photo) — `GalleryView` consumes this once, via
    /// `.onChange` rather than `.onAppear` (so merely revisiting the screen
    /// doesn't keep reopening a card), clearing it right after —
    /// pushing straight to that card's `PlaceCardDetailView` so the user
    /// lands on the very place they just shared in, instead of back on
    /// whatever screen they started from with no visible confirmation.
    @Published var pendingDetailCardID: String?

    /// A single card was just created from shared-in info (see
    /// `AddPlaceCardView`'s "추가" action) — jump to Gallery and have it
    /// push straight to that card.
    func showCardDetail(_ cardID: String) {
        pendingDetailCardID = cardID
        selectedTab = .home
    }
}
