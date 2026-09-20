import SwiftUI

/// Shown when a photo was handed to PlaceCards through the Share
/// Extension (`ShareViewController`, `PlaceCardsShare` target) — opens the
/// normal "장소 추가" flow (`AddPlaceCardView`) with the shared photo
/// already picked.
///
/// 이름에 "BoardPicker"가 남아 있지만 더 이상 게시판을 묻지 않는다.
/// 공유로 들어온 카드는 일단 "가져오기"로 가고, 게시판은 나중에 거기서
/// 정한다. 이름을 그대로 둔 것은 `MainTabView`의 공유 표시 장치
/// (`.sheet(item:)`·큐·`presentShortly`)를 건드리지 않기 위해서다 —
/// 00_UI개편_기초.md §2.1이 그 부분을 특별히 경고한다.
///
/// 게시판을 고르는 단계가 사라지면서 "게시판이 없습니다" 막다른 길도
/// 없어졌다. 게시판을 하나도 만들지 않은 채 공유해도 카드가 만들어진다.
struct SharedPhotoBoardPickerSheet: View {
    let imageData: Data
    /// Photos the user had already picked in `AddPlaceCardView` before
    /// leaving for a map app to find where they were taken — carried into
    /// the same new card as the screenshot they shared back, so one trip
    /// out to the map produces one card holding both. Empty for every
    /// ordinary share; see `MapOpenContext`.
    var photoDatas: [Data] = []

    @EnvironmentObject private var storageService: StorageService
    /// Re-declared and re-injected below purely so `AddPlaceCardView`'s own
    /// sheet actually gets it — see `SharedLinkBoardPickerSheet`'s identical
    /// comment on this same property for why a second level of `.sheet`
    /// needs it re-attached explicitly.
    @EnvironmentObject private var navigation: AppNavigation

    var body: some View {
        // 게시판을 고르지 않으므로 여기서 바로 "장소 추가"다. 예전에는
        // 이 시트가 게시판 목록을 보여 주고 고른 뒤에 중첩 시트로
        // `AddPlaceCardView`를 띄웠다 — 시트를 겹쳐 쌓는 것은
        // `MainTabView`의 주석이 "조용히 안 뜨는" 원인으로 적어 둔 모양
        // 이므로, 한 겹 줄어든 것은 덤이다.
        AddPlaceCardView(
            viewModel: PlaceCardViewModel(
                storageService: storageService, boardId: nil, cameFromShare: true
            ),
            // The user's own photos first, the just-shared one last:
            // whichever ends up first is the one a cover photo is taken
            // from, and a map screenshot — shared to be read for its text,
            // not looked at — is the worse choice for that than a photo
            // they actually took of the place.
            initialImageDatas: photoDatas + [imageData]
        )
        .environmentObject(navigation)
    }
}

#Preview {
    SharedPhotoBoardPickerSheet(imageData: Data())
        .environmentObject(StorageService())
        .environmentObject(AppNavigation())
}
