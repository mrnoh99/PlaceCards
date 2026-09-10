import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var storageService: StorageService
    @StateObject private var navigation = AppNavigation()

    var body: some View {
        TabView(selection: $navigation.selectedTab) {
            HomeView()
                .tabItem { Label("홈", systemImage: "house") }
                .tag(AppTab.home)

            GalleryView(viewModel: GalleryViewModel(storageService: storageService))
                .tabItem { Label("갤러리", systemImage: "square.grid.2x2") }
                .tag(AppTab.gallery)

            PlacesMapView(viewModel: MapViewModel(storageService: storageService))
                .tabItem { Label("지도", systemImage: "map") }
                .tag(AppTab.map)

            SettingsView()
                .tabItem { Label("설정", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .environmentObject(navigation)
    }
}

#Preview {
    MainTabView()
        .environmentObject(StorageService())
}
