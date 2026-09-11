import SwiftUI

/// Mirrors Peragra's `AddTripSheet`: name + subtitle, plus a cover-icon
/// grid picker, before any place card can be added.
struct AddBoardSheet: View {
    @EnvironmentObject private var storageService: StorageService
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var subtitle = ""
    @State private var coverIcon = Board.coverIconChoices[0]

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
        let board = Board(
            name: name.trimmingCharacters(in: .whitespaces),
            subtitle: subtitle.trimmingCharacters(in: .whitespaces),
            coverIcon: coverIcon
        )
        storageService.saveBoard(board)
        dismiss()
    }
}

#Preview {
    AddBoardSheet()
        .environmentObject(StorageService())
}
