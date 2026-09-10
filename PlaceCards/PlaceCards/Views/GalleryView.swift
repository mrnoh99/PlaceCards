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
                    locatableCards: viewModel.locatableCards,
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
                                PlaceCardGridCell(card: card)
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

/// Also reused by `BoardDetailView`, which shows the same grid scoped to
/// one board. Kept as a plain (non-Button) label inside a `NavigationLink`
/// so a tap anywhere on the cell still opens `PlaceCardDetailView`; the
/// star/visited/call/map/website/Instagram controls below are their own
/// `.plain`-styled buttons, which SwiftUI already routes taps to ahead of
/// the surrounding NavigationLink, so they act as their own affordances
/// instead of opening the detail view. Favorite/visited mirror Peragra's
/// `PlaceRowView`, including being toggleable right from here.
struct PlaceCardGridCell: View {
    let card: PlaceCard

    @EnvironmentObject private var storageService: StorageService
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.15))
                if let firstItem = card.media.allItems.first,
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
                            Text(category)
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

            if hasAnyAction {
                HStack(spacing: 12) {
                    if let callURL {
                        Button { openURL(callURL) } label: {
                            Image(systemName: "phone.fill")
                        }
                    }
                    if hasAnyMapLink {
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
                            Image(systemName: "map.fill")
                        }
                    }
                    if let website = card.website, let url = URL(string: website) {
                        Button { openURL(url) } label: {
                            Image(systemName: "link")
                        }
                    }
                    if let instagramURL = card.instagramURL, let url = URL(string: instagramURL) {
                        Button { openURL(url) } label: {
                            Image(systemName: "camera.fill")
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

    private var callURL: URL? {
        guard let phone = card.phone, !phone.isEmpty else { return nil }
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty else { return nil }
        return URL(string: "tel:\(digits)")
    }

    private var hasAnyMapLink: Bool {
        GoogleMapsOpener.url(for: card) != nil || NaverMapOpener.url(for: card) != nil
            || KakaoMapOpener.url(for: card) != nil || TmapOpener.url(for: card) != nil
    }

    private var hasAnyAction: Bool {
        callURL != nil || hasAnyMapLink || card.website != nil || card.instagramURL != nil
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
