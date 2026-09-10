import SwiftUI
import MapKit

struct PlacesMapView: View {
    @StateObject private var viewModel: MapViewModel
    @EnvironmentObject private var navigation: AppNavigation
    @State private var selectedCard: PlaceCard?

    init(viewModel: MapViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    /// Narrowed to `navigation.mapFilterIDs` when a board's "지도에서
    /// 보기" bulk action set it — otherwise every card, as usual.
    private var visibleCards: [PlaceCard] {
        guard let filterIDs = navigation.mapFilterIDs else { return viewModel.annotatedPlaceCards }
        return viewModel.annotatedPlaceCards.filter { filterIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Map(
                coordinateRegion: $viewModel.region,
                annotationItems: visibleCards
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
            .navigationTitle(navigation.mapFilterIDs == nil ? "지도" : "선택한 장소")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if navigation.mapFilterIDs != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("전체 보기") { navigation.mapFilterIDs = nil }
                    }
                }
            }
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
        .environmentObject(AppNavigation())
}
