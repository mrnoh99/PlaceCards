import SwiftUI
import MapKit

struct PlaceCardDetailView: View {
    let card: PlaceCard

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !card.media.allItems.isEmpty {
                    TabView {
                        ForEach(card.media.allItems) { item in
                            if let image = MediaStore.loadImage(fileName: item.localPath) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                            }
                        }
                    }
                    .tabViewStyle(.page)
                    .frame(height: 240)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(card.name)
                        .font(.title.bold())
                    if let category = card.category, !category.isEmpty {
                        Label(category, systemImage: PlaceCategoryIcon.symbolName(for: category))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text(card.address)
                        .font(.body)

                    HStack(spacing: 16) {
                        if let rating = card.rating {
                            Label(String(format: "%.1f", rating), systemImage: "star.fill")
                                .foregroundStyle(.orange)
                        }
                        if let reviewCount = card.reviewCount {
                            Text("리뷰 \(reviewCount)개")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline)

                    if let phone = card.phone, !phone.isEmpty {
                        Label(phone, systemImage: "phone")
                    }
                    if let website = card.website, let url = URL(string: website) {
                        Link(destination: url) {
                            Label(website, systemImage: "globe")
                        }
                    }

                    if !card.amenities.isEmpty {
                        Text("편의시설")
                            .font(.headline)
                        WrapTagsView(tags: card.amenities)
                    }

                    if !card.tags.isEmpty {
                        Text("태그")
                            .font(.headline)
                        WrapTagsView(tags: card.tags)
                    }
                }
                .padding(.horizontal)

                if let coordinates = card.coordinates {
                    Map(
                        coordinateRegion: .constant(
                            MKCoordinateRegion(
                                center: CLLocationCoordinate2D(latitude: coordinates.latitude, longitude: coordinates.longitude),
                                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                            )
                        ),
                        annotationItems: [card]
                    ) { item in
                        MapMarker(coordinate: CLLocationCoordinate2D(latitude: coordinates.latitude, longitude: coordinates.longitude))
                    }
                    .frame(height: 180)
                    .padding(.horizontal)
                    .allowsHitTesting(false)

                    Button {
                        openInMaps(coordinates: coordinates, name: card.name)
                    } label: {
                        Label("지도에서 열기", systemImage: "map")
                    }
                    .buttonStyle(.bordered)
                    .padding(.horizontal)
                }

                ShareLink(item: shareText) {
                    Label("공유", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle(card.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var shareText: String {
        "\(card.name)\n\(card.address)"
    }

    private func openInMaps(coordinates: Coordinates, name: String) {
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: coordinates.latitude, longitude: coordinates.longitude))
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = name
        mapItem.openInMaps()
    }
}

private struct WrapTagsView: View {
    let tags: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        PlaceCardDetailView(card: PlaceCard(boardId: "preview", name: "샘플 카페", address: "서울시 강남구"))
    }
}
