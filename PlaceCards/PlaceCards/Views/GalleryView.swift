import SwiftUI

struct GalleryView: View {
    @StateObject private var viewModel: GalleryViewModel

    init(viewModel: GalleryViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PlaceStatusFilterBar(
                    sortMode: $viewModel.sortMode,
                    distanceReference: $viewModel.distanceReference,
                    hereCoordinate: $viewModel.hereCoordinate,
                    referenceCandidates: viewModel.referenceCandidates,
                    categoryFilter: $viewModel.categoryFilter,
                    categories: viewModel.allCategories,
                    filter: $viewModel.statusFilter,
                    allCount: viewModel.totalCount,
                    favoriteCount: viewModel.favoriteCount,
                    visitedCount: viewModel.visitedCount
                )
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
                        ForEach(viewModel.filteredPlaceCards) { card in
                            NavigationLink {
                                PlaceCardDetailView(card: card)
                            } label: {
                                PlaceCardGridCell(card: card, referenceCoordinate: viewModel.distanceReferenceCoordinate)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("갤러리")
            .searchable(text: $viewModel.searchQuery, prompt: "이름, 주소로 검색")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("전체") { viewModel.selectedTag = nil }
                        ForEach(viewModel.allTags, id: \.self) { tag in
                            Button(tag) { viewModel.selectedTag = tag }
                        }
                    } label: {
                        Label("태그", systemImage: "tag")
                    }
                }
            }
            .overlay {
                if viewModel.filteredPlaceCards.isEmpty {
                    ContentUnavailableView.search
                }
            }
        }
    }
}

/// Used only by the "갤러리" tab now — a board's own place list is a plain
/// `List` of `PlaceCardListRow`, not this grid (see `BoardDetailView`).
/// Kept as a plain (non-Button) label inside a `NavigationLink` so a tap
/// anywhere on the cell still opens `PlaceCardDetailView`; the star/
/// visited/call/map/website/Instagram controls below are their own
/// `.plain`-styled buttons, which SwiftUI already routes taps to ahead of
/// the surrounding NavigationLink here — unlike inside a `List`, where
/// that same setup doesn't work (see `BoardDetailView`'s own row-tap
/// handling for why). Favorite/visited mirror Peragra's `PlaceRowView`,
/// including being toggleable right from here.
struct PlaceCardGridCell: View {
    let card: PlaceCard
    /// Set only while the grid is sorted by distance from a chosen
    /// reference — shown as a "250m"/"1.3km" label next to the address.
    var referenceCoordinate: Coordinates? = nil

    @EnvironmentObject private var storageService: StorageService
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.15))
                if let firstItem = card.media.officialPhotos.first ?? card.media.allItems.first,
                   let image = MediaStore.loadImage(fileName: firstItem.localPath) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                HStack(alignment: .top) {
                    if let category = card.category, !category.isEmpty {
                        Label {
                            Text(PlaceCategoryIcon.normalizedLabel(for: category))
                        } icon: {
                            Image(systemName: PlaceCategoryIcon.symbolName(for: category))
                        }
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.thinMaterial, in: Capsule())
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        Button(action: toggleVisited) {
                            Image(systemName: card.isVisited ? "checkmark.circle.fill" : "checkmark.circle")
                                .foregroundStyle(card.isVisited ? .green : .white)
                        }
                        Button(action: toggleFavorite) {
                            Image(systemName: card.isFavorite ? "star.fill" : "star")
                                .foregroundStyle(card.isFavorite ? .yellow : .white)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.callout)
                    .shadow(radius: 2)
                }
                .padding(6)
            }
            .frame(height: 120)
            .clipped()

            Text(card.name)
                .font(.subheadline.bold())
                .lineLimit(1)
            Text(card.address)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let distanceText = Coordinates.distanceText(from: referenceCoordinate, to: card.coordinates) {
                Text(distanceText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if card.hasAnyAction {
                HStack(spacing: 12) {
                    if let callURL = card.callURL {
                        Button { openURL(callURL) } label: {
                            Image(systemName: "phone")
                        }
                    }
                    if card.hasAnyMapLink {
                        Menu {
                            if GoogleMapsOpener.url(for: card) != nil {
                                Button("Google Maps") { GoogleMapsOpener.open(for: card, using: openURL) }
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
                .font(.callout)
                .foregroundStyle(Color.accentColor)
            }
        }
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
    let storageService = StorageService()
    GalleryView(viewModel: GalleryViewModel(storageService: storageService))
        .environmentObject(storageService)
}
