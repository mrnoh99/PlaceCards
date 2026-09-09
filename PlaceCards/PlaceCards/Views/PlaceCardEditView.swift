import SwiftUI

struct PlaceCardEditView: View {
    @Environment(\.dismiss) private var dismiss

    let card: PlaceCard?
    let onSave: (PlaceCard) -> Void

    @State private var guestName: String
    @State private var tableName: String
    @State private var note: String

    init(card: PlaceCard?, onSave: @escaping (PlaceCard) -> Void) {
        self.card = card
        self.onSave = onSave
        _guestName = State(initialValue: card?.guestName ?? "")
        _tableName = State(initialValue: card?.tableName ?? "")
        _note = State(initialValue: card?.note ?? "")
    }

    private var isValid: Bool {
        !guestName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("손님 정보") {
                    TextField("이름", text: $guestName)
                    TextField("테이블", text: $tableName)
                }
                Section("메모") {
                    TextField("메모 (선택)", text: $note, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }
            }
            .navigationTitle(card == nil ? "카드 추가" : "카드 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        var result = card ?? PlaceCard(guestName: "")
                        result.guestName = guestName.trimmingCharacters(in: .whitespacesAndNewlines)
                        result.tableName = tableName.trimmingCharacters(in: .whitespacesAndNewlines)
                        result.note = note
                        onSave(result)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}

#Preview {
    PlaceCardEditView(card: nil) { _ in }
}
