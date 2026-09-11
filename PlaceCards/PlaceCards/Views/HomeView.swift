import SwiftUI
import UIKit

/// The board list — the app's home screen. Mirrors Peragra's
/// `TripsListView`: a board (name + subtitle + cover icon) is created
/// first, and place cards are only ever added inside one, from
/// `BoardDetailView`.
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
        storageService.placeCards.filter { $0.matchesSearch(searchQuery) }
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
        let normalized = storageService.placeCards.compactMap { card -> String? in
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
                        categoryBrowseSection
                        ForEach(storageService.boards) { board in
                            NavigationLink {
                                BoardDetailView(board: board)
                            } label: {
                                BoardRow(board: board, cardCount: storageService.placeCards(inBoard: board.id).count)
                            }
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
                    }
                }
            }
            .navigationTitle("PlaceCards")
            // Fires whenever this root board list becomes visible again —
            // initial load, and every pop back to it (from BoardDetailView,
            // whatever depth) — but not while a deeper push (e.g. a place
            // card detail within a board) merely covers BoardDetailView,
            // since this view itself isn't reappearing then. That's what
            // makes clearing the scope here safe: it only clears once the
            // user has actually left every board, not on every transient
            // onDisappear inside one. See `AppNavigation.currentHomeBoardID`.
            .onAppear { navigation.currentHomeBoardID = nil }
            // `.always` so search stays visible without a pull-down/
            // scroll — matches Gallery/BoardDetailView.
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

private struct BoardRow: View {
    let board: Board
    let cardCount: Int

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: board.coverIcon)
                .font(.system(size: 20))
                .foregroundStyle(Color.accentColor)
                .frame(width: 48, height: 48)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text(board.name)
                    .font(.headline)
                if !board.subtitle.isEmpty {
                    Text(board.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text("장소 ".localized + "\(cardCount)" + "개".localized)
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
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

    var body: some View {
        Menu {
            Button {
                copyAsText()
            } label: {
                Label("텍스트로 복사".localized, systemImage: "doc.on.doc")
            }
            if let exportFileURL {
                ShareLink(item: exportFileURL) {
                    Label("파일로 공유".localized, systemImage: "square.and.arrow.up")
                }
            }
        } label: {
            Label("내보내기".localized, systemImage: "square.and.arrow.up")
        }
        .tint(.blue)
        .task { prepareFile() }
    }

    private func prepareFile() {
        guard let data = try? BackupService.exportBoard(board, storageService: storageService) else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(BackupService.boardFilename(for: board))
        try? data.write(to: url, options: .atomic)
        exportFileURL = url
    }

    private func copyAsText() {
        guard let data = try? BackupService.exportBoard(board, storageService: storageService),
              let text = String(data: data, encoding: .utf8) else { return }
        UIPasteboard.general.string = text
    }
}

#Preview {
    HomeView()
        .environmentObject(StorageService())
        .environmentObject(AppNavigation())
}
