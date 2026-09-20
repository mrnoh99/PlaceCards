import SwiftUI

/// Shown when a link (or plain text, e.g. Naver Map's own "공유") was
/// handed to PlaceCards through the Share Extension
/// (`ShareViewController`, `PlaceCardsShare` target) — mirrors
/// `SharedPhotoBoardPickerSheet` closely, just for a shared link instead
/// of a shared photo: opens the normal "장소 추가" flow
/// (`AddPlaceCardView`) with the link already dropped into a candidate row.
///
/// 게시판은 묻지 않는다. 공유로 들어온 카드는 일단 "가져오기"로 가고,
/// 게시판은 나중에 거기서 정한다. 단 **목록 공유는 예외**다 — 그쪽은
/// "어느 게시판에 넣을까"가 아니라 "만들 게시판 이름이 무엇인가"이고,
/// 장소 수십 개가 이름 없는 곳으로 쏟아지면 안 되므로 그대로 묻는다. `AddPlaceCardView` itself already jumps to the resulting
/// card's detail view once it's created (`cameFromSharedInfo` in its own
/// init, driving `AppNavigation.showCardDetail(_:)`) — nothing extra to
/// wire up here for that part.
struct SharedLinkBoardPickerSheet: View {
    let linkText: String
    /// Photos the user had already picked in `AddPlaceCardView` before
    /// leaving for a map app to find where they were taken — handed
    /// straight back into the card this link builds, so the trip out to
    /// the map doesn't cost them the photos that prompted it. Empty for
    /// every ordinary share; see `MapOpenContext`.
    var photoDatas: [Data] = []

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
    /// 목록 가져오기가 만든 게시판과 그 목록을 한 덩어리로 들고 간다.
    /// 둘을 따로 두고 시트 안에서 `if let`으로 꺼내면
    /// 00_UI개편_기초.md §2.1이 적어 둔 "빈 시트" 모양이 된다 — 표시
    /// 시점에 그 옵셔널이 nil이면 SwiftUI는 구조적으로 빈 시트를 띄운다.
    private struct ListImport: Identifiable {
        let id = UUID().uuidString
        let board: Board
        let list: SharedPlaceList
    }

