import SwiftUI
import UIKit

/// One share waiting to be shown, and everything needed to show it. A
/// fresh `id` per share (rather than one derived from the payload) so that
/// two shares of the same kind in a row still read as two distinct items
/// to `.sheet(item:)` — otherwise the second would silently not present.
private struct PendingShare: Identifiable {
    enum Kind {
        /// Shared photos (one share can carry several), going through
        /// "create a new card", carrying any photos the user had picked
        /// before leaving for the map app these came back from — see
        /// `MapOpenContext`. That second list is empty for every ordinary
        /// share.
        case photoToBoard([Data], [Data])
        /// Shared photos offered to the card that recently launched
        /// "지도에서 열기" — see `MapOpenContext`.
        case photoToCard(PlaceCard, [Data])
        /// A shared link going through "pick a board, create a new card",
        /// carrying any photos the user had picked before leaving for the
        /// map app that this link came back from — see `MapOpenContext`.
        /// Empty for every ordinary share.
        case linkToBoard(String, [Data])
        case linkToCard(PlaceCard, String)
    }

    let id = UUID()
    var kind: Kind
}

struct MainTabView: View {
    @EnvironmentObject private var storageService: StorageService
    @StateObject private var navigation = AppNavigation()
    @Environment(\.scenePhase) private var scenePhase

    /// One share handed over by the Share Extension (`ShareViewController`,
    /// `PlaceCardsShare` target), waiting to be shown — checked every time
    /// the app becomes active, since the extension runs as a separate
    /// process and hands its payload over via `SharedImportStore`'s file in
    /// their shared App Group container, not directly.
    ///
    /// The payload rides *inside* this value rather than sitting in a
    /// separate `@State` optional that the sheet's content closure reads
    /// back. That difference is the whole fix for the long-standing "공유
    /// 화면이 처음엔 비어 있다가 앱을 다시 열면 제대로 뜬다" report: with
    /// `.sheet(isPresented:)` plus `if let payload` inside the closure,
    /// SwiftUI presents whatever that closure returns *at presentation
    /// time*, and when the optional reads `nil` there what it presents is a
    /// structurally empty sheet. Re-opening the app re-evaluates the body
    /// with the value in place, which is exactly why it looked like it
    /// "fixed itself" on a second look. Note the two sheets ever reported
    /// blank were precisely the two built that way, while the two already
    /// using `.sheet(item:)` never were. Handing the payload in as the
    /// item's own data makes an empty sheet impossible to express — and it
    /// also collapses four separate `.sheet` modifiers on this one view
    /// (itself a well-known way to get sheets that don't present) down to
    /// one.
    @State private var pendingShare: PendingShare?
    /// Shares that arrived while another one was still on screen. Only one
    /// sheet can be up at a time, so the rest wait here rather than
    /// overwriting each other — the old code had every branch flip its own
    /// independent state, so a photo and a link arriving together raced and
    /// one of them was silently dropped.
    @State private var queuedShares: [PendingShare.Kind] = []
    /// True between asking `presentShortly` to show the next share and it
    /// actually landing. Without it, two shares arriving in the same
    /// runloop tick would both be scheduled and the second would replace
    /// the first mid-flight.
    @State private var isPresentationScheduled = false
    /// Set when the user rejects the "이 카드에 추가할까요?" guess
    /// (`MapScreenshotImportSheet`/`MapLinkImportSheet`'s "다른 장소예요"
    /// action) — carries the very same payload back out through the
    /// sheet's `onDismiss` so it can be re-shown as the ordinary
    /// board-picker flow instead of evaporating. Routed through `onDismiss`
    /// because the outgoing sheet has to be fully gone before another can
    /// present in its place.
    @State private var rerouteAfterDismiss: PendingShare.Kind?
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

    /// Set by `OnboardingView` when the user picked "지금 설정하기" on the
    /// AI-key step — consumed once here, since that screen has no
    /// `AppNavigation` of its own to switch tabs with.
    @AppStorage("pendingOpenAIKeySetup") private var pendingOpenAIKeySetup = false

