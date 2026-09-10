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
    @State private var searchQuery = ""
    @State private var isPresentingImportBoard = false

    private var filteredBoards: [Board] {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return storageService.boards }
        return storageService.boards.filter { board in
            board.name.localizedCaseInsensitiveContains(searchQuery)
                || board.subtitle.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if storageService.boards.isEmpty {
                    emptyState
                } else if filteredBoards.isEmpty {
                    ContentUnavailableView.search
                } else {
                    List {
                        ForEach(filteredBoards) { board in
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
                                        Label("삭제", systemImage: "trash")
                                    }
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    boardPendingEdit = board
                                } label: {
                                    Label("수정", systemImage: "pencil")
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
            .searchable(text: $searchQuery, prompt: "게시판 검색")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            isPresentingAddBoard = true
                        } label: {
                            Label("새 게시판", systemImage: "plus")
                        }
                        Button {
                            isPresentingImportBoard = true
                        } label: {
                            Label("게시판 가져오기", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Label("추가", systemImage: "plus")
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
                "비어있는 게시판 \"\(boardPendingDelete?.name ?? "")\"을 삭제할까요?",
                isPresented: Binding(
                    get: { boardPendingDelete != nil },
                    set: { if !$0 { boardPendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("삭제", role: .destructive) {
                    if let board = boardPendingDelete {
                        storageService.deleteBoard(board)
                    }
                    boardPendingDelete = nil
                }
                Button("취소", role: .cancel) { boardPendingDelete = nil }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("게시판이 없습니다", systemImage: "square.stack")
        } description: {
            Text("먼저 게시판을 만들고, 그 안에 장소 카드를 추가해보세요.")
        } actions: {
            Button("첫 게시판 만들기") { isPresentingAddBoard = true }
                .buttonStyle(.borderedProminent)
        }
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
                Text("장소 \(cardCount)개")
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
                Label("텍스트로 복사", systemImage: "doc.on.doc")
            }
            if let exportFileURL {
                ShareLink(item: exportFileURL) {
                    Label("파일로 공유", systemImage: "square.and.arrow.up")
                }
            }
        } label: {
            Label("내보내기", systemImage: "square.and.arrow.up")
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