    @State private var pendingListImport: ListImport?

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
        /// The share turned out to be a whole Google Maps list rather than
        /// a single place — a different thing to import, and a different
        /// thing to import it *into* (see `listBoardName`).
        case list(SharedPlaceList)
        case failure
    }

    /// The board an imported list will be created as — prefilled with the
    /// list's own name, since a Google Maps list and a PinSpots board are
    /// the same idea, but editable before committing: the user may already
    /// have their own name for it, and Google's list names are often
    /// shorthand only the owner understands.
    @State private var listBoardName = ""

    var body: some View {
        Group {
            switch previewState {
            case .loading:
                // 목록 공유인지 장소 하나인지는 링크를 따라가 봐야 알 수
                // 있고, 그 답에 따라 다음 화면이 갈린다. 그때까지만
                // 기다린다.
                framed(title: "공유한 링크".localized) {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .list(let list):
                framed(title: "공유한 목록 가져오기".localized) {
                    listContent(list)
                }
            case .resolved, .failure:
                // 게시판을 묻지 않으므로 미리보기도 보여 줄 일이 없다 —
                // 무엇이 들어오는지는 바로 다음 화면이 그대로 보여 준다.
                // 예전에는 게시판을 고르기 *전에* 확인시키려고 있었다.
                AddPlaceCardView(
                    viewModel: PlaceCardViewModel(
                        storageService: storageService, boardId: nil, cameFromShare: true
                    ),
                    initialImageDatas: photoDatas,
                    initialLinkText: linkText
                )
                .environmentObject(navigation)
            }
        }
        .task { await resolvePreview() }
        .sheet(item: $pendingListImport, onDismiss: { dismiss() }) { item in
            AddPlaceCardView(
                viewModel: PlaceCardViewModel(
                    storageService: storageService, boardId: item.board.id, cameFromShare: true
                ),
                initialList: item.list
            )
            .environmentObject(navigation)
        }
    }

    /// 이 시트가 스스로 띄우는 화면들의 테두리. `AddPlaceCardView`는
    /// 제 NavigationStack을 들고 있으므로 여기를 거치지 않는다 — 겹쳐
    /// 놓으면 제목 줄이 두 개가 된다.
    private func framed<Content: View>(
        title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationStack {
            content()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("취소".localized) { dismiss() }
                    }
                }
        }
    }

    /// The whole-list import screen: what the list is, every place it
    /// turned out to hold, and the board it's about to become. Shown
    /// instead of the board picker — a list has no reason to be filed into
    /// an existing board, it *is* the board.
    @ViewBuilder
    private func listContent(_ list: SharedPlaceList) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text(list.name)
                        .font(.headline)
                    if let ownerName = list.ownerName {
                        Text(ownerName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("공유한 목록".localized)
            } footer: {
                // Google's own "N places" count is the only way to tell
                // that the share didn't carry every entry — a subset is
                // fine to import, but never silently: without this the
                // missing places would just quietly not exist.
                if !list.isComplete {
                    Text(partialImportNotice(list))
                }
            }

            Section("만들 게시판".localized) {
                TextField("게시판 이름".localized, text: $listBoardName)
            }

            Section(placesSectionTitle(list)) {
                ForEach(list.places) { place in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name)
                            .font(.subheadline)
                        if let address = place.address {
                            Text(address)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                Button("이 목록 가져오기".localized) {
                    importList(list)
                }
                .disabled(listBoardName.trimmingCharacters(in: .whitespaces).isEmpty || list.places.isEmpty)
            } footer: {
                Text("가져온 장소는 Google에서 하나씩 확인해 평점·연락처·영업시간·사진까지 채웁니다. 장소 수만큼 본인의 Google Places API 키가 사용됩니다.".localized)
            }
        }
    }

    /// States the limit and stops there — it doesn't ask the user to go
    /// chase the remainder. What a shared list hands over is what gets
    /// imported; the places Google leaves out of the share simply aren't
    /// recoverable from it (see `GoogleMapsListParser`), so turning that
    /// into a chore for the user would be worse than saying so plainly.
    /// The cap is Google's and measured at 20, but the number is taken
    /// from what actually arrived rather than written into the sentence,
    /// so this stays true if that ever changes.
    ///
    /// Built in separate statements rather than one `+` chain inside the
    /// view body — the type checker gives up on a chain this long there
    /// ("unable to type-check this expression in reasonable time"), which
    /// is the same reason `MapScreenshotImportSheet.nameChangeAlertMessage`
    /// exists as its own property.
    private func partialImportNotice(_ list: SharedPlaceList) -> String {
        let stated = "\(list.statedCount ?? list.places.count)"
        let recovered = "\(list.places.count)"
        let prefix = "이 목록 ".localized
        let middle = "개 중 ".localized
        let suffix = "개를 가져옵니다. 구글이 공유 링크에 담아 보내는 최대 개수입니다.".localized
        return prefix + stated + middle + recovered + suffix
    }

    private func placesSectionTitle(_ list: SharedPlaceList) -> String {
        let prefix = "가져올 장소 (".localized
        let count = "\(list.places.count)"
        let suffix = "개)".localized
        return prefix + count + suffix
    }

    /// Creates the board, then hands the list to `AddPlaceCardView` — which
    /// seeds one reviewable row per place and runs the bulk Places
    /// verification, so nothing is written until the user confirms there.
    private func importList(_ list: SharedPlaceList) {
        let board = Board(
            name: listBoardName.trimmingCharacters(in: .whitespaces),
            subtitle: list.ownerName.map { "Google Maps · ".localized + $0 } ?? "Google Maps",
            coverIcon: "map"
        )
        storageService.saveBoard(board)
        pendingListImport = ListImport(board: board, list: list)
    }

    @ViewBuilder
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
        // A shared Google Maps *list* arrives as an ordinary-looking share
        // link (usually a `maps.app.goo.gl` short one), so it can only be
        // told apart from a single place by following it — which is why
        // this is decided here, during the preview fetch that was going to
        // happen anyway, rather than up front in `MainTabView`.
        if parsed.source == .googleMapShare, let url = parsed.url,
           let list = await GoogleMapsListParser.fetchList(from: url, sharedText: linkText),
           !list.places.isEmpty {
            listBoardName = list.name
            previewState = .list(list)
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
