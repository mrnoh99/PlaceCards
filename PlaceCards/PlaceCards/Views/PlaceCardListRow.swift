import SwiftUI

/// A board's own place list's row style — a plain `List` row (small
/// thumbnail + text), unlike `PlaceCardGridCell`'s photo-grid cell used by
/// the "갤러리" tab, which stays a grid. Carries the same
/// star/category/visited/call/map/website/Instagram info as the grid
/// cell, just laid out for a single-column list instead. Favorite/visited
/// stay toggleable right from here, same as the grid cell.
struct PlaceCardListRow: View {
    let card: PlaceCard

    @EnvironmentObject private var storageService: StorageService
    @Environment(\.openURL) private var openURL

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
                                .foregroundStyle(card.isVisited ? .green : .secondary)
                        }
                        Button(action: toggleFavorite) {
                            Image(systemName: card.isFavorite ? "star.fill" : "star")
                                .foregroundStyle(card.isFavorite ? .yellow : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline)
                }

                if let category = card.category, !category.isEmpty {
                    Label(category, systemImage: PlaceCategoryIcon.symbolName(for: category))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(card.address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

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
            if let firstItem = card.media.allItems.first,
               let image = MediaStore.loadImage(fileName: firstItem.localPath) {
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
                }
            }
            if card.hasAnyMapLink {
                Menu {
                    if let url = GoogleMapsOpener.url(for: card) {
                        Button("Google Maps") { openURL(url) }
                    }
                    if let url = NaverMapOpener.url(for: card) {
                        Button("Naver Map") { openURL(url) }
                    }
                    if let url = KakaoMapOpener.url(for: card) {
                        Button("Kakao Map") { openURL(url) }
                    }
                    if let url = TmapOpener.url(for: card) {
                        Button("Tmap") { openURL(url) }
                    }
                } label: {
                    Image(systemName: "map")
                }
            }
            if let website = card.website, let url = URL(string: website) {
                Button { openURL(url) } label: {
                    Image(systemName: "link")
                }
            }
            if let instagramURL = card.instagramURL, let url = URL(string: instagramURL) {
                Button { openURL(url) } label: {
                    Image(systemName: "camera")
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

#Preview {
    List {
        PlaceCardListRow(card: PlaceCard(boardId: "preview", name: "샘플 카페", category: "카페", address: "서울시 강남구"))
    }
    .environmentObject(StorageService())
}
