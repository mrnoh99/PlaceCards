import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var storageService: StorageService
    @Binding var isPresentingAddCard: Bool

    private var recentCards: [PlaceCard] {
        Array(storageService.placeCards.sorted { $0.createdAt > $1.createdAt }.prefix(5))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        isPresentingAddCard = true
                    } label: {
                        Label("사진으로 장소 추가하기", systemImage: "plus.circle.fill")
                            .font(.headline)
                    }
                }

                if !recentCards.isEmpty {
                    Section("최근 추가한 장소") {
                        ForEach(recentCards) { card in
                            NavigationLink {
                                PlaceCardDetailView(card: card)
                            } label: {
                                PlaceCardRow(card: card)
                            }
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "저장된 장소가 없습니다",
                        systemImage: "mappin.slash",
                        description: Text("위의 버튼으로 첫 장소를 추가해보세요.")
                    )
                }
            }
            .navigationTitle("PlaceCards")
        }
    }
}

struct PlaceCardRow: View {
    let card: PlaceCard

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(card.name)
                    .font(.headline)
                Text(card.address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let rating = card.rating {
                HStack(spacing: 2) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                    Text(String(format: "%.1f", rating))
                        .font(.caption)
                }
            }
        }
    }
}

#Preview {
    HomeView(isPresentingAddCard: .constant(false))
        .environmentObject(StorageService())
}
