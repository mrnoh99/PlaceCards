import SwiftUI
import MapKit

struct PlacesMapView: View {
    @StateObject private var viewModel: MapViewModel
    @State private var selectedCard: PlaceCard?

    init(viewModel: MapViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            Map(
                coordinateRegion: $viewModel.region,
                annotationItems: viewModel.annotatedPlaceCards
            ) { card in
                MapAnnotation(coordinate: viewModel.coordinate(for: card)) {
                    Button {
                        selectedCard = card
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title)
                                .foregroundStyle(.red)
                            Text(card.name)
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .background(.thinMaterial, in: Capsule())
                        }
                    }
                }
            }
            .navigationTitle("지도")
            .sheet(item: $selectedCard) { card in
                NavigationStack {
                    PlaceCardDetailView(card: card)
                }
            }
        }
    }
}

#Preview {
    PlacesMapView(viewModel: MapViewModel(storageService: StorageService()))
}
