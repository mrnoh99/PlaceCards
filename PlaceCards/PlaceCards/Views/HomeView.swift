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
    /// 앱이 하나 만들어 내려보낸다(`PlaceCardsApp`). 설정 화면의 "지금
    /// 맞추기"와 **같은** 것이라, 한쪽이 도는 동안 다른 쪽 단추도 같이
    /// 돌고 두 번 시작되지 않는다.
    @EnvironmentObject private var cloudSync: CloudSyncService
    @State private var isPresentingAddBoard = false
    @State private var boardPendingDelete: Board?
    @State private var boardPendingExport: Board?
    @State private var boardPendingEdit: Board?
    @State private var selectedSearchResult: PlaceCard?
    @State private var searchQuery = ""
    /// nil means every category, within the current search — set from
    /// `searchCategoryChips` once there are results to narrow.
    @State private var searchCategoryFilter: String?
    @State private var isPresentingImportBoard = false
    @State private var isPresentingCategoryEditor = false
    @State private var isPresentingBoardReorder = false
    /// 동기화가 끝난 뒤 알릴 말. 알릴 것이 없으면 nil로 남는다 —
    /// `SyncState.deservesNotice` 주석 참고.
    @State private var syncNotice: String?
    /// `CategoryPickerSheet`이 고른 것을 받는 자리. 그 화면은 고르기와
    /// 편집을 같이 하므로 바인딩이 필요하고, 여기서는 고른 것을 그대로
    /// 갤러리 필터로 넘긴 뒤 비운다.
    @State private var categoryEditorPick: String?
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
    /// (`browse(category:)`).
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
            // 오른쪽 칸은 제 `NavigationStack`을 가져야 한다. 갤러리가 이
            // 안에서 카드 상세로 밀고 들어가기 때문이다.
            //
            // `NavigationSplitView`의 칸은 저절로 스택이 되지 않는다.
            // 스택 없이 `navigationDestination`을 쓰면 SwiftUI가 그것을
            // "다음 칸"에 대한 지시로 읽는데, 오른쪽 칸 다음에는 칸이
            // 없어서 경고를 내고 밀기가 동작하지 않는다.
            NavigationStack {
                detailPane
            }
        }
        .onChange(of: sidebarSelection) { _, newValue in
            // 고른 것을 갤러리 탭과 지도 탭도 함께 본다. 한 방향으로만
            // 흐르게 둔다 — 반대로도 되돌리면 두 `onChange`가 서로를
            // 깨워 맴돌 수 있고, 지금 범위를 바꾸는 곳은 여기뿐이다.
            if case .scope(let scope) = newValue {
                navigation.galleryScope = scope
            }
        }
        // 갤러리 탭이 없어졌으므로 갤러리를 부르는 길이 모두 여기로
        // 온다. 카테고리 칩(`galleryCategoryFilter`)과 방금 만든 카드
        // (`pendingDetailCardID`) 둘 다, 오른쪽 칸이 갤러리를 보고 있지
        // 않으면 아무 일도 일어나지 않은 것처럼 보인다 — 삭제됨을 보고
        // 있었거나 아직 아무것도 안 골랐을 때다. 그때 옮겨 준다.
        .onChange(of: navigation.galleryCategoryFilter) { _, newValue in
            if newValue != nil { showGalleryInDetail() }
        }
        .onChange(of: navigation.pendingDetailCardID) { _, newValue in
            if newValue != nil { showGalleryInDetail() }
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

    /// 오른쪽 칸을 갤러리로 돌린다. 이미 갤러리를 보고 있으면 고른 것을
    /// 건드리지 않는다 — 보고 있던 게시판이 "모든 카드"로 튕기면 안 된다.
    /// 카테고리 칩 — 범위를 "모든 카드"로 되돌린 뒤 그 카테고리만 남긴다.
    ///
    /// 칩 목록은 처음부터 **모든 카드**에서 모은 것이다(`allCategories`).
    /// 누를 때 범위를 그대로 두면, 보드를 보고 나온 뒤에는 그 보드 안에서만
    /// 걸러져 칩에 보이던 카드가 사라진다 — 목록과 결과가 어긋난다.
    ///
    /// `galleryScope`와 `sidebarSelection`을 같이 옮긴다. 하나만 옮기면
    /// 왼쪽 목록은 보드를 짚고 있는데 오른쪽은 전체를 보여 주는 꼴이 된다.
    private func browse(category: String) {
        navigation.galleryScope = .all
        sidebarSelection = .scope(.all)
        // 갤러리에 곧장 손대지 않고 맡겨만 둔다. 좁은 화면에서는 이
        // 칩을 누른 *뒤에야* 갤러리가 만들어지므로, 지금 뷰모델을
        // 맞춰 봐야 그 뒤에 오는 `.onAppear`가 덮어쓴다.
        navigation.galleryCategoryFilter = category
    }

    private func showGalleryInDetail() {
        if case .scope = sidebarSelection { return }
        sidebarSelection = .scope(navigation.galleryScope)
    }

    /// 오른쪽 칸의 내용. 고른 것이 삭제됨이면 그 화면, 아니면 갤러리다.
    ///
    /// 갤러리는 제 `NavigationStack`을 세우지 않는다 — 이 셋을 감싸는
    /// 스택이 바로 위에 하나 있고, 그 안에 또 세우면 두 겹이 된다.
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
                                    // **조건 없이 하나는 준다.** 예전에는 카드가
                                    // 있는 보드에서 이 묶음이 비었는데, 내용이 빈
                                    // `swipeActions`는 아무것도 안 내놓는 대신
                                    // 그 밀기가 줄 선택으로 떨어진다 — 아이폰에서
                                    // "왼쪽으로 밀면 갤러리로 넘어간다"가 그것이다.
                                    //
                                    // **빈 보드만 지운다는 규칙은 그대로다.** 259차가
                                    // 그 규칙을 조건과 함께 없앴는데 틀렸다.
                                    // `deleteBoard`가 카드를 안 데려가는 것은 맞지만,
                                    // 그게 근거가 아니다 — **카드는 여러 보드에 들어갈
                                    // 수 있고**, 그래서 보드만 지우면 카드가 어디에도
                                    // 속하지 않은 채 남는다. 먼저 비우게 해야 한다.
                                    //
                                    // 규칙은 단추를 숨겨서가 아니라 **왜 못 지우는지
                                    // 말해서** 지킨다. 숨기면 위의 빈 묶음 문제가
                                    // 돌아오고, 사용자는 왜 안 나오는지도 모른다.
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            boardPendingDelete = board
                                        } label: {
                                            Label("삭제".localized, systemImage: "trash")
                                        }
                                    }
                                    .swipeActions(edge: .leading) {
                                        Button {
                                            boardPendingEdit = board
                                        } label: {
                                            Label("수정".localized, systemImage: "pencil")
                                        }
                                        .tint(.blue)
                                    }
                                    // 내보내기는 **길게 눌러** 연다. 예전에는
                                    // `Menu`를 `swipeActions` 안에 넣었는데, 그
                                    // 자리는 `Button`을 기대하는 곳이라 아이폰에서
                                    // 아예 안 나왔다(사용자 신고: 오른쪽으로 밀면
                                    // 수정만 보인다).
                                    .contextMenu {
                                        Button {
                                            boardPendingEdit = board
                                        } label: {
                                            Label("수정".localized, systemImage: "pencil")
                                        }
                                        Button {
                                            boardPendingExport = board
                                        } label: {
                                            Label("내보내기".localized, systemImage: "square.and.arrow.up")
                                        }
                                        Button(role: .destructive) {
                                            boardPendingDelete = board
                                        } label: {
                                            Label("삭제".localized, systemImage: "trash")
                                        }
                                    }
                            }
                        } header: {
                            HStack {
                                sectionHeader("사용자 보드".localized)
                                Spacer()
                                Button {
                                    isPresentingBoardReorder = true
                                } label: {
                                    Image(systemName: "arrow.up.arrow.down")
                                        .accessibilityLabel("보드 순서 바꾸기".localized)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(Theme.accent)
                            }
                            .background(Theme.panel)
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
        // 검색 결과는 밀지 않고 띄운다.
        //
        // `NavigationSplitView`의 칸에서 `navigationDestination`을 쓰면
        // SwiftUI는 그것을 "다음 칸"에 대한 지시로 읽는다. 왼쪽에서 쓰면
        // 오른쪽 칸을 갈아 끼우겠다는 뜻이 되는데, 오른쪽 칸은 이미 왼쪽
        // 목록의 선택이 정하고 있어 둘이 같은 자리를 놓고 다툰다. 게다가
        // 오른쪽 칸은 제 `NavigationStack`을 가지므로 그 지시가 갈 곳도
        // 없어진다.
        //
        // 모달은 칸 구조와 무관하다. 지도 탭이 같은 화면을 띄우는 방식과
        // 같게 맞췄다.
        .sheet(item: $selectedSearchResult) { card in
            NavigationStack {
                PlaceCardDetailView(card: card)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("닫기".localized) { selectedSearchResult = nil }
                        }
                    }
            }
        }
        .toolbar {
            // 설정 안쪽까지 들어가야 누를 수 있으면 자주 누르지 않게 되고,
            // 안 누르면 기기 사이가 벌어진다. 라이브러리 전체에 걸린 일이라
            // 게시판 목록(이 화면)이 제자리다 — 갤러리 툴바는 고른 카드에
            // 대한 것들로 이미 차 있다.
            ToolbarItem(placement: .primaryAction) {
                if cloudSync.syncState.isBusy {
                    ProgressView()
                } else {
                    Button {
                        Task { await cloudSync.syncNow(storageService: storageService) }
                    } label: {
                        Label("지금 맞추기".localized, systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            }
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
        // 끝났다고 늘 띄우지는 않는다 — `deservesNotice` 주석 참고.
        .onChange(of: cloudSync.syncState) { _, state in
            guard state.deservesNotice else { return }
            syncNotice = state.progressText
        }
        .alert(
            "동기화".localized,
            isPresented: Binding(
                get: { syncNotice != nil },
                set: { if !$0 { syncNotice = nil } }
            )
        ) {
            Button("확인".localized, role: .cancel) { syncNotice = nil }
        } message: {
            Text(syncNotice ?? "")
        }
        .sheet(isPresented: $isPresentingAddBoard) {
            AddBoardSheet()
        }
        .sheet(isPresented: $isPresentingImportBoard) {
            ImportBoardSheet()
        }
        .sheet(isPresented: $isPresentingCategoryEditor) {
            CategoryPickerSheet(categories: allCategories, selection: $categoryEditorPick)
        }
        .sheet(isPresented: $isPresentingBoardReorder) {
            BoardReorderSheet()
        }
        .onChange(of: categoryEditorPick) { _, newValue in
            guard let newValue else { return }
            categoryEditorPick = nil
            browse(category: newValue)
        }
        .sheet(item: $boardPendingEdit) { board in
            EditBoardSheet(board: board)
        }
        .sheet(item: $boardPendingExport) { board in
            ExportBoardSheet(board: board, storageService: storageService)
        }
        .confirmationDialog(
            deletePendingBoardIsEmpty
                ? "게시판 \"".localized + (boardPendingDelete?.name ?? "") + "\"을 삭제할까요?".localized
                : "게시판 \"".localized + (boardPendingDelete?.name ?? "") + "\"을 지울 수 없습니다".localized,
            isPresented: Binding(
                get: { boardPendingDelete != nil },
                set: { if !$0 { boardPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if deletePendingBoardIsEmpty {
                Button("삭제".localized, role: .destructive) {
                    if let board = boardPendingDelete {
                        storageService.deleteBoard(board)
                    }
                    boardPendingDelete = nil
                }
                Button("취소".localized, role: .cancel) { boardPendingDelete = nil }
            } else {
                Button("확인".localized) { boardPendingDelete = nil }
            }
        } message: {
            Text(deletePendingBoardIsEmpty
                 ? "되돌릴 수 없습니다.".localized
                 : "장소가 들어 있는 게시판은 지울 수 없습니다. 장소는 여러 게시판에 들어갈 수 있어서, 게시판만 지우면 그 장소가 어디에도 속하지 않은 채 남습니다. 먼저 장소를 옮기거나 빼주세요.".localized)
        }
    }

    /// 지우려는 게시판이 비어 있나. `boardPendingDelete`가 없으면 대화상자도
    /// 안 뜨므로 그때 값은 쓰이지 않는다.
    private var deletePendingBoardIsEmpty: Bool {
        guard let board = boardPendingDelete else { return true }
        return storageService.placeCards(inBoard: board.id).isEmpty
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

    /// Sits above the board list — tapping a category narrows the gallery
    /// to it (across every board, not just whichever one that place happens
    /// to live in). Hidden when no card anywhere has a category yet.
    ///
    /// 머리에 편집 단추가 붙는다. 카테고리는 AI가 읽어 온 자유 문자열이라
    /// "식당"/"레스토랑"/"음식점"처럼 사실상 같은 것이 여럿으로 갈라지기
    /// 쉬운데, 그것을 고칠 자리가 갤러리 안쪽에만 있었다. 목록을 보는
    /// 자리에서 바로 닿게 한다.
    @ViewBuilder
    private var categoryBrowseSection: some View {
        if !allCategories.isEmpty {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(allCategories, id: \.self) { category in
                            searchCategoryChip(title: category, isSelected: false) {
                                browse(category: category)
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    sectionHeader("카테고리별 보기".localized)
                    Spacer()
                    Button {
                        isPresentingCategoryEditor = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .accessibilityLabel("카테고리 편집".localized)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                }
                .background(Theme.panel)
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
            // 표지 사진이 있으면 그것, 없으면 기호. 크기·모서리는 둘이
            // 같아야 한다 — 한 목록에 섞여 놓인다.
            //
            // 썸네일로 줄여 읽는다(`loadThumbnail`). 48pt 칸에 원본을
            // 통째로 디코딩하면 목록을 넘길 때마다 그만큼을 버린다 —
            // `00_UI개편_기초.md` §2.9가 적어 둔 그 종류다.
            Group {
                if let path = board.coverPhotoPath,
                   let image = MediaStore.loadThumbnail(fileName: path, maxPixelSize: 144) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: board.coverIcon)
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.primaryText)
                }
            }
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

/// 게시판 하나를 내보내는 시트 — 길게 눌러 나오는 "내보내기"가 연다.
///
/// 예전에는 `.swipeActions` 안의 `Menu`(`ExportBoardMenu`)였다. 그 자리는
/// `Button`을 기대하는 곳이라 **아이폰에서는 아예 렌더되지 않았고**, 내보내기에
/// 닿을 길이 없었다(사용자 신고: "오른쪽으로 밀면 edit"만 나온다).
///
/// 시트로 옮기면서 준비 시점도 제자리를 찾았다. 예전에는 메뉴가 뜨기만 하면
/// `.task`가 돌아서 **행을 스와이프해 여는 것만으로** 그 게시판의 사진이 전부
/// 복사됐다. 이제는 사용자가 내보내기를 고른 뒤에만 돈다.
private struct ExportBoardSheet: View {
    let board: Board
    let storageService: StorageService
    @Environment(\.dismiss) private var dismiss
    @State private var bundleURL: URL?
    @State private var csvURL: URL?
    @State private var copied = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let bundleURL {
                        ShareLink(item: bundleURL) {
                            Label("파일로 공유".localized, systemImage: "square.and.arrow.up")
                        }
                    } else {
                        HStack {
                            ProgressView()
                            Text("준비 중…".localized)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    if let csvURL {
                        ShareLink(item: csvURL) {
                            Label("CSV로 공유".localized, systemImage: "tablecells")
                        }
                    }
                    Button {
                        Task {
                            await copyAsText()
                            copied = true
                        }
                    } label: {
                        Label("텍스트로 복사".localized, systemImage: "doc.on.doc")
                    }
                } footer: {
                    Text(copied
                         ? "클립보드에 복사했습니다.".localized
                         : "\"파일로 공유\"는 사진까지 담은 폴더를 내보냅니다. \"텍스트로 복사\"는 사진 없이 목록만 복사합니다.".localized)
                }
            }
            .navigationTitle(board.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기".localized) { dismiss() }
                }
            }
        }
        .task { await prepare() }
    }

    private func prepare() async {
        let bundle = FileManager.default.temporaryDirectory
            .appendingPathComponent(BackupService.boardFilename(for: board))
        if (try? await BackupService.writeBundle(
            to: bundle, board: board, storageService: storageService
        )) != nil {
            bundleURL = bundle
        }

        let csv = CSVExport.csv(boards: [board], placeCards: storageService.placeCards(inBoard: board.id))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(CSVExport.filename(board: board))
        try? csv.write(to: url, options: .atomic)
        csvURL = url
    }

    /// 사진은 안 싣는다. 예전에는 사진 전체를 base64로 클립보드에 올렸는데,
    /// 붙여 넣을 곳에서 쓸모가 없을뿐더러 그것만으로도 메모리가 터진다.
    private func copyAsText() async {
        guard let text = await BackupService.metadataText(
            board: board, storageService: storageService
        ) else { return }
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
        .environmentObject(CloudSyncService())
}

/// 보드 순서만 바꾸는 화면.
///
/// 왼쪽 목록에서 바로 끌어 옮기게 하지 않은 이유가 있다. 그 목록은
/// `List(selection:)`이고 **그 선택이 곧 오른쪽 칸에 무엇을 보여 줄지를
/// 정한다.** 끌어 옮기려면 편집 모드로 들어가야 하는데, 편집 모드에서의
/// 선택은 "여럿 고르기"라 그 둘이 같은 자리를 놓고 다툰다. 따로 띄우면
/// 그 다툼이 아예 없다.
///
/// 순서를 바꾸는 것 말고 할 일이 없는 화면이라 편집 모드를 켜 둔 채로
/// 연다 — "편집"을 한 번 더 누르게 할 이유가 없다.
private struct BoardReorderSheet: View {
    @EnvironmentObject private var storageService: StorageService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(storageService.boards) { board in
                    Label(board.name, systemImage: board.coverIcon)
                }
                .onMove { source, destination in
                    storageService.moveBoards(fromOffsets: source, toOffset: destination)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("보드 순서".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료".localized) { dismiss() }
                }
            }
        }
    }
}
