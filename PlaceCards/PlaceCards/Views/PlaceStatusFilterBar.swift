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

/// A horizontally-scrolling row of sort + filter controls, shared by any
/// place list (board detail, gallery) — mirrors Peragra's `PlaceFilterBar`
/// (sort menu + reference-place menu) followed by
/// `TripDetailView.collectionFilterBar` (its All/Favorites/Visited chips),
/// combined into a single row since PlaceCards has no category chips of
/// its own to separate them from.
struct PlaceStatusFilterBar: View {
    @Binding var sortMode: PlaceSortMode
    @Binding var referenceCardId: String?
    /// Cards with a resolved coordinate, offered as choices for "Distance from…".
    let locatableCards: [PlaceCard]

    @Binding var filter: PlaceStatusFilter
    let allCount: Int
    let favoriteCount: Int
    let visitedCount: Int

    private var referenceCard: PlaceCard? {
        guard let referenceCardId else { return nil }
        return locatableCards.first { $0.id == referenceCardId }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                sortMenu
                if sortMode == .distance {
                    referenceCardMenu
                }
                Divider().frame(height: 20)
                chip(title: "전체 (\(allCount))", isSelected: filter == .all) { filter = .all }
                chip(title: "⭐ 즐겨찾기 (\(favoriteCount))", isSelected: filter == .favorite) { filter = .favorite }
                chip(title: "✅ 방문 (\(visitedCount))", isSelected: filter == .visited) { filter = .visited }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(PlaceSortMode.allCases) { mode in
                Button {
                    sortMode = mode
                    if mode != .distance { referenceCardId = nil }
                } label: {
                    if sortMode == mode {
                        Label(mode.rawValue, systemImage: "checkmark")
                    } else {
                        Text(mode.rawValue)
                    }
                }
            }
        } label: {
            chipLabel(title: "정렬: \(sortMode.rawValue)", isSelected: sortMode != .byCategory)
        }
    }

    private var referenceCardMenu: some View {
        Menu {
            ForEach(locatableCards) { card in
                Button(card.name) { referenceCardId = card.id }
            }
        } label: {
            chipLabel(
                title: referenceCard.map { "기준: \($0.name)" } ?? "장소 선택…",
                isSelected: referenceCard != nil
            )
        }
        .disabled(locatableCards.isEmpty)
    }

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            chipLabel(title: title, isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }

    private func chipLabel(title: String, isSelected: Bool) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
    }
}

#Preview {
    PlaceStatusFilterBar(
        sortMode: .constant(.byCategory),
        referenceCardId: .constant(nil),
        locatableCards: [],
        filter: .constant(.all),
        allCount: 12,
        favoriteCount: 3,
        visitedCount: 5
    )
}
