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

    func showOnMap(_ ids: Set<String>) {
        mapFilterIDs = ids
        selectedTab = .map
    }
}
