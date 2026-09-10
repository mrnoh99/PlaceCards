import SwiftUI

/// Which subset of a place list to show — mirrors Peragra's default
/// "All (n)" / "⭐ Favorites (n)" / "✅ Visited (n)" chips
/// (`TripDetailView.collectionFilterBar`), simplified to PlaceCards' plain
/// `isFavorite`/`isVisited` flags rather than Peragra's general
/// user-defined list system.
enum PlaceStatusFilter: Equatable {
    case all
    case favorite
    case visited

    func matches(_ card: PlaceCard) -> Bool {
        switch self {
        case .all: return true
        case .favorite: return card.isFavorite
        case .visited: return card.isVisited
        }
    }
}

/// A horizontally-scrolling row of filter chips, shared by any place list
/// (board detail, gallery) — same chip styling as Peragra's `FilterChip`.
struct PlaceStatusFilterBar: View {
    @Binding var filter: PlaceStatusFilter
    let allCount: Int
    let favoriteCount: Int
    let visitedCount: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "전체 (\(allCount))", isSelected: filter == .all) { filter = .all }
                chip(title: "⭐ 즐겨찾기 (\(favoriteCount))", isSelected: filter == .favorite) { filter = .favorite }
                chip(title: "✅ 방문 (\(visitedCount))", isSelected: filter == .visited) { filter = .visited }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PlaceStatusFilterBar(filter: .constant(.all), allCount: 12, favoriteCount: 3, visitedCount: 5)
}
