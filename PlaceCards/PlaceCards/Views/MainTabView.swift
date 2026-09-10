import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var storageService: StorageService

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("홈", systemImage: "house") }

            GalleryView(viewModel: GalleryViewModel(storageService: storageService))
                .tabItem { Label("갤러리", systemImage: "square.grid.2x2") }

            PlacesMapView(viewModel: MapViewModel(storageService: storageService))
                .tabItem { Label("지도", systemImage: "map") }

            SettingsView()
                .tabItem { Label("설정", systemImage: "gearshape") }
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(StorageService())
}
