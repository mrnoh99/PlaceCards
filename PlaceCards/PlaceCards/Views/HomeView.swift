import SwiftUI

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

    var body: some View {
        NavigationStack {
            Group {
                if storageService.boards.isEmpty {
                    emptyState
                } else {
                    List {
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
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPresentingAddBoard = true
                    } label: {
                        Label("새 게시판", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isPresentingAddBoard) {
                AddBoardSheet()
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

#Preview {
    HomeView()
        .environmentObject(StorageService())
        .environmentObject(AppNavigation())
}
