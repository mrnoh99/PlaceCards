import SwiftUI

/// Shown when a link (or plain text, e.g. Naver Map's own "공유") was
/// handed to PlaceCards through the Share Extension
/// (`ShareViewController`, `PlaceCardsShare` target) — mirrors
/// `SharedPhotoBoardPickerSheet` exactly, just for a shared link instead
/// of a shared photo: asks which board to add it to, then opens the
/// normal "장소 추가" flow (`AddPlaceCardView`) for that board with the
/// link already dropped into a candidate row.
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

    var body: some View {
        NavigationStack {
            Group {
                if storageService.boards.isEmpty {
                    ContentUnavailableView {
                        Label("게시판이 없습니다".localized, systemImage: "square.stack")
                    } description: {
                        Text("먼저 홈에서 게시판을 만들어주세요.".localized)
                    }
                } else {
                    List(storageService.boards) { board in
                        Button {
                            selectedBoard = board
                        } label: {
                            Label(board.name, systemImage: board.coverIcon)
                        }
                        .foregroundStyle(.primary)
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
        .sheet(item: $selectedBoard, onDismiss: { dismiss() }) { board in
            AddPlaceCardView(
                viewModel: PlaceCardViewModel(storageService: storageService, boardId: board.id),
                initialLinkText: linkText
            )
            .environmentObject(navigation)
        }
    }
}

#Preview {
    SharedLinkBoardPickerSheet(linkText: "https://maps.google.com/example")
        .environmentObject(StorageService())
        .environmentObject(AppNavigation())
}
