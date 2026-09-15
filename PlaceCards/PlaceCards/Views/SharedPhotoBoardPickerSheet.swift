import SwiftUI

/// Shown when a photo was handed to PlaceCards through the Share
/// Extension (`ShareViewController`, `PlaceCardsShare` target) — since
/// every card belongs to a board, this asks which board to add it to,
/// then opens the normal "장소 추가" flow (`AddPlaceCardView`) for that
/// board with the shared photo already picked.
struct SharedPhotoBoardPickerSheet: View {
    let imageData: Data

    @EnvironmentObject private var storageService: StorageService
    /// Re-declared and re-injected below purely so `AddPlaceCardView`'s own
    /// sheet actually gets it — see `SharedLinkBoardPickerSheet`'s identical
    /// comment on this same property for why a second level of `.sheet`
    /// needs it re-attached explicitly.
    @EnvironmentObject private var navigation: AppNavigation
    @Environment(\.dismiss) private var dismiss
    @State private var selectedBoard: Board?
    /// Flipped true from `.task`, which only runs after this view's first
    /// layout pass — the list is held back until then so it is drawn on a
    /// genuine second pass. Same bug and same fix as
    /// `SharedLinkBoardPickerSheet`: presented at the moment the app comes
    /// forward from the share sheet, the list would otherwise render blank
    /// and only fill in once some *other* state change (backgrounding the
    /// app and returning) forced a redraw. The link sheet was fixed for
    /// this and the photo sheet — same shape, same presentation path
    /// (`MainTabView.presentShortly`) — was not.
    @State private var isReady = false

    private var previewImage: UIImage? { UIImage(data: imageData) }

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
                        // The photo equivalent of the link sheet's "공유한
                        // 정보" preview: which board to file this under is
                        // hard to answer without seeing what "this" even
                        // is, and several screenshots taken back to back
                        // look identical in the share sheet.
                        Section("공유한 사진".localized) {
                            if let previewImage {
                                Image(uiImage: previewImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 180)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                Text("사진을 미리 볼 수 없습니다.".localized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
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
            .navigationTitle("공유한 사진을 추가할 게시판".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소".localized) { dismiss() }
                }
            }
            .task { isReady = true }
        }
        .sheet(item: $selectedBoard, onDismiss: { dismiss() }) { board in
            AddPlaceCardView(
                viewModel: PlaceCardViewModel(storageService: storageService, boardId: board.id),
                initialImageData: imageData
            )
            .environmentObject(navigation)
        }
    }
}

#Preview {
    SharedPhotoBoardPickerSheet(imageData: Data())
        .environmentObject(StorageService())
        .environmentObject(AppNavigation())
}
