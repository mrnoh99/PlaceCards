import SwiftUI
import UIKit

/// Which subset of a place list to show — mirrors Peragra's default
/// "All (n)" / "⭐ Favorites (n)" / "✅ Visited (n)" chips
/// (`TripDetailView.collectionFilterBar`), simplified to PlaceCards' plain
/// `isFavorite`/`isVisited` flags rather than Peragra's general
/// user-defined list system. There, the built-in Favorites/Visited lists
/// are just two more toggleable memberships `activeCollectionIDs`
/// combines with AND (`allSatisfy`) — so both chips are independently
/// toggleable here too, meaning "favorited AND visited" when both are on
/// at once. "전체" isn't a third option alongside them; it's just what
/// showing when neither toggle is on already means.
struct PlaceStatusFilter: Equatable {
    var favoriteOnly = false
    var visitedOnly = false

    var isAll: Bool { !favoriteOnly && !visitedOnly }

    func matches(_ card: PlaceCard) -> Bool {
        if favoriteOnly && !card.isFavorite { return false }
        if visitedOnly && !card.isVisited { return false }
        return true
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

    /// The category chip presents `CategoryPickerSheet` (a searchable
    /// list) rather than a plain `Menu` once there are enough categories
    /// that scanning a dropdown by eye stops being practical.
    @State private var isPresentingCategoryPicker = false
    /// Shown once "현재 위치" comes back with no coordinate *and* the
    /// reason is a denied/restricted permission — as opposed to still
    /// being mid-fetch or a transient signal failure, which just leave
    /// the distance label absent with nothing to tell the user (matches
    /// every other momentary "no result" case in the app). A denied
    /// permission is different: it will never resolve on its own, no
    /// matter how many times "현재 위치" is tapped again, so silently
    /// doing nothing here previously just looked like the feature didn't
    /// work at all.
    @State private var isPresentingLocationDeniedAlert = false

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
                chip(title: "전체 (".localized + "\(allCount))", isSelected: filter.isAll) {
                    filter.favoriteOnly = false
                    filter.visitedOnly = false
                }
                chip(title: "⭐ 즐겨찾기 (".localized + "\(favoriteCount))", isSelected: filter.favoriteOnly) {
                    filter.favoriteOnly.toggle()
                }
                chip(title: "✅ 방문 (".localized + "\(visitedCount))", isSelected: filter.visitedOnly) {
                    filter.visitedOnly.toggle()
                }
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
                        Label(mode.displayName, systemImage: "checkmark")
                    } else {
                        Text(mode.displayName)
                    }
                }
            }
        } label: {
            chipLabel(title: "정렬: ".localized + sortMode.displayName, isSelected: sortMode != .byCategory)
        }
    }

    private var categoryMenu: some View {
        Button {
            isPresentingCategoryPicker = true
        } label: {
            chipLabel(title: "카테고리: ".localized + (categoryFilter ?? "전체".localized), isSelected: categoryFilter != nil)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isPresentingCategoryPicker) {
            CategoryPickerSheet(categories: categories, selection: $categoryFilter)
        }
    }

    private var referenceMenu: some View {
        Menu {
            Button {
                distanceReference = .here
                Task {
                    let coordinate = await LocationService.currentLocation()
                    hereCoordinate = coordinate
                    if coordinate == nil, await LocationService.isAuthorizationDenied() {
                        isPresentingLocationDeniedAlert = true
                    }
                }
            } label: {
                Label("현재 위치".localized, systemImage: "location")
            }
            ForEach(referenceCandidates) { card in
                Button(card.name) { distanceReference = .card(card.id) }
            }
        } label: {
            chipLabel(title: referenceTitle, isSelected: distanceReference != nil)
        }
        .alert("위치 권한이 꺼져 있습니다".localized, isPresented: $isPresentingLocationDeniedAlert) {
            Button("설정 열기".localized) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("취소".localized, role: .cancel) {}
        } message: {
            Text("현재 위치에서의 거리를 표시하려면 설정 앱에서 PlaceCards의 위치 권한을 허용해주세요.".localized)
        }
    }

    private var referenceTitle: String {
        switch distanceReference {
        case .here: return "기준: 현재 위치".localized
        case .card: return referenceCard.map { "기준: ".localized + $0.name } ?? "장소 선택…".localized
        case nil: return "장소 선택…".localized
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
        categories: ["카페".localized, "식당".localized],
        filter: .constant(PlaceStatusFilter()),
        allCount: 12,
        favoriteCount: 3,
        visitedCount: 5
    )
}
