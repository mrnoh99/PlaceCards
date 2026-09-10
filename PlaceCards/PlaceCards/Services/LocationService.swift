import CoreLocation

/// One-shot fetch of the device's current location, for the "현재 위치"
/// (Here) option at the top of the distance-sort reference menu. Ported
/// from Peragra's `LocationService` (there used for tagging a photo with
/// where it was taken).
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<Coordinates?, Never>?

    static func currentLocation() async -> Coordinates? {
        let service = LocationService()
        return await service.fetch()
    }

    private func fetch() async -> Coordinates? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.delegate = self
            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
            default:
                finish(with: nil)
            }
            // A denied/restricted authorization never calls back, and even
            // an authorized fetch can hang (poor signal, background
            // throttling) — this guarantees the caller isn't stuck waiting
            // forever.
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                self?.finish(with: nil)
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            finish(with: nil)
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else {
            finish(with: nil)
            return
        }
        finish(with: Coordinates(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(with: nil)
    }

    private func finish(with coordinate: Coordinates?) {
        continuation?.resume(returning: coordinate)
        continuation = nil
    }
}