    var body: some View {
        ZStack {
            TabView(selection: $navigation.selectedTab) {
                HomeView(galleryViewModel: GalleryViewModel(storageService: storageService))
                    // 탭 이름은 "갤러리"지만 타입은 그대로 `HomeView`,
                    // 태그도 `.home`이다. 이 저장소에는 이미 다른
                    // `GalleryView`가 있어서 이름을 옮기면 둘이 부딪힌다.
                    .tabItem { Label("갤러리".localized, systemImage: "square.grid.2x2") }
                    .tag(AppTab.home)

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
                Task {
                    await AutoBackupService.runIfDue(storageService: storageService)
                    await CloudBackupService.backup(storageService: storageService)
                }
            } else if newPhase == .background {
                Task { await runBackupsWhileBackgrounding() }
            }
        }
        .task {
            consumePendingKeySetupIfNeeded()
            checkForSharedImage()
            await restoreFromCloudIfNeeded()
            // 클라우드 복원 뒤에 돈다. 복원이 삭제됨에 있던 카드를 도로
            // 들여올 수 있고, 그중 기한이 지난 것은 여기서 정리된다.
            // 삭제됨을 그냥 두면 사진 파일이 영영 남아 저장 공간을 먹는다.
            storageService.purgeExpiredTrash()
            withAnimation { isPerformingStartupWork = false }

            // Fire-and-forget from here on — exporting the current data
            // elsewhere doesn't change anything on screen, so there's no
            // reason to keep the intro up for it. A separate `Task` so it
            // keeps running after this one's own body has already
            // finished, rather than in line ahead of the state change
            // above.
            Task {
                await AutoBackupService.runIfDue(storageService: storageService)
                await CloudBackupService.backup(storageService: storageService)
            }
        }
        .sheet(item: $pendingShare, onDismiss: handleShareDismissed) { share in
            shareSheet(for: share.kind)
        }
        .alert("iCloud에서 복원됨".localized, isPresented: $showingCloudRestoreAlert) {
            Button("확인".localized, role: .cancel) {}
        } message: {
            Text("iCloud에서 이전 백업을 찾아 게시판과 장소를 가져왔습니다.".localized)
        }
        .alert(
            "저장된 데이터를 읽지 못했습니다".localized,
            isPresented: Binding(
                get: { storageService.loadFailureMessage != nil },
                set: { if !$0 { storageService.acknowledgeLoadFailure() } }
            )
        ) {
            Button("확인".localized, role: .cancel) { storageService.acknowledgeLoadFailure() }
        } message: {
            Text(storageService.loadFailureMessage ?? "")
        }
        .alert("인스타그램 링크는 자동으로 인식할 수 없어요".localized, isPresented: $isPresentingInstagramGuidanceAlert) {
            Button("확인".localized, role: .cancel) {}
        } message: {
            Text("게시물을 캡처(스크린샷)해서 \"장소 추가\"의 사진 선택으로 다시 추가해주세요.".localized)
        }
    }

    /// Every payload arrives as a parameter here, so there is no state to
    /// read back and therefore no way to render an empty sheet — see
    /// `pendingShare`.
    @ViewBuilder
    private func shareSheet(for kind: PendingShare.Kind) -> some View {
        switch kind {
        case .photoToBoard(let datas, let photoDatas):
            SharedPhotoBoardPickerSheet(imageDatas: datas, photoDatas: photoDatas)
                .environmentObject(navigation)
        case .photoToCard(let card, let datas):
            MapScreenshotImportSheet(
                card: card,
                imageDatas: datas,
                onCreateNewInstead: { rerouteAfterDismiss = .photoToBoard(datas, []) }
            ) { _ in }
        case .linkToBoard(let text, let photoDatas):
            SharedLinkBoardPickerSheet(linkText: text, photoDatas: photoDatas)
                .environmentObject(navigation)
        case .linkToCard(let card, let text):
            MapLinkImportSheet(
                card: card,
                linkText: text,
                onCreateNewInstead: { rerouteAfterDismiss = .linkToBoard(text, []) }
            ) { _ in }
        }
    }

    /// A rejected "이 카드에 추가할까요?" guess goes back to the front of
    /// the line as the ordinary board-picker flow; otherwise whatever
    /// arrived while this sheet was up gets its turn.
    private func handleShareDismissed() {
        if let rerouteAfterDismiss {
            self.rerouteAfterDismiss = nil
            queuedShares.insert(rerouteAfterDismiss, at: 0)
        }
        presentNextShare()
    }

    /// Queues a share and shows it when nothing else is up.
    private func enqueueShare(_ kind: PendingShare.Kind) {
        queuedShares.append(kind)
        presentNextShare()
    }

