import Foundation
import SwiftUI
import UIKit

/// The board list — the app's home screen. Mirrors Peragra's
/// `TripsListView`: a board (name + subtitle + cover icon) is created
/// first, and place cards are only ever added inside one. Tapping a board
/// doesn't push a per-board screen here — it scopes the Gallery tab to
/// that board and switches to it (`AppNavigation.showBoardInGallery`),
/// since Gallery's own list/grid toggle already covers everything a
/// dedicated board screen would.
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
    @State private var isPresentingTrash = false

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
        NavigationStack {
            Group {
                if isSearching {
                    searchResultsList
                } else if storageService.boards.isEmpty {
                    emptyState
                } else {
                    List {
                        // Lightroom의 앨범 목록과 같은 순서다 — 앱이
                        // 스스로 세우는 항목이 위, 사용자가 만든 것이
                        // 아래. 둘을 한 List에 두되 Section으로 가른다.
                        Section {
                            SystemCollectionRow(
                                icon: "square.grid.2x2",
                                title: "모든 카드".localized,
                                count: storageService.activePlaceCards.count
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { navigation.showAllInGallery() }

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
                            .contentShape(Rectangle())
                            .onTapGesture { navigation.showImportedInGallery() }

                            SystemCollectionRow(
                                icon: "trash",
                                title: "삭제됨".localized,
                                count: storageService.deletedPlaceCards.count
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { isPresentingTrash = true }
                        } header: {
                            sectionHeader("PinSpots")
                        }
                        .listRowBackground(Theme.panel)
                        .listRowSeparator(.hidden)

                        Section {
                            ForEach(storageService.boards) { board in
                                BoardRow(board: board, cardCount: storageService.placeCards(inBoard: board.id).count)
                                    .contentShape(Rectangle())
                                    .onTapGesture { navigation.showBoardInGallery(board.id) }
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

                        categoryBrowseSection

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
            .navigationDestination(isPresented: $isPresentingTrash) {
                TrashView()
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
    HomeView()
        .environmentObject(StorageService())
        .environmentObject(AppNavigation())
}
