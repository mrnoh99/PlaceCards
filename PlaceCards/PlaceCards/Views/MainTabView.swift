import SwiftUI
import UIKit

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
    /// for maps.google.com, or Naver Map's own share).
    @State private var pendingLinkText: String?
    @State private var isPresentingSharedLinkSheet = false
    /// Set instead of `isPresentingSharedLinkSheet` when the incoming link
    /// arrives soon after "지도에서 열기" was tapped on this card — same
    /// `MapOpenContext`-aware routing `pendingMapScreenshotCard` already
    /// does for a shared photo, so confirming a place on Google/Naver Map
    /// and sharing it back can merge straight into the card that sent the
    /// user there instead of always creating a new one.
    @State private var pendingMapLinkCard: PlaceCard?
    /// Shown instead of the board picker when the shared link is an
    /// Instagram post/reel — see `SharedLinkParser.isInstagramLink`.
    @State private var isPresentingInstagramGuidanceAlert = false

    /// Shown once, right after a cold-launch auto-restore from
    /// `CloudBackupService` actually found and applied something — see
    /// `restoreFromCloudIfNeeded()`.
    @State private var showingCloudRestoreAlert = false

    /// Covers the tab view at cold launch until `restoreFromCloudIfNeeded()`
    /// settles — the one startup step whose result actually changes what
    /// appears on screen (a first-run/reinstall device restoring its whole
    /// library from iCloud before there's anything local to show yet).
    /// True only that briefly: for a returning user with local data
    /// already on disk, `restoreFromCloudIfNeeded()`'s own guard returns
    /// almost immediately, so this never visibly lingers. Backups
    /// (`AutoBackupService`/`CloudBackupService.backup`, now potentially
    /// carrying every photo's own bytes — see `BackupService`'s own doc
    /// comment) are pure writes that don't change what's displayed, so
    /// they're kicked off separately, after this is already down, instead
    /// of holding the intro screen up for them too.
    @State private var isPerformingStartupWork = true

    var body: some View {
        ZStack {
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

            if isPerformingStartupWork {
                startupIntroView
                    .transition(.opacity)
            }
        }
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
            await restoreFromCloudIfNeeded()
            withAnimation { isPerformingStartupWork = false }

            // Fire-and-forget from here on — exporting the current data
            // elsewhere doesn't change anything on screen, so there's no
            // reason to keep the intro up for it. A separate `Task` so it
            // keeps running after this one's own body has already
            // finished, rather than in line ahead of the state change
            // above.
            Task {
                AutoBackupService.runIfDue(storageService: storageService)
                await CloudBackupService.backup(storageService: storageService)
            }
        }
        .sheet(isPresented: $isPresentingSharedImportSheet) {
            if let pendingSharedImageData {
                SharedPhotoBoardPickerSheet(imageData: pendingSharedImageData)
                    .environmentObject(navigation)
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
                    .environmentObject(navigation)
            }
        }
        .sheet(item: $pendingMapLinkCard) { card in
            if let pendingLinkText {
                MapLinkImportSheet(card: card, linkText: pendingLinkText) { _ in }
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

    /// Opaque, not a translucent overlay — it needs to fully hide the tab
    /// view underneath (still being laid out/rendered on an empty or
    /// stale `storageService` while this is up), not just dim it.
    private var startupIntroView: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor)
                Text("PinSpots")
                    .font(.title2.bold())
                ProgressView()
                    .padding(.top, 8)
            }
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
        // Read once, up front, rather than inside each branch below — the
        // image branch clears this right after checking it, so a link
        // branch reading it afterward would always see it already gone on
        // the (rare) occasion both an image and a link were pending at
        // once. Reading it once here is correct either way.
        let recentCardID = MapOpenContext.recentCardID()

        if let data = SharedImportStore.takePendingImage() {
            pendingSharedImageData = data
            if let recentCardID, let card = storageService.placeCard(id: recentCardID) {
                presentShortly { pendingMapScreenshotCard = card }
            } else {
                presentShortly { isPresentingSharedImportSheet = true }
            }
            MapOpenContext.clear()
        }

        if let text = SharedImportStore.takePendingLink() {
            if SharedLinkParser.isInstagramLink(text) {
                presentShortly { isPresentingInstagramGuidanceAlert = true }
            } else if let recentCardID, let card = storageService.placeCard(id: recentCardID) {
                pendingLinkText = text
                presentShortly { pendingMapLinkCard = card }
            } else {
                pendingLinkText = text
                presentShortly { isPresentingSharedLinkSheet = true }
            }
            MapOpenContext.clear()
        }
    }

    /// Flipping a sheet/alert's `isPresented` binding to `true` in the very
    /// same runloop tick as the app finishing a foreground transition
    /// (cold launch's `.task`, or `scenePhase` flipping to `.active` right
    /// after the user switches back from wherever they shared out of) can
    /// silently fail to actually present — the state changes, but no sheet
    /// appears, until *something else* changes state afterward. Reported
    /// as "처음에는 화면이 안 뜨다가 포커스를 바꿨다 돌아오면 뜬다" (doesn't
    /// show up at first; switching away and back makes it appear).
    ///
    /// A flat 150ms delay used to be the fix, but a heavier return trip —
    /// switching back after finding a place in the Google Maps app and
    /// sharing it, say — can still land the state flip inside that window,
    /// since the delay was only ever a guess at how long the window scene
    /// takes to settle, not an actual signal that it has. This instead
    /// polls until the window scene reports itself `.foregroundActive`
    /// (there's no notification for "now it's safe to present a sheet"),
    /// then waits one more short beat before presenting — closer to
    /// waiting for the real condition than hoping a fixed number was big
    /// enough.
    private func presentShortly(_ action: @escaping () -> Void) {
        Task { @MainActor in
            for _ in 0..<20 {
                let isActive = UIApplication.shared.connectedScenes.contains { $0.activationState == .foregroundActive }
                if isActive { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
            action()
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(StorageService())
}
