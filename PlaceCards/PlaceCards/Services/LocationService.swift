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
/// timeout is all that ever ends the wait.
///
/// Answering at all is treated as the goal: a cached position is preferred
/// to making the user wait, a stale one is preferred to failing, and only
/// a genuinely denied permission or a device that has never had a fix
/// produces `nil`. "현재 위치를 가져오지 못했습니다" should be a rarity,
/// not the normal outcome of tapping "기준: 현재 위치".
@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    /// How old a cached fix may be and still answer "현재 위치". Sorting
    /// saved places by distance does not need a metre-accurate, just-taken
    /// fix — a position from the last few minutes orders a list of
    /// restaurants identically — so a cached one is preferred over making
    /// the user wait for the radio.
    private static let cachedLocationMaxAge: TimeInterval = 5 * 60
    /// Generous enough to cover a cold GPS fix indoors, and only ever
    /// reached when there is no cached fix to fall back on.
    private static let fetchTimeout: TimeInterval = 10

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<Coordinates?, Never>?
    /// `requestLocation()` must be issued exactly once per fetch — see
    /// `requestLocationOnce()`.
    private var hasRequestedLocation = false

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
            // The default is `kCLLocationAccuracyBest`, which indoors on
            // cellular can take far longer than anyone will wait — and
            // buys nothing here, since this only ever orders saved places
            // by how far away they are.
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
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
                requestLocationOnce()
            default:
                finish(with: nil)
            }
        }
    }

    /// Issues the one-shot fix, at most once per fetch, after first taking
    /// any recent cached position instead.
    ///
    /// The guard is the fix for "권한이 있는데도 현재 위치를 가져오지
    /// 못했습니다": since iOS 14 `locationManagerDidChangeAuthorization` is
    /// called *immediately* when a delegate is assigned, to report the
    /// status the manager already has. So an already-authorized fetch
    /// asked for a location twice — once here, once from that callback —
    /// and `requestLocation()` cancels any request already in flight and
    /// reports the cancelled one through `didFailWithError`. That failure
    /// then ended the whole fetch with `nil` almost instantly, which is
    /// why this failed immediately rather than after the timeout, and why
    /// it failed even with permission granted and a good signal.
    private func requestLocationOnce() {
        guard !hasRequestedLocation else { return }
        hasRequestedLocation = true

        if let cached = manager.location,
           -cached.timestamp.timeIntervalSinceNow <= Self.cachedLocationMaxAge {
            finish(with: cached.coordinates)
            return
        }
        manager.requestLocation()
        startTimeout()
    }

    /// Whatever position the system still has, however old — worth
    /// answering with when the alternative is telling the user their
    /// location is simply unavailable. Only consulted once a live fix has
    /// already failed or timed out.
    private var staleCachedCoordinates: Coordinates? {
        manager.location?.coordinates
    }

    /// A denied/restricted authorization never calls back, and even an
    /// authorized fetch can hang (poor signal, background throttling) —
    /// this guarantees the caller isn't stuck waiting forever. Only
    /// started once a location fix has actually been requested, not
    /// while still waiting on the permission dialog.
    private func startTimeout() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.fetchTimeout) { [weak self] in
            guard let self else { return }
            finish(with: staleCachedCoordinates)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            requestLocationOnce()
        case .denied, .restricted:
            finish(with: nil)
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else {
            finish(with: staleCachedCoordinates)
            return
        }
        finish(with: location.coordinates)
    }

    /// A one-shot request that couldn't produce a fresh fix isn't the same
    /// as having no idea where the device is — `CLError.locationUnknown`
    /// in particular means "not yet", not "never". Falls back to whatever
    /// position the system still holds rather than reporting failure while
    /// a perfectly usable one sits there.
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(with: staleCachedCoordinates)
    }

    private func finish(with coordinate: Coordinates?) {
        continuation?.resume(returning: coordinate)
        continuation = nil
    }
}

private extension CLLocation {
    var coordinates: Coordinates {
        Coordinates(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
