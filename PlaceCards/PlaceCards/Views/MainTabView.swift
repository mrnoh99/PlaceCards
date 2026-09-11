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
    /// Shown instead of the board picker when the shared link is an
    /// Instagram post/reel — see `SharedLinkParser.isInstagramLink`.
    @State private var isPresentingInstagramGuidanceAlert = false

    /// Shown once, right after a cold-launch auto-restore from
    /// `CloudBackupService` actually found and applied something — see
    /// `restoreFromCloudIfNeeded()`.
    @State private var showingCloudRestoreAlert = false

    var body: some View {
        TabView(selection: $navigation.selectedTab) {
            HomeView()
                .tabItem { Label("홈".localized, systemImage: "house") }
                .tag(AppTab.home)

            GalleryView(viewModel: GalleryViewModel(storageService: storageService))
                .tabItem { Label("갤러리".localized, systemImage: "square.grid.2x2") }
                .tag(AppTab.gallery)

            PlacesMapView(viewModel: MapViewModel(storageService: storageService))
                .tabItem { Label("지도".localized, systemImage: "map") }
                .tag(AppTab.map)

            SettingsView()
                .tabItem { Label("설정".localized, systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .environmentObject(navigation)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                checkForSharedImage()
                AutoBackupService.runIfDue(storageService: storageService)
                Task { await CloudBackupService.backup(storageService: storageService) }
            } else if newPhase == .background {
                Task { await CloudBackupService.backup(storageService: storageService) }
            }
        }
        .task {
            checkForSharedImage()
            AutoBackupService.runIfDue(storageService: storageService)
            await restoreFromCloudIfNeeded()
            await CloudBackupService.backup(storageService: storageService)
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
        .alert("iCloud에서 복원됨".localized, isPresented: $showingCloudRestoreAlert) {
            Button("확인".localized, role: .cancel) {}
        } message: {
            Text("iCloud에서 이전 백업을 찾아 게시판과 장소를 자동으로 복원했습니다.".localized)
        }
        .alert("인스타그램 링크는 자동으로 인식할 수 없어요".localized, isPresented: $isPresentingInstagramGuidanceAlert) {
            Button("확인".localized, role: .cancel) {}
        } message: {
            Text("게시물을 캡처(스크린샷)해서 \"장소 추가\"의 사진 선택으로 다시 추가해주세요.".localized)
        }
    }

    /// Only ever restores when local storage is still empty — a
    /// legitimately empty first run (a brand-new install with nothing
    /// backed up yet) must never be silently overwritten just because an
    /// iCloud snapshot happens to exist from some other install.
    private func restoreFromCloudIfNeeded() async {
        guard storageService.boards.isEmpty else { return }
        guard await CloudBackupService.hasRestorableBackup() else { return }
        await CloudBackupService.restoreIfAvailable(storageService: storageService)
        showingCloudRestoreAlert = true
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
            if SharedLinkParser.isInstagramLink(text) {
                isPresentingInstagramGuidanceAlert = true
            } else {
                pendingLinkText = text
                isPresentingSharedLinkSheet = true
            }
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(StorageService())
}
