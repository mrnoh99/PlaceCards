import Foundation
import MapKit
import SwiftUI
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
    @Published var cameraPosition: MapCameraPosition = .region(MapViewModel.defaultRegion)

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

    /// Moves the Apple map to actually show the given cards' pins — unlike
    /// Google/Naver (each fits its own web page's map to every marker it's
    /// handed via `map.fitBounds`), this app's Apple map otherwise just
    /// sits on `defaultRegion` (Seoul) forever, since nothing else ever
    /// touches `cameraPosition` besides a search match. Reported as
    /// "선택하면 지도가 pin이 있는 곳으로 이동을 안 한다" — called by
    /// `PlacesMapView` whenever Apple becomes the active map provider.
    func fitToVisiblePlaces(_ cards: [PlaceCard]) {
        let coordinates = cards.compactMap { card -> CLLocationCoordinate2D? in
            guard let coordinates = card.coordinates else { return nil }
            return CLLocationCoordinate2D(latitude: coordinates.latitude, longitude: coordinates.longitude)
        }
        guard let region = Self.boundingRegion(for: coordinates) else { return }
        cameraPosition = .region(region)
    }

    /// Apple's own `Map` doesn't actually zoom out to a true whole-world
    /// view the way Google's web-based one does — reported directly:
    /// "애플지도는 줌아웃 기능이 세계를 한 화면에 보여줄 수 없다". Asking
    /// for a wider span than it can really render doesn't fail outright,
    /// it just clamps to whatever its actual max zoom-out happens to be,
    /// with no guarantee every pin this was supposed to fit still lands
    /// inside that. Capped well under that ceiling instead of trusting it,
    /// so cards spread across, say, Korea and the US still get a sane,
    /// fully-honored (if very zoomed out) region — one MapKit can actually
    /// render — rather than a request it silently can't keep.
    private static let maxFitSpanDegrees: Double = 60

    /// A single pin gets a fixed close-in span (nothing to "fit" against);
    /// several pins get a region spanning all of them, padded by 30% so
    /// the outermost pins aren't flush against the screen edge, with a
    /// floor on the span so two pins a few meters apart don't produce a
    /// street-level zoom that clips everything else around them, and a
    /// ceiling (`maxFitSpanDegrees`) for the opposite case — pins spread
    /// across countries/continents.
    private static func boundingRegion(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        guard !coordinates.isEmpty else { return nil }
        guard coordinates.count > 1 else {
            return MKCoordinateRegion(center: coordinates[0], span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
        }

        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        guard let minLatitude = latitudes.min(), let maxLatitude = latitudes.max(),
              let minLongitude = longitudes.min(), let maxLongitude = longitudes.max() else {
            return nil
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: min(max((maxLatitude - minLatitude) * 1.3, 0.02), maxFitSpanDegrees),
            longitudeDelta: min(max((maxLongitude - minLongitude) * 1.3, 0.02), maxFitSpanDegrees)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}
