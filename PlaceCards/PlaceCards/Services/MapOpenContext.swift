import Foundation

/// Remembers which card most recently launched "지도에서 열기" — read back
/// when a photo or link comes in through the Share Extension
/// (`SharedImportStore`) so something shared right after opening a map app
/// can be offered as "add this to the card you just opened the map for"
/// instead of always routing through "pick a board, create a new card"
/// (`SharedPhotoBoardPickerSheet`/`SharedLinkBoardPickerSheet`). Plain
/// `UserDefaults` — this only needs to survive the app being backgrounded/
/// suspended while the user is in the map app, not to be shared with the
/// Share Extension process itself (that only ever writes the photo/link,
/// via `SharedImportStore`'s own App Group container).
enum MapOpenContext {
    private static let cardIDKey = "mapOpenContext.cardID"
    private static let timestampKey = "mapOpenContext.timestamp"

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
        UserDefaults.standard.set(cardID, forKey: cardIDKey)
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

    static func clear() {
        UserDefaults.standard.removeObject(forKey: cardIDKey)
        UserDefaults.standard.removeObject(forKey: timestampKey)
    }
}
