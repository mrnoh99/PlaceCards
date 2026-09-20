import SwiftUI

/// A board's own place list's row style — a plain `List` row (small
/// thumbnail + text), unlike `PlaceCardGridCell`'s photo-grid cell used by
/// the "갤러리" tab, which stays a grid. Carries the same
/// star/category/visited/call/map/website/Instagram info as the grid
/// cell, just laid out for a single-column list instead. Favorite/visited
/// stay toggleable right from here, same as the grid cell.
struct PlaceCardListRow: View {
    let card: PlaceCard
    /// 지금 보고 있는 보드 — 그 보드는 배지에서 빠진다. `BoardBadges` 참고.
    var excludingBoardID: String? = nil
    /// Set only while the list is sorted by distance from a chosen
    /// reference — shown as a "250m"/"1.3km" label alongside the
    /// category, mirroring Peragra's `PlaceRowView` distance label.
    var referenceCoordinate: Coordinates? = nil

    @EnvironmentObject private var storageService: StorageService
    @Environment(\.openURL) private var openURL

    private var distanceText: String? {
        Coordinates.distanceText(from: referenceCoordinate, to: card.coordinates)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 8) {
                    Text(card.name)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    HStack(spacing: 8) {
                        Button(action: toggleVisited) {
                            Image(systemName: card.isVisited ? "checkmark.circle.fill" : "checkmark.circle")
                                .accessibilityLabel(card.isVisited ? "방문 표시 해제".localized : "방문으로 표시".localized)
                                .foregroundStyle(card.isVisited ? .green : .secondary)
                        }
                        Button(action: toggleFavorite) {
                            Image(systemName: card.isFavorite ? "star.fill" : "star")
                                .accessibilityLabel(card.isFavorite ? "즐겨찾기 해제".localized : "즐겨찾기에 추가".localized)
                                .foregroundStyle(card.isFavorite ? .yellow : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline)
                }

                if card.category?.isEmpty == false || distanceText != nil || card.isPlaceConfirmed {
                    HStack(spacing: 4) {
                        if card.isPlaceConfirmed {
                            Label("장소확정".localized, systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                        }
                        if let category = card.category, !category.isEmpty {
                            Label(PlaceCategoryIcon.normalizedLabel(for: category), systemImage: PlaceCategoryIcon.symbolName(for: category))
                        }
                        if let distanceText {
                            Text(card.category?.isEmpty == false ? "· \(distanceText)" : distanceText)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Text(card.address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                BoardBadges(card: card, excludingBoardID: excludingBoardID, visibleCount: 2)

                HStack(spacing: 10) {
                    if let rating = card.rating {
                        Text(String(format: "%.1f", rating))
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    if card.hasAnyAction {
                        actionIcons
                    }
                }
                .font(.caption2)
            }

            // Stands in for the disclosure chevron a NavigationLink would
            // normally add — this row is tapped via BoardDetailView's own
            // `.onTapGesture` instead (see there for why), which gets no
            // such indicator for free.
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.15))
            if let firstItem = card.coverPhoto,
               let image = MediaStore.loadThumbnail(fileName: firstItem.localPath, maxPixelSize: 168) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 56, height: 56)
        .clipped()
    }

    @ViewBuilder
    private var actionIcons: some View {
        HStack(spacing: 10) {
            if let callURL = card.callURL {
                Button { openURL(callURL) } label: {
                    Image(systemName: "phone")
                        .accessibilityLabel("전화 걸기".localized)
                }
            }
            if card.hasAnyMapLink {
                MapOpenMenu(card: card) {
                    Image(systemName: "map")
                        .accessibilityLabel("지도에서 열기".localized)
                }
            }
            if let website = card.website, let url = URL(string: website) {
                Button { openURL(url) } label: {
                    Image(systemName: "link")
                        .accessibilityLabel("웹사이트 열기".localized)
                }
            }
            if let instagramURL = card.instagramURL, let url = URL(string: instagramURL) {
                Button { openURL(url) } label: {
                    Image(systemName: "camera")
                        .accessibilityLabel("인스타그램 열기".localized)
                        .foregroundStyle(.pink)
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
    }

    private func toggleFavorite() {
        var updated = card
        updated.isFavorite.toggle()
        storageService.save(updated)
    }

    private func toggleVisited() {
        var updated = card
        updated.isVisited.toggle()
        storageService.save(updated)
    }
}

/// 이 카드가 속한 보드를, **지금 보고 있는 보드는 빼고** 늘어놓는다.
///
/// 보고 있는 보드를 빼는 것이 핵심이다. 그 보드를 열어 둔 채로 보는
/// 목록에서는 모든 칸에 같은 이름이 붙으므로, 아무것도 구별해 주지
/// 못하면서 자리만 먹는다. 여기서 알고 싶은 것은 "이 카드가 **여기 말고**
/// 또 어디에 있나"다.
///
/// 카드 상세의 "보드" 구역(`PlaceCardDetailView.boardsSection`)과 달리
/// 읽기만 한다 — 좁은 칸에 x를 넣으면 목록을 넘기다 잘못 누르기 쉽고,
/// 보드에서 빼는 것은 되돌리기 화면이 따로 없는 동작이다.
struct BoardBadges: View {
    let card: PlaceCard
    /// 지금 보고 있는 보드. "모든 카드"·"가져오기"·검색처럼 보드로
    /// 좁혀져 있지 않으면 nil이고, 그때는 아무것도 빠지지 않는다.
    var excludingBoardID: String? = nil
    /// 이름까지 보여 줄 최대 개수. 넘치는 만큼은 "+2"로 줄인다.
    /// 격자 칸은 좁아 하나, 목록 줄은 둘 — 폭이 다르니 수도 다르다.
    var visibleCount: Int = 1

    @EnvironmentObject private var storageService: StorageService

    /// `card.boardIDs` 순서가 아니라 홈 목록 순서를 따른다(카드 상세의
    /// 칩과 같은 규칙). 실재하지 않는 보드 id는 교집합에서 빠진다.
    private var boards: [Board] {
        storageService.boards.filter {
            $0.id != excludingBoardID && card.boardIDs.contains($0.id)
        }
    }

    var body: some View {
        if !boards.isEmpty {
            HStack(spacing: 4) {
                ForEach(Array(boards.prefix(visibleCount))) { board in
                    Label(board.name, systemImage: board.coverIcon)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }
                if boards.count > visibleCount {
                    Text("+\(boards.count - visibleCount)")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption2)
        }
    }
}

#Preview {
    List {
        PlaceCardListRow(card: PlaceCard(boardId: "preview", name: "샘플 카페".localized, category: "카페".localized, address: "서울시 강남구".localized))
    }
    .environmentObject(StorageService())
}
