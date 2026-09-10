import SwiftUI

/// Shown when a photo was handed to PlaceCards through the Share
/// Extension (`ShareViewController`, `PlaceCardsShare` target) — since
/// every card belongs to a board, this asks which board to add it to,
/// then opens the normal "장소 추가" flow (`AddPlaceCardView`) for that
/// board with the shared photo already picked.
struct SharedPhotoBoardPickerSheet: View {
    let imageData: Data

    @EnvironmentObject private var storageService: StorageService
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
            .navigationTitle("공유한 사진을 추가할 게시판".localized)
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
                initialImageData: imageData
            )
        }
    }
}

#Preview {
    SharedPhotoBoardPickerSheet(imageData: Data())
        .environmentObject(StorageService())
}
