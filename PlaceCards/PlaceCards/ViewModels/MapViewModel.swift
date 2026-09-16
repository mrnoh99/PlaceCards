import Foundation
import MapKit
import Combine

@MainActor
final class MapViewModel: ObservableObject {
    /// `MapCameraPosition`, not a plain `MKCoordinateRegion` — the "지도"
    /// tab's Apple map (`PlacesMapView.appleMap`) used to bind a region
    /// straight into the deprecated `Map(coordinateRegion:)` initializer,
    /// which `PlaceCardDetailView` already documents as carrying a
    /// well-known MapKit bug (tiles/gestures can get stuck non-responsive).
    /// This is the same `Map(position:)` composable API that fix already
    /// switched to there.
    @Published var cameraPosition: MapCameraPosition = .region(Self.defaultRegion)

    private static let defaultRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )

    private let storageService: StorageService

    init(storageService: StorageService) {
        self.storageService = storageService
    }

    var annotatedPlaceCards: [PlaceCard] {
        storageService.placeCards.filter { $0.coordinates != nil }
    }

    func coordinate(for card: PlaceCard) -> CLLocationCoordinate2D {
        guard let coordinates = card.coordinates else {
            return cameraPosition.region?.center ?? Self.defaultRegion.center
        }
        return CLLocationCoordinate2D(latitude: coordinates.latitude, longitude: coordinates.longitude)
    }

    /// Recenters the Apple map on a coordinate (a search match) without
    /// resetting whatever zoom level the person already panned/pinched to.
    func recenter(on coordinate: CLLocationCoordinate2D) {
        let span = cameraPosition.region?.span ?? Self.defaultRegion.span
        cameraPosition = .region(MKCoordinateRegion(center: coordinate, span: span))
    }
}
