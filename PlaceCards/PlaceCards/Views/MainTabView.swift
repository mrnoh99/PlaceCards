import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var storageService: StorageService
    @State private var isPresentingAddCard = false

    var body: some View {
        TabView {
            HomeView(isPresentingAddCard: $isPresentingAddCard)
                .tabItem { Label("홈", systemImage: "house") }

            GalleryView(viewModel: GalleryViewModel(storageService: storageService))
                .tabItem { Label("갤러리", systemImage: "square.grid.2x2") }

            PlacesMapView(viewModel: MapViewModel(storageService: storageService))
                .tabItem { Label("지도", systemImage: "map") }

            SettingsView()
                .tabItem { Label("설정", systemImage: "gearshape") }
        }
        .sheet(isPresented: $isPresentingAddCard) {
            AddPlaceCardView(viewModel: PlaceCardViewModel(storageService: storageService))
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(StorageService())
}
