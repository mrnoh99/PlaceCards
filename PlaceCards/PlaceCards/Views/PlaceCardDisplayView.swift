import SwiftUI

/// Renders the card as a foldable tent: an upside-down copy on top and an
/// upright copy on the bottom, so it reads correctly from both sides once
/// printed and folded in half to stand on a table.
struct PlaceCardDisplayView: View {
    let card: PlaceCard

    var body: some View {
        VStack(spacing: 0) {
            cardHalf
                .rotationEffect(.degrees(180))
            Divider()
            cardHalf
        }
        .navigationTitle(card.guestName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var cardHalf: some View {
        VStack(spacing: 12) {
            Text(card.guestName)
                .font(.system(size: 40, weight: .bold, design: .serif))
                .multilineTextAlignment(.center)
            if !card.tableName.isEmpty {
                Text(card.tableName)
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            if !card.note.isEmpty {
                Text(card.note)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    NavigationStack {
        PlaceCardDisplayView(card: PlaceCard(guestName: "홍길동", tableName: "1번 테이블", note: "환영합니다"))
    }
}
