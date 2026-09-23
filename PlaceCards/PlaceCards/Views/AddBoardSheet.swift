import SwiftUI

/// Mirrors Peragra's `AddTripSheet`: name + subtitle, plus a cover-icon
/// grid picker, before any place card can be added.
struct AddBoardSheet: View {
    @EnvironmentObject private var storageService: StorageService
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var subtitle = ""
    @State private var coverIcon = Board.coverIconChoices[0]
    @State private var coverPhotoPath: String?

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("게시판".localized) {
                    TextField("이름 (예: 도쿄 봄 여행)".localized, text: $name)
                    TextField("부제목 (예: 2026년 4월 · 도쿄)".localized, text: $subtitle)
                }

                Section("표지".localized) {
                    BoardCoverPicker(coverIcon: $coverIcon, coverPhotoPath: $coverPhotoPath)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .keyboardDoneButton()
            .navigationTitle("새 게시판".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소".localized) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("만들기".localized) { createBoard() }
                        .disabled(!canSubmit)
                }
            }
        }
    }

    private func createBoard() {
        var board = Board(
            name: name.trimmingCharacters(in: .whitespaces),
            subtitle: subtitle.trimmingCharacters(in: .whitespaces),
            coverIcon: coverIcon
        )
        board.coverPhotoPath = coverPhotoPath
        storageService.saveBoard(board)
        dismiss()
    }
}

#Preview {
    AddBoardSheet()
        .environmentObject(StorageService())
}
