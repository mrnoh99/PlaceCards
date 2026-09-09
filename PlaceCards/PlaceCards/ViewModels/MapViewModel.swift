import Foundation
import MapKit
import Combine

@MainActor
final class MapViewModel: ObservableObject {
    @Published var region = MKCoordinateRegion(
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
            return region.center
        }
        return CLLocationCoordinate2D(latitude: coordinates.latitude, longitude: coordinates.longitude)
    }
}
