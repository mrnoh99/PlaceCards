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

/// What "거리(Distance)" sort measures from: the device's current location
/// ("현재 위치"), always offered first, or another saved card.
enum DistanceReference: Equatable {
    case here
    case card(String)
}

/// A horizontally-scrolling row of sort + filter controls, shared by any
/// place list (board detail, gallery) — mirrors Peragra's `PlaceFilterBar`
/// (sort menu + reference-place menu) followed by
/// `TripDetailView.collectionFilterBar` (its All/Favorites/Visited chips),
/// combined into a single row. The category dropdown next to the sort menu
/// filters by `PlaceCard.category`'s free-text value rather than Peragra's
/// fixed `PlaceCategory` enum, since Google Places categories aren't a
/// closed set here — it only lists categories actually present, and hides
/// itself when there are none.
struct PlaceStatusFilterBar: View {
    @Binding var sortMode: PlaceSortMode
    @Binding var distanceReference: DistanceReference?
    /// Set by this view when "현재 위치" is chosen — the parent owns it (and
    /// resolves the actual sort with it) since fetching it is async.
    @Binding var hereCoordinate: Coordinates?
    /// Every card in the current list, offered by name as a "Distance
    /// from…" reference choice — not narrowed to ones with a resolved
    /// coordinate, since a card added without one yet should still be
    /// pickable by name; `PlaceCardSorting` already falls back to leaving
    /// the list unsorted if the chosen reference turns out to have none.
    let referenceCandidates: [PlaceCard]

    /// nil means no category filter is applied ("전체").
    @Binding var categoryFilter: String?
    /// Distinct categories present in the current list, offered as dropdown choices.
    let categories: [String]

    @Binding var filter: PlaceStatusFilter
    let allCount: Int
    let favoriteCount: Int
    let visitedCount: Int

    private var referenceCard: PlaceCard? {
        guard case .card(let id) = distanceReference else { return nil }
        return referenceCandidates.first { $0.id == id }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                sortMenu
                if sortMode == .distance {
                    referenceMenu
                }
                if !categories.isEmpty {
                    categoryMenu
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
                    if mode != .distance { distanceReference = nil }
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

    private var categoryMenu: some View {
        Menu {
            Button {
                categoryFilter = nil
            } label: {
                if categoryFilter == nil {
                    Label("전체", systemImage: "checkmark")
                } else {
                    Text("전체")
                }
            }
            ForEach(categories, id: \.self) { category in
                Button {
                    categoryFilter = category
                } label: {
                    if categoryFilter == category {
                        Label(category, systemImage: "checkmark")
                    } else {
                        Text(category)
                    }
                }
            }
        } label: {
            chipLabel(title: "카테고리: \(categoryFilter ?? "전체")", isSelected: categoryFilter != nil)
        }
    }

    private var referenceMenu: some View {
        Menu {
            Button {
                distanceReference = .here
                Task { hereCoordinate = await LocationService.currentLocation() }
            } label: {
                Label("현재 위치", systemImage: "location")
            }
            ForEach(referenceCandidates) { card in
                Button(card.name) { distanceReference = .card(card.id) }
            }
        } label: {
            chipLabel(title: referenceTitle, isSelected: distanceReference != nil)
        }
    }

    private var referenceTitle: String {
        switch distanceReference {
        case .here: return "기준: 현재 위치"
        case .card: return referenceCard.map { "기준: \($0.name)" } ?? "장소 선택…"
        case nil: return "장소 선택…"
        }
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
        distanceReference: .constant(nil),
        hereCoordinate: .constant(nil),
        referenceCandidates: [],
        categoryFilter: .constant(nil),
        categories: ["카페", "식당"],
        filter: .constant(.all),
        allCount: 12,
        favoriteCount: 3,
        visitedCount: 5
    )
}
