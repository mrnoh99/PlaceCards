import SwiftUI

/// Shows the place cards inside one board, and is where new place cards
/// actually get created — mirrors Peragra's `TripDetailView` (simplified:
/// no lists/collections/duplicate-merging here).
struct BoardDetailView: View {
    let board: Board
    @EnvironmentObject private var storageService: StorageService
    @State private var isPresentingAddCard = false

    private var cards: [PlaceCard] {
        storageService.placeCards(inBoard: board.id).sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        Group {
            if cards.isEmpty {
                ContentUnavailableView {
                    Label("장소가 없습니다", systemImage: "mappin.slash")
                } description: {
                    Text("오른쪽 위 + 버튼으로 이 게시판에 첫 장소를 추가해보세요.")
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
                        ForEach(cards) { card in
                            NavigationLink {
                                PlaceCardDetailView(card: card)
                            } label: {
                                PlaceCardGridCell(card: card)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(board.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isPresentingAddCard = true
                } label: {
                    Label("장소 추가", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isPresentingAddCard) {
            AddPlaceCardView(viewModel: PlaceCardViewModel(storageService: storageService, boardId: board.id))
        }
    }
}

#Preview {
    NavigationStack {
        BoardDetailView(board: Board(name: "도쿄 봄 여행", subtitle: "2026년 4월", coverEmoji: "✈️"))
            .environmentObject(StorageService())
    }
}
