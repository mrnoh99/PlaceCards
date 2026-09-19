import Foundation

/// Remembers what the user left the app for when they launched a map —
/// read back when a photo or link comes in through the Share Extension
/// (`SharedImportStore`), so something shared right after opening a map
/// app can be joined up with whatever it was about instead of arriving
/// with no context at all.
///
/// There are two such things, and a map open is exactly one of them:
///
/// - **A saved card** (`recordMapOpen(cardID:)`), from "지도에서 열기" on a
///   card that already exists. What comes back is offered as "add this to
///   the card you just opened the map for" rather than routing through
///   "pick a board, create a new card".
/// - **Photos not yet saved to anything** (`recordMapOpen(photoDatas:)`),
///   from `AddPlaceCardView`'s "GPS로 촬영위치찾기" — the user picked
///   photos, had no name or address for them, and went to a map app to
///   find the place by where the photos were taken. What comes back is
///   the place, and these are the photos it belongs to.
///
///   Without this the photos were simply lost: the incoming share closes
///   `AddPlaceCardView`, taking its `@State` (and the picked photos) with
///   it, and the card then built from the shared link had no photo on it —
///   the user had to pick the very same photos again, on a card they had
///   just created *because* of those photos.
///
/// The two are mutually exclusive — recording either clears the other,
/// since a single map open cannot have been about both.
///
/// Recorded only where opening a map plausibly means "let me look this
/// place up" — deliberately not for Tmap, whose whole purpose is
/// turn-by-turn navigation: tapping it means the user is driving there,
/// and anything they share during or after that trip has no particular
/// reason to be about this card. Plain
/// `UserDefaults` — this only needs to survive the app being backgrounded/
/// suspended while the user is in the map app, not to be shared with the
/// Share Extension process itself (that only ever writes the photo/link,
/// via `SharedImportStore`'s own App Group container).
enum MapOpenContext {
    private static let cardIDKey = "mapOpenContext.cardID"
    private static let timestampKey = "mapOpenContext.timestamp"

    /// Photo bytes go to a file, not `UserDefaults` — there can be up to
    /// ten of them at full camera resolution, which is not what the
    /// defaults database is for. Inside the app's own caches directory
    /// (not the App Group container `SharedImportStore` uses): the Share
    /// Extension never reads these, only the app that wrote them, and
    /// losing them to a cache purge is a recoverable inconvenience rather
    /// than data loss — the photos are still in the user's library.
    private static let photosDirectoryName = "PendingMapOpenPhotos"

    /// A screenshot shared back after this long is more likely to be
    /// unrelated to the map open that started this — treated as expired
    /// rather than risk silently misattributing it to the wrong card.
    /// Was 30 minutes, which turned out far too generous in practice:
    /// reported as sharing an unrelated new place (after browsing the map
    /// app for something else entirely) silently merging into whatever
    /// card had last launched "지도에서 열기", instead of going through the
    /// normal "pick a board, create a new card" flow — the user would end
    /// up looking at that old, already-open card again instead of a new
    /// one. 5 minutes still comfortably covers the actual intended case
    /// (open the map app, glance at/confirm the place, share it straight
    /// back) without staying "recent" long enough to catch unrelated
    /// browsing later in the same map session.
    private static let validityWindow: TimeInterval = 5 * 60

    static func recordMapOpen(cardID: String) {
        clearPhotos()
        UserDefaults.standard.set(cardID, forKey: cardIDKey)
        UserDefaults.standard.set(Date(), forKey: timestampKey)
    }

    /// The photos the user had picked when they left for a map app to
    /// find where they were taken. Written to disk rather than held in
    /// memory because the app can be terminated while the user is off in
    /// the map app — which is precisely the case where losing them costs
    /// the most, since by then they have spent a while finding the place.
    ///
    /// Numbered so the original order survives the round trip; the
    /// directory is emptied first so a second map open never mixes its
    /// photos with the previous one's.
    static func recordMapOpen(photoDatas: [Data]) {
        clearPhotos()
        UserDefaults.standard.removeObject(forKey: cardIDKey)
        guard !photoDatas.isEmpty, let directory = photosDirectoryURL() else { return }
        for (index, data) in photoDatas.enumerated() {
            let url = directory.appendingPathComponent(String(format: "%02d.dat", index))
            try? data.write(to: url, options: .atomic)
        }
        UserDefaults.standard.set(Date(), forKey: timestampKey)
    }

    /// The card ID that most recently launched "지도에서 열기", if that
    /// happened recently enough to still plausibly be what a
    /// just-shared screenshot is about. Does not clear itself — call
    /// `clear()` once the caller has acted on (or decided not to act on)
    /// the result.
    static func recentCardID() -> String? {
        guard let date = UserDefaults.standard.object(forKey: timestampKey) as? Date,
              Date().timeIntervalSince(date) < validityWindow else {
            return nil
        }
        return UserDefaults.standard.string(forKey: cardIDKey)
    }

    /// Those photos, if the map open was recent enough to still be what a
    /// just-arrived share is about. Like `recentCardID()` this does not
    /// clear itself — the caller takes them into the share it is about to
    /// present and calls `clear()`, so they travel with that share rather
    /// than being read back later from here (by which time `clear()` has
    /// already run).
    static func recentPhotoDatas() -> [Data] {
        guard let date = UserDefaults.standard.object(forKey: timestampKey) as? Date,
              Date().timeIntervalSince(date) < validityWindow,
              let directory = photosDirectoryURL(createIfNeeded: false),
              let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return []
        }
        return names.sorted().compactMap { try? Data(contentsOf: directory.appendingPathComponent($0)) }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: cardIDKey)
        UserDefaults.standard.removeObject(forKey: timestampKey)
        clearPhotos()
    }

    private static func clearPhotos() {
        guard let directory = photosDirectoryURL(createIfNeeded: false) else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    private static func photosDirectoryURL(createIfNeeded: Bool = true) -> URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = base.appendingPathComponent(photosDirectoryName, isDirectory: true)
        if createIfNeeded {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }
}
