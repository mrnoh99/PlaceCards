import CoreLocation

/// One-shot fetch of the device's current location, for the "현재 위치"
/// (Here) option at the top of the distance-sort reference menu. Ported
/// from Peragra's `LocationService` (there used for tagging a photo with
/// where it was taken).
///
/// `@MainActor` deliberately — every caller (`PlaceStatusFilterBar`'s
/// `Task { hereCoordinate = await LocationService.currentLocation() }`)
/// already runs on the main actor, but `currentLocation()`/`fetch()`
/// weren't themselves isolated to it, so `await`ing them from a
/// MainActor context hopped this class's `CLLocationManager` onto
/// whatever background thread Swift Concurrency's cooperative pool
/// happened to run the call on. `CLLocationManager` is only reliable
/// when created and driven from the same thread throughout (Apple's own
/// guidance is main-thread) — off that thread its delegate callbacks can
/// simply never fire, which silently produced exactly this bug: "현재
/// 위치" never resolves a coordinate, distance never shows, and the
/// 8-second timeout is all that ever ends the wait.
@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<Coordinates?, Never>?

    static func currentLocation() async -> Coordinates? {
        let service = LocationService()
        return await service.fetch()
    }

    /// Whether a previously-denied/restricted permission — not "not asked
    /// yet" or "granted but the fix above simply hasn't resolved yet" —
    /// is why `currentLocation()` just returned nil. `CLLocationManager`
    /// is safe to construct fresh here just to read this; it's a
    /// synchronous property read, not a fetch. Lets a caller tell "still
    /// waiting"/"no signal" apart from "will never resolve until Settings
    /// is changed" and show the right message for each instead of the
    /// silent, indistinguishable nil both used to produce.
    static func isAuthorizationDenied() -> Bool {
        let status = CLLocationManager().authorizationStatus
        return status == .denied || status == .restricted
    }

    private func fetch() async -> Coordinates? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.delegate = self
            switch manager.authorizationStatus {
            case .notDetermined:
                // Don't start the timeout yet — it's not waiting on a
                // location fix yet, but on however long the person takes
                // to respond to the system permission dialog, which
                // routinely exceeds a few seconds. Starting it here was
                // the actual bug behind "현재 위치" never showing a
                // distance on first use: the timeout fired and resolved
                // this call with nil before the person even answered the
                // prompt, so the real fix that arrived once they granted
                // it (see locationManagerDidChangeAuthorization) had
                // nothing left to resume — `continuation` was already
                // nil, so it was silently dropped every time.
                manager.requestWhenInUseAuthorization()
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
                startTimeout()
            default:
                finish(with: nil)
            }
        }
    }

    /// A denied/restricted authorization never calls back, and even an
    /// authorized fetch can hang (poor signal, background throttling) —
    /// this guarantees the caller isn't stuck waiting forever. Only
    /// started once a location fix has actually been requested, not
    /// while still waiting on the permission dialog.
    private func startTimeout() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.finish(with: nil)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
            startTimeout()
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
