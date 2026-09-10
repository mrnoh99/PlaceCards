import SwiftUI

/// Mirrors Peragra's `EditTripSheet`: same name/subtitle/cover-icon form
/// as `AddBoardSheet`, pre-filled with the board's current values.
struct EditBoardSheet: View {
    let board: Board

    @EnvironmentObject private var storageService: StorageService
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var subtitle: String
    @State private var coverIcon: String

    init(board: Board) {
        self.board = board
        _name = State(initialValue: board.name)
        _subtitle = State(initialValue: board.subtitle)
        _coverIcon = State(initialValue: board.coverIcon)
    }

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

                Section("아이콘".localized) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
                        ForEach(Board.coverIconChoices, id: \.self) { icon in
                            Button {
                                coverIcon = icon
                            } label: {
                                Image(systemName: icon)
                                    .font(.system(size: 22))
                                    .foregroundStyle(coverIcon == icon ? Color.accentColor : .secondary)
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(coverIcon == icon ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .strokeBorder(coverIcon == icon ? Color.accentColor : .clear, lineWidth: 1.5)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("게시판 수정".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소".localized) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장".localized) { save() }
                        .disabled(!canSubmit)
                }
            }
        }
    }

    private func save() {
        var updated = board
        updated.name = name.trimmingCharacters(in: .whitespaces)
        updated.subtitle = subtitle.trimmingCharacters(in: .whitespaces)
        updated.coverIcon = coverIcon
        storageService.saveBoard(updated)
        dismiss()
    }
}

#Preview {
    EditBoardSheet(board: Board(name: "도쿄 봄 여행".localized, subtitle: "2026년 4월".localized, coverIcon: "airplane"))
        .environmentObject(StorageService())
}
