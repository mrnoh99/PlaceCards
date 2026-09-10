import SwiftUI

struct GalleryView: View {
    @StateObject private var viewModel: GalleryViewModel

    init(viewModel: GalleryViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
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
/// one board.
struct PlaceCardGridCell: View {
    let card: PlaceCard

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
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
                }
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
        }
    }
}

#Preview {
    GalleryView(viewModel: GalleryViewModel(storageService: StorageService()))
}
