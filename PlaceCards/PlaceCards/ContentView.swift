import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: PlaceCardStore
    @State private var isPresentingNewCard = false
    @State private var editingCard: PlaceCard?

    var body: some View {
        NavigationStack {
            Group {
                if store.cards.isEmpty {
                    ContentUnavailableView(
                        "카드가 없습니다",
                        systemImage: "person.crop.rectangle.stack",
                        description: Text("오른쪽 위 + 버튼을 눌러 첫 자리 카드를 만들어보세요.")
                    )
                } else {
                    List {
                        ForEach(store.cards) { card in
                            NavigationLink {
                                PlaceCardDisplayView(card: card)
                            } label: {
                                PlaceCardRow(card: card)
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    delete(card)
                                } label: {
                                    Label("삭제", systemImage: "trash")
                                }
                                Button {
                                    editingCard = card
                                } label: {
                                    Label("수정", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                        .onDelete(perform: store.deleteCards)
                        .onMove(perform: store.moveCards)
                    }
                }
            }
            .navigationTitle("PlaceCards")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editingCard = nil
                        isPresentingNewCard = true
                    } label: {
                        Label("추가", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                        .disabled(store.cards.isEmpty)
                }
            }
            .sheet(isPresented: $isPresentingNewCard) {
                PlaceCardEditView(card: nil) { newCard in
                    store.addCard(newCard)
                }
            }
            .sheet(item: $editingCard) { card in
                PlaceCardEditView(card: card) { updated in
                    store.updateCard(updated)
                }
            }
        }
    }

    private func delete(_ card: PlaceCard) {
        if let index = store.cards.firstIndex(where: { $0.id == card.id }) {
            store.deleteCards(at: IndexSet(integer: index))
        }
    }
}

private struct PlaceCardRow: View {
    let card: PlaceCard

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(card.guestName)
                .font(.headline)
            if !card.tableName.isEmpty {
                Text(card.tableName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(PlaceCardStore())
}
