import SwiftUI

/// Shown when a link (or plain text, e.g. Naver Map's own "공유") was
/// handed to PlaceCards through the Share Extension
/// (`ShareViewController`, `PlaceCardsShare` target) — mirrors
/// `SharedPhotoBoardPickerSheet` closely, just for a shared link instead
/// of a shared photo: shows what's about to be added (see `previewContent`),
/// asks which board to add it to, then opens the normal "장소 추가" flow
/// (`AddPlaceCardView`) for that board with the link already dropped into a
/// candidate row. `AddPlaceCardView` itself already jumps to the resulting
/// card's detail view once it's created (`cameFromSharedInfo` in its own
/// init, driving `AppNavigation.showCardDetail(_:)`) — nothing extra to
/// wire up here for that part.
struct SharedLinkBoardPickerSheet: View {
    let linkText: String

    @EnvironmentObject private var storageService: StorageService
    /// Re-declared and re-injected below purely so `AddPlaceCardView`'s own
    /// sheet actually gets it — `AppNavigation` lives in `MainTabView`'s own
    /// body (`.environmentObject(navigation)` on its `TabView`), not at the
    /// app root the way `StorageService` does, and an `@EnvironmentObject`
    /// like that doesn't reliably survive a *second* level of `.sheet`
    /// presentation (this view is already one sheet deep off `MainTabView`;
    /// its own `AddPlaceCardView` sheet below is a second) without being
    /// explicitly re-attached at each boundary.
    @EnvironmentObject private var navigation: AppNavigation
    @Environment(\.dismiss) private var dismiss
    @State private var selectedBoard: Board?

    /// Held back until `.task` runs once, then flipped on — this view's
    /// own board `List` was reported showing up blank on its very first
    /// presentation (right after cold-launching into a shared link), only
    /// rendering correctly once something else forced a re-layout (the app
    /// backgrounded and foregrounded again). `.task` doesn't run until
    /// after this view's first layout pass, so gating the real content
    /// behind it (rather than showing the `List` straight away) forces
    /// that same kind of second pass automatically, without the user
    /// having to leave and come back. Mirrors `MainTabView.presentShortly`'s
    /// own reasoning for a sibling case of this exact class of bug — a
    /// sheet/state flip landing in the same runloop tick as other startup
    /// work can silently fail to lay out correctly the first time.
    @State private var isReady = false

    /// Resolved once via `.task` — the same "parse the URL directly, fall
    /// back to a page-title fetch for a short link" logic
    /// `MapLinkImportSheet.process()` already uses, run here too so the
    /// user can see *what* they're about to add before picking a board,
    /// instead of only finding out after already committing to one.
    /// Deliberately read-only here: `AddPlaceCardView` (opened after a
    /// board is picked) re-resolves the same link itself as a normal
    /// candidate row, since that's the one place a mismatch actually needs
    /// fixing (via "Google에서 검색" or manual edit) — this is only a
    /// preview.
    @State private var previewState: PreviewState = .loading

    private enum PreviewState {
        case loading
        case resolved(name: String?, address: String?)
        case failure
    }

    var body: some View {
        NavigationStack {
            Group {
                if !isReady {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if storageService.boards.isEmpty {
                    ContentUnavailableView {
                        Label("게시판이 없습니다".localized, systemImage: "square.stack")
                    } description: {
                        Text("먼저 홈에서 게시판을 만들어주세요.".localized)
                    }
                } else {
                    List {
                        Section("공유한 정보".localized) {
                            previewContent
                        }
                        Section("추가할 게시판".localized) {
                            ForEach(storageService.boards) { board in
                                Button {
                                    selectedBoard = board
                                } label: {
                                    Label(board.name, systemImage: board.coverIcon)
                                }
                                .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("공유한 링크를 추가할 게시판".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소".localized) { dismiss() }
                }
            }
        }
        .task {
            isReady = true
            await resolvePreview()
        }
        .sheet(item: $selectedBoard, onDismiss: { dismiss() }) { board in
            AddPlaceCardView(
                viewModel: PlaceCardViewModel(storageService: storageService, boardId: board.id),
                initialLinkText: linkText
            )
            .environmentObject(navigation)
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        switch previewState {
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                Text("공유한 정보를 확인하는 중…".localized)
                    .foregroundStyle(.secondary)
            }
        case .resolved(let name, let address):
            VStack(alignment: .leading, spacing: 2) {
                Text(name ?? linkText)
                    .font(.headline)
                    .lineLimit(2)
                if let address, !address.isEmpty {
                    Text(address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .failure:
            Text("공유한 링크에서 장소 정보를 찾지 못했습니다.".localized)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Same parse-then-fallback shape as `MapLinkImportSheet.process()`,
    /// stopping short of actually applying anything — this only ever
    /// updates `previewState`, never `linkText` itself, since the real
    /// resolution (and any "이름이 다릅니다"-style confirmation) belongs to
    /// `AddPlaceCardView`'s own candidate row once a board is picked.
    private func resolvePreview() async {
        guard var parsed = SharedLinkParser.parse(linkText) else {
            previewState = .failure
            return
        }
        if parsed.name == nil, let url = parsed.url, let title = await LinkMetadataFetcher.fetchTitle(for: url) {
            parsed.name = title.strippingInvisibleFormatCharacters()
        }
        let name = parsed.name?.trimmingCharacters(in: .whitespaces).strippingInvisibleFormatCharacters()
        let address = parsed.address?.trimmingCharacters(in: .whitespaces)
        if (name?.isEmpty ?? true) && (address?.isEmpty ?? true) {
            previewState = .failure
        } else {
            previewState = .resolved(name: (name?.isEmpty == false) ? name : nil, address: address)
        }
    }
}

#Preview {
    SharedLinkBoardPickerSheet(linkText: "https://maps.google.com/example")
        .environmentObject(StorageService())
        .environmentObject(AppNavigation())
}
