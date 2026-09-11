import Foundation

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
    /// The board the user last picked from Home's board list, or nil for
    /// "every board" — Gallery and Map read this to scope themselves to
    /// that board, so all three tabs stay in sync about "which places"
    /// without the user having to pick a board again in each one. Set by
    /// `HomeView.showBoardInGallery` (a board row tap, which also switches
    /// to the Gallery tab); cleared only by Gallery's own "전체 보기"
    /// button (`GalleryView`) — not by any Home lifecycle event, since
    /// Home's own root view now never goes away just because a board was
    /// picked (there's no more push into a per-board screen to pop back
    /// out of).
    @Published var currentHomeBoardID: String?

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

    /// A board row tap on Home — scopes Gallery (and Map) to just that
    /// board's places and switches to the Gallery tab, replacing the old
    /// "push into a per-board list screen" flow.
    func showBoardInGallery(_ boardID: String) {
        currentHomeBoardID = boardID
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
