import Foundation
import SwiftUI
import UIKit

/// The app's home screen — Lightroom의 라이브러리처럼 두 칸이다. 왼쪽은
/// 앱이 세우는 모음(모든 카드·가져오기·삭제됨)과 사용자가 만든 게시판을
/// 고르는 목록, 오른쪽은 고른 것이 펼쳐지는 곳.
///
/// 게시판을 누르면 예전에는 갤러리 탭으로 건너뛰었다. 이제 건너뛰지 않고
/// 오른쪽 칸이 바뀐다. 아이폰처럼 좁은 화면에서는 `NavigationSplitView`가
/// 한 단으로 접어 주므로, 누르면 밀려 들어왔다가 뒤로가기로 나오는
/// 예전과 거의 같은 느낌이 된다.
///
/// 카드는 이제 게시판 없이도 있을 수 있다(공유로 들어온 것, 게시판이
/// 하나도 없을 때 만든 것) — `boardIds`가 빈 배열인 카드다.
/// 홈 왼쪽 목록에서 고를 수 있는 것. 갤러리로 펼쳐지는 범위 셋과,
/// 갤러리가 아닌 삭제됨이다.
private enum HomeSelection: Hashable {
    case scope(GalleryScope)
    case trash
}

struct HomeView: View {
    @EnvironmentObject private var storageService: StorageService
    @EnvironmentObject private var navigation: AppNavigation
    @State private var isPresentingAddBoard = false
    @State private var boardPendingDelete: Board?
    @State private var boardPendingEdit: Board?
    @State private var selectedSearchResult: PlaceCard?
    @State private var searchQuery = ""
    /// nil means every category, within the current search — set from
    /// `searchCategoryChips` once there are results to narrow.
    @State private var searchCategoryFilter: String?
    @State private var isPresentingImportBoard = false
    /// 왼쪽에서 고른 것. `List(selection:)`이 이걸 채우고, 좁은 화면에서는
    /// 값이 생기는 순간 오른쪽 칸이 밀려 들어온다.
    @State private var sidebarSelection: HomeSelection?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// 오른쪽 칸의 갤러리가 쓰는 것. 갤러리 탭이 쓰는 것과는 다른
    /// 인스턴스라 검색어나 필터는 서로 따로 논다. 무엇을 보여 줄지는
    /// 둘 다 `AppNavigation.galleryScope`에서 받으므로 어긋나지 않는다.
    @StateObject private var galleryViewModel: GalleryViewModel

    init(galleryViewModel: GalleryViewModel) {
        _galleryViewModel = StateObject(wrappedValue: galleryViewModel)
    }