    private func presentNextShare() {
        guard !isPresentationScheduled, pendingShare == nil, !queuedShares.isEmpty else { return }
        isPresentationScheduled = true
        let next = queuedShares.removeFirst()
        presentShortly {
            pendingShare = PendingShare(kind: next)
            isPresentationScheduled = false
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
        guard let backup = await CloudBackupService.loadRestorableBackup() else { return }
        try? await BackupService.restore(backup, storageService: storageService)
        showingCloudRestoreAlert = true
    }

    /// Opens the Settings tab once, for a user who just asked to set their
    /// AI key up straight away. Cleared as it's consumed so it never fires
    /// again on a later launch.
    private func consumePendingKeySetupIfNeeded() {
        guard pendingOpenAIKeySetup else { return }
        pendingOpenAIKeySetup = false
        navigation.selectedTab = .settings
    }

    private func checkForSharedImage() {
        // Read once, up front, rather than inside each branch below — the
        // image branch clears this right after checking it, so a link
        // branch reading it afterward would always see it already gone on
        // the (rare) occasion both an image and a link were pending at
        // once. Reading it once here is correct either way.
        let recentCardID = MapOpenContext.recentCardID()

        let sharedImageDatas = SharedImportStore.takePendingImages()
        if !sharedImageDatas.isEmpty {
            if let recentCardID, let card = storageService.placeCard(id: recentCardID) {
                enqueueShare(.photoToCard(card, sharedImageDatas))
            } else {
                // Same lazy read as the link branch below, and for the
                // same reason — see its comment.
                enqueueShare(.photoToBoard(sharedImageDatas, MapOpenContext.recentPhotoDatas()))
            }
            MapOpenContext.clear()
        }

        if let text = SharedImportStore.takePendingLink() {
            // Read only once a link is actually in hand, unlike
            // `recentCardID` above: this loads every stashed photo off
            // disk, and this method runs on every single foreground
            // transition, almost none of which carry a share. `clear()`
            // below deletes them, so they have to be taken into the share
            // here rather than fetched back later.
            let recentPhotoDatas = MapOpenContext.recentPhotoDatas()
            if SharedLinkParser.isInstagramLink(text) {
                presentShortly { isPresentingInstagramGuidanceAlert = true }
            } else if let recentCardID, let card = storageService.placeCard(id: recentCardID) {
                // A shared Google Maps *list* is never "the card you just
                // opened a map for" — it's a whole board's worth of places
                // — so it must not be offered as a merge into that one
                // card. Whether a share is a list can only be told by
                // following the link (see `GoogleMapsListParser`), so this
                // one case pays for that check before choosing a screen;
                // every other share routes immediately as before.
                Task {
                    let isList = await isSharedListLink(text)
                    enqueueShare(isList ? .linkToBoard(text, recentPhotoDatas) : .linkToCard(card, text))
                }
            } else {
                enqueueShare(.linkToBoard(text, recentPhotoDatas))
            }
            MapOpenContext.clear()
        }
    }

    /// Both backups, run as the app is being put away.
    ///
    /// `AutoBackupService.runIfDue` is here as well as on `.active`
    /// because the launch-time run can only ever capture the library as
    /// it was *before* this session's edits — a day's work otherwise sat
    /// unwritten to the backup folder until the next cold launch, which
    /// is the opposite of when a backup is worth having. It still honours
    /// the user's configured interval, so this adds no files beyond the
    /// schedule they already chose; it only adds one more moment to
    /// notice that the interval has elapsed.
    ///
    /// The background-task assertion is what makes either of these worth
    /// starting here at all. A plain `.background` transition leaves only
    /// a couple of seconds before iOS suspends the process, and
    /// `BackupService.exportData` reads and base64-encodes every photo in
    /// the library — on a library of any size that doesn't finish in
    /// time, and a suspended task simply never resumes. (The iCloud
    /// snapshot has been started from here all along, with no assertion,
    /// so this fixes that silently-truncated case too.) The assertion is
    /// ended the moment the work is done rather than left to expire, so
    /// the app isn't held awake any longer than the write needs.
    ///
    /// Running out of time even so is safe, just wasted: both writers use
    /// an atomic write, so the previous backup stays intact rather than
    /// being replaced by a half-written one.
    @MainActor
    private func runBackupsWhileBackgrounding() async {
        let application = UIApplication.shared
        var taskID: UIBackgroundTaskIdentifier = .invalid
        taskID = application.beginBackgroundTask(withName: "PlaceCards.backupOnBackground") {
            // UIKit documents that it calls this on the main thread, which
            // is exactly what `assumeIsolated` asserts — needed because the
            // handler itself carries no isolation, while `UIApplication` is
            // `@MainActor`.
            MainActor.assumeIsolated {
                guard taskID != .invalid else { return }
                application.endBackgroundTask(taskID)
                taskID = .invalid
            }
        }

        await AutoBackupService.runIfDue(storageService: storageService)
        await CloudBackupService.backup(storageService: storageService)

        guard taskID != .invalid else { return }
        application.endBackgroundTask(taskID)
        taskID = .invalid
    }

    /// Only ever true for a Google Maps share — every other source
    /// (Naver, a plain link) has no list concept at all, so nothing else
    /// is worth a network round trip to rule out.
    private func isSharedListLink(_ text: String) async -> Bool {
        guard let parsed = SharedLinkParser.parse(text), parsed.source == .googleMapShare,
              let url = parsed.url else { return false }
        return await GoogleMapsListParser.isSharedList(url)
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
