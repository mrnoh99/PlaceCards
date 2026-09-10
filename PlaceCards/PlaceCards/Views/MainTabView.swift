import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var storageService: StorageService
    @StateObject private var navigation = AppNavigation()
    @Environment(\.scenePhase) private var scenePhase

    /// Set when a photo shared into the app through the Share Extension
    /// (`ShareViewController`, `PlaceCardsShare` target) is waiting to be
    /// picked up — checked every time the app becomes active, since the
    /// extension runs as a separate process and hands the photo over via
    /// `SharedImportStore`'s file in their shared App Group container,
    /// not directly.
    @State private var pendingSharedImageData: Data?
    @State private var isPresentingSharedImportSheet = false
    /// Set instead of `isPresentingSharedImportSheet` when the incoming
    /// photo arrives soon after "지도에서 열기" was tapped on this card
    /// (`MapOpenContext`) — offers adding it straight to that card rather
    /// than always asking which board to create a new one in.
    @State private var pendingMapScreenshotCard: PlaceCard?

    /// Same hand-off as `pendingSharedImageData`, for a shared link/text
    /// instead of a photo (e.g. the "share this page" prompt iOS offers
    /// for maps.google.com, or Naver Map's own share). Always goes
    /// through the board picker rather than `MapOpenContext` like the
    /// photo flow does — a link resolves to a place *name*, which is what
    /// creating a new card needs, not a field an existing card has to
    /// receive it in.
    @State private var pendingLinkText: String?
    @State private var isPresentingSharedLinkSheet = false

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
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            checkForSharedImage()
        }
        .task {
            checkForSharedImage()
        }
        .sheet(isPresented: $isPresentingSharedImportSheet) {
            if let pendingSharedImageData {
                SharedPhotoBoardPickerSheet(imageData: pendingSharedImageData)
            }
        }
        .sheet(item: $pendingMapScreenshotCard) { card in
            if let pendingSharedImageData {
                MapScreenshotImportSheet(card: card, imageData: pendingSharedImageData) { _ in }
            }
        }
        .sheet(isPresented: $isPresentingSharedLinkSheet) {
            if let pendingLinkText {
                SharedLinkBoardPickerSheet(linkText: pendingLinkText)
            }
        }
    }

    private func checkForSharedImage() {
        if let data = SharedImportStore.takePendingImage() {
            pendingSharedImageData = data
            if let cardID = MapOpenContext.recentCardID(), let card = storageService.placeCard(id: cardID) {
                pendingMapScreenshotCard = card
            } else {
                isPresentingSharedImportSheet = true
            }
            MapOpenContext.clear()
        }

        if let text = SharedImportStore.takePendingLink() {
            pendingLinkText = text
            isPresentingSharedLinkSheet = true
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(StorageService())
}