    private var isSearching: Bool {
        !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Every place card (across every board) matching `searchQuery` via
    /// `PlaceCard.matchesSearch` — mirrors every other search box in the
    /// app. Computed ahead of `searchCategoryFilter` so the category
    /// chips below always offer every category actually present in the
    /// *text* match, not just what's left after a category is already
    /// picked.
    private var searchResultsBeforeCategoryFilter: [PlaceCard] {
        storageService.activePlaceCards.filter { $0.matchesSearch(searchQuery) }
    }

    private var searchCategories: [String] {
        let normalized = searchResultsBeforeCategoryFilter.compactMap { card -> String? in
            guard let category = card.category, !category.isEmpty else { return nil }
            return PlaceCategoryIcon.normalizedLabel(for: category)
        }
        return Array(Set(normalized)).sorted()
    }

    private var searchResults: [PlaceCard] {
        guard let searchCategoryFilter else { return searchResultsBeforeCategoryFilter }
        return searchResultsBeforeCategoryFilter.filter { card in
            guard let category = card.category, !category.isEmpty else { return false }
            return PlaceCategoryIcon.normalizedLabel(for: category) == searchCategoryFilter
        }
    }

    /// Every category present across every board's cards — offered as
    /// "카테고리별 보기" chips above the board list, each jumping straight
    /// to the Gallery tab pre-filtered to that category
    /// (`AppNavigation.showInGallery(category:)`).
    private var allCategories: [String] {
        let normalized = storageService.activePlaceCards.compactMap { card -> String? in
            guard let category = card.category, !category.isEmpty else { return nil }
            return PlaceCategoryIcon.normalizedLabel(for: category)
        }
        return Array(Set(normalized)).sorted()
    }

    var body: some View {
        // Lightroom의 라이브러리 화면과 같은 두 칸 구성이다. 왼쪽은
        // 고르는 곳, 오른쪽은 고른 것이 펼쳐지는 곳.
        //
        // `NavigationSplitView`를 쓰면 아이폰처럼 좁은 화면에서 저절로
        // 한 단 목록으로 접히고, 줄을 누르면 오른쪽 칸이 밀려 들어온다
        // — 지금까지의 홈과 거의 같은 느낌이 공짜로 나온다.
        NavigationSplitView {
            sidebar
        } detail: {
            detailPane
        }
        .onChange(of: sidebarSelection) { _, newValue in
            // 고른 것을 갤러리 탭과 지도 탭도 함께 본다. 한 방향으로만
            // 흐르게 둔다 — 반대로도 되돌리면 두 `onChange`가 서로를
            // 깨워 맴돌 수 있고, 지금 범위를 바꾸는 곳은 여기뿐이다.
            if case .scope(let scope) = newValue {
                navigation.galleryScope = scope
            }
        }
        .onAppear {
            // 두 칸이 다 보이는 화면에서는 오른쪽을 비워 두지 않는다.
            // 좁은 화면에서 이러면 앱을 열자마자 오른쪽 칸이 밀려
            // 들어와 목록을 못 보게 되므로 거기서는 비워 둔다.
            if horizontalSizeClass == .regular, sidebarSelection == nil {
                sidebarSelection = .scope(navigation.galleryScope)
            }
        }
    }

    /// 오른쪽 칸. 고른 것이 삭제됨이면 그 화면, 아니면 갤러리다.
    ///
    /// 갤러리는 제 `NavigationStack`을 세우지 않는다 — 여기는
    /// `NavigationSplitView`가 이미 그릇을 대고 있다.
    @ViewBuilder
    private var detailPane: some View {
        // 옵셔널을 먼저 풀고 switch한다. 옵셔널인 채로 `case .scope:`를
        // 쓰는 것은 되기도 하고 아니기도 해서, 컴파일 검증이 CI뿐인
        // 이곳에서는 굳이 시험하지 않는다(CLAUDE.md §1).
        if let sidebarSelection {
            switch sidebarSelection {
            case .scope:
                GalleryView(viewModel: galleryViewModel, providesNavigationStack: false)
            case .trash:
                TrashView()
            }
        } else {
            ContentUnavailableView {
                Label("고른 것이 없습니다".localized, systemImage: "square.grid.2x2")
            } description: {
                Text("왼쪽에서 게시판이나 모음을 고르세요.".localized)
            }
        }
    }

    private var sidebar: some View {
        Group {
            if isSearching {
                searchResultsList
            } else if storageService.boards.isEmpty, storageService.placeCards.isEmpty {
                // 게시판이 없다는 것만으로 빈 화면을 내면 안 된다.
                // 카드는 이제 게시판 없이도 생긴다(공유로 들어온 것,
                // 게시판이 하나도 없을 때 "+"로 만든 것) — 그때 이
                // 화면을 내면 "모든 카드"·"가져오기" 줄이 같이 가려져
                // 그 카드에 닿을 길이 사라진다. 삭제됨에만 남은 경우도
                // 마찬가지라 placeCards를 통째로 본다.
                emptyState
            } else {
                List(selection: $sidebarSelection) {
                    // Lightroom의 앨범 목록과 같은 순서다 — 앱이
                    // 스스로 세우는 항목이 위, 사용자가 만든 것이
                    // 아래. 둘을 한 List에 두되 Section으로 가른다.
                    Section {
                        SystemCollectionRow(
                            icon: "square.grid.2x2",
                            title: "모든 카드".localized,
                            count: storageService.activePlaceCards.count
                        )
                        .tag(HomeSelection.scope(.all))

                        // 다른 앱에서 공유해 들어온 정보로 만들어진
                        // 카드. 보드가 아니라 출신으로 모은 것이라, 이
                        // 카드들은 제 보드에도 그대로 들어 있다.
                        // 파일에서 게시판을 들여오는 일은 예전처럼
                        // 오른쪽 위 "+" 메뉴에 있다.
                        SystemCollectionRow(
                            icon: "square.and.arrow.down",
                            title: "가져오기".localized,
                            count: storageService.importedPlaceCards.count
                        )
                        .tag(HomeSelection.scope(.imported))

                        SystemCollectionRow(
                            icon: "trash",
                            title: "삭제됨".localized,
                            count: storageService.deletedPlaceCards.count
                        )
                        .tag(HomeSelection.trash)
                    } header: {
                        sectionHeader("PinSpots")
                    }
                    .listRowBackground(Theme.panel)
                    .listRowSeparator(.hidden)

                    categoryBrowseSection

                    // 게시판이 하나도 없으면 머리만 덩그러니
                    // 남으므로 구역째 내린다. 공유로만 쓰는
                    // 사람에게는 흔한 상태다.
                    if !storageService.boards.isEmpty {
                        Section {
                            ForEach(storageService.boards) { board in
                                BoardRow(board: board, cardCount: storageService.placeCards(inBoard: board.id).count)
                                    .tag(HomeSelection.scope(.board(board.id)))
                                    .swipeActions(edge: .trailing) {
                                        // Mirrors Peragra: deleting is only offered
                                        // once the board has no saved place cards,
                                        // so a swipe can never silently take place
                                        // cards (and their photos) with it.
                                        if storageService.placeCards(inBoard: board.id).isEmpty {
                                            Button(role: .destructive) {
                                                boardPendingDelete = board
                                            } label: {
                                                Label("삭제".localized, systemImage: "trash")
                                            }
                                        }
                                    }
                                    .swipeActions(edge: .leading) {
                                        Button {
                                            boardPendingEdit = board
                                        } label: {
                                            Label("수정".localized, systemImage: "pencil")
                                        }
                                        .tint(.blue)
                                        ExportBoardMenu(board: board, storageService: storageService)
                                    }
                            }
                        } header: {
                            sectionHeader("사용자 보드".localized)
                        }
                        .listRowBackground(Theme.panel)
                        .listRowSeparator(.hidden)
                    }

                    // Last row of the list, so it sits under the
                    // content rather than pinned over it — the same
                    // place Settings has always put it.
                    Section {
                        CreditFooter()
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Theme.panel)
            }
        }
        .navigationTitle("PinSpots")
        // `.always` so search stays visible without a pull-down/
        // scroll — matches Gallery.
        .searchable(text: $searchQuery, placement: .navigationBarDrawer(displayMode: .always), prompt: "카드 검색".localized)
        .onChange(of: searchQuery) { _, newValue in
            if newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                searchCategoryFilter = nil
            }
        }
        .navigationDestination(item: $selectedSearchResult) { card in
            PlaceCardDetailView(card: card)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        isPresentingAddBoard = true
                    } label: {
                        Label("새 게시판".localized, systemImage: "plus")
                    }
                    Button {
                        isPresentingImportBoard = true
                    } label: {
                        Label("게시판 가져오기".localized, systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Label("추가".localized, systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isPresentingAddBoard) {
            AddBoardSheet()
        }
        .sheet(isPresented: $isPresentingImportBoard) {
            ImportBoardSheet()
        }
        .sheet(item: $boardPendingEdit) { board in
            EditBoardSheet(board: board)
        }
        .confirmationDialog(
            "비어있는 게시판 \"".localized + (boardPendingDelete?.name ?? "") + "\"을 삭제할까요?".localized,
            isPresented: Binding(
                get: { boardPendingDelete != nil },
                set: { if !$0 { boardPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("삭제".localized, role: .destructive) {
                if let board = boardPendingDelete {
                    storageService.deleteBoard(board)
                }
                boardPendingDelete = nil
            }
            Button("취소".localized, role: .cancel) { boardPendingDelete = nil }
        }
    }

    /// Lightroom의 섹션 제목 — 굵고 크게, 그리고 `.textCase(nil)`.
    /// List의 기본 헤더는 한글에는 티가 안 나지만 "PinSpots" 같은
    /// 로마자를 대문자로 바꿔 버린다.
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3.bold())
            .foregroundStyle(Theme.primaryText)
            .textCase(nil)
            .padding(.top, 8)
            .padding(.bottom, 2)
            // `.plain` 목록의 헤더는 스크롤하면 붙어 있고 기본 배경이
            // 반투명 머티리얼이라, 지정하지 않으면 사진 위를 지날 때
            // 밝은 띠로 보인다. 아래 `maxWidth: .infinity`는 Text에
            // 건 것이라 안전하다 — 버튼에 걸면 탭 영역이 같이 퍼진다.
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.panel)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("게시판이 없습니다".localized, systemImage: "square.stack")
        } description: {
            Text("먼저 게시판을 만들고, 그 안에 장소 카드를 추가해보세요.".localized)
        } actions: {
            Button("첫 게시판 만들기".localized) { isPresentingAddBoard = true }
                .buttonStyle(.borderedProminent)
        }
    }

    /// Sits above the board list — tapping a category jumps straight to
    /// the Gallery tab pre-filtered to it (across every board, not just
    /// whichever one that place happens to live in). Hidden when no card
    /// anywhere has a category yet.
    @ViewBuilder
    private var categoryBrowseSection: some View {
        if !allCategories.isEmpty {
            Section("카테고리별 보기".localized) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(allCategories, id: \.self) { category in
                            searchCategoryChip(title: category, isSelected: false) {
                                navigation.showInGallery(category: category)
                            }
                        }
                    }
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    /// Shown instead of the board list while `searchQuery` isn't empty —
    /// every matching place card across every board, not just the board
    /// names themselves (which is all the old board-name search covered).
    @ViewBuilder
    private var searchResultsList: some View {
        if searchResults.isEmpty {
            ContentUnavailableView.search
        } else {
            List {
                if searchCategories.count > 1 {
                    Section {
                        searchCategoryChips
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
                ForEach(searchResults) { card in
                    // No NavigationLink wrapping the row — see
                    // `BoardDetailView.cardRow(_:)`'s own comment: it
                    // claims the whole row as its tap target and swallows
                    // taps on PlaceCardListRow's own favorite/visited
                    // buttons before they fire. A plain .onTapGesture
                    // instead only fires for points the row's own
                    // Buttons don't already claim.
                    PlaceCardListRow(card: card)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedSearchResult = card }
                }
            }
            .listStyle(.plain)
        }
    }

    /// "전체" plus every category present in the current text match —
    /// tapping one narrows `searchResults` further, same idea as
    /// `PlaceStatusFilterBar`'s category menu but as chips, since this
    /// list has no other filter/sort controls competing for space.
    private var searchCategoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                searchCategoryChip(title: "전체".localized, isSelected: searchCategoryFilter == nil) {
                    searchCategoryFilter = nil
                }
                ForEach(searchCategories, id: \.self) { category in
                    searchCategoryChip(title: category, isSelected: searchCategoryFilter == category) {
                        searchCategoryFilter = category
                    }
                }
            }
        }
    }

    private func searchCategoryChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Lightroom 왼쪽 목록의 "모든 사진"·"가져오기"에 해당하는, 앱이 스스로
/// 세우는 항목 한 줄. 사용자가 만든 보드(`BoardRow`)와 달리 표지가 없으므로
/// 왼쪽은 언제나 아이콘 칸이다 — 둘의 칸 크기와 모서리를 맞춰야 한 목록에
/// 섞여도 줄이 어긋나 보이지 않는다.
private struct SystemCollectionRow: View {
    let icon: String
    let title: String
    /// nil이면 개수 줄을 아예 두지 않는다. "가져오기"는 모아 놓은 것이
    /// 아니라 하는 일이라 셀 것이 없다.
    let count: Int?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(Theme.primaryText)
                .frame(width: 48, height: 48)
                .background(Theme.tile)
                .clipShape(RoundedRectangle(cornerRadius: Theme.tileCorner))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(Theme.primaryText)
                if let count {
                    Text(count.formatted())
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct BoardRow: View {
    let board: Board
    let cardCount: Int

    /// "장소 12개". 문장을 프로퍼티로 빼 두는 건 이 저장소의 관례다 —
    /// `.localized` 조각을 `+`로 이어 붙인 식을 뷰 본문에 그대로 두면
    /// 타입 검사가 시간 안에 끝나지 않은 적이 있다(CLAUDE.md §1).
    private var countText: String {
        "장소 ".localized + cardCount.formatted() + "개".localized
    }

    var body: some View {
        // 칸 크기·모서리·글자 크기는 `SystemCollectionRow`와 같아야 한다.
        // 한 목록에 위아래로 놓이므로 하나라도 어긋나면 눈에 띈다.
        HStack(spacing: 14) {
            Image(systemName: board.coverIcon)
                .font(.system(size: 20))
                .foregroundStyle(Theme.primaryText)
                .frame(width: 48, height: 48)
                .background(Theme.tile)
                .clipShape(RoundedRectangle(cornerRadius: Theme.tileCorner))

            VStack(alignment: .leading, spacing: 3) {
                Text(board.name)
                    .font(.body)
                    .foregroundStyle(Theme.primaryText)
                if !board.subtitle.isEmpty {
                    Text(board.subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                Text(countText)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

/// "내보내기" swipe action — ported from Peragra's own `ExportBoardMenu`
/// (`TripsListView.swift`): a board plus its own place cards, as one
/// self-contained JSON file (`BackupService.exportBoard`), either shared
/// via the system share sheet or copied as raw text. The file is
/// prepared once the menu itself appears (`.task`), which for a `Menu`
/// inside `.swipeActions` only actually happens once the row is swiped
/// open — not eagerly for every board in the list.
private struct ExportBoardMenu: View {
    let board: Board
    let storageService: StorageService
    @State private var exportFileURL: URL?
    @State private var csvFileURL: URL?

    var body: some View {
        Menu {
            Button {
                Task { await copyAsText() }
            } label: {
                Label("텍스트로 복사".localized, systemImage: "doc.on.doc")
            }
            if let exportFileURL {
                ShareLink(item: exportFileURL) {
                    Label("파일로 공유".localized, systemImage: "square.and.arrow.up")
                }
            }
            // The JSON above restores this app and nothing else. One board
            // is usually one trip, which is exactly the unit someone wants
            // in a spreadsheet, so the CSV sits right next to it.
            if let csvFileURL {
                ShareLink(item: csvFileURL) {
                    Label("CSV로 공유".localized, systemImage: "tablecells")
                }
            }
        } label: {
            Label("내보내기".localized, systemImage: "square.and.arrow.up")
        }
        .tint(.blue)
        .task { await prepareFile() }
    }

    private func prepareFile() async {
        if let data = try? await BackupService.exportBoard(board, storageService: storageService) {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(BackupService.boardFilename(for: board))
            try? data.write(to: url, options: .atomic)
            exportFileURL = url
        }

        let csv = CSVExport.csv(boards: [board], placeCards: storageService.placeCards(inBoard: board.id))
        let csvURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(CSVExport.filename(board: board))
        try? csv.write(to: csvURL, options: .atomic)
        csvFileURL = csvURL
    }

    private func copyAsText() async {
        guard let data = try? await BackupService.exportBoard(board, storageService: storageService),
              let text = String(data: data, encoding: .utf8) else { return }
        UIPasteboard.general.string = text
    }
}

#Preview {
    // 프리뷰의 StorageService는 한 번만 만들어 둘 다에게 준다 — 목록과
    // 오른쪽 칸이 서로 다른 저장소를 보면 빈 화면이 나온다.
    let storage = StorageService()
    return HomeView(galleryViewModel: GalleryViewModel(storageService: storage))
        .environmentObject(storage)
        .environmentObject(AppNavigation())
}
