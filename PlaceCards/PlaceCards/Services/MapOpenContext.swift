import Foundation

/// Remembers which card most recently launched "지도에서 열기" — read back
/// when a photo comes in through the Share Extension (`SharedImportStore`)
/// so a screenshot taken right after opening a map app can be offered as
/// "add this to the card you just opened the map for" instead of always
/// routing through "pick a board, create a new card"
/// (`SharedPhotoBoardPickerSheet`). Plain `UserDefaults` — this only
/// needs to survive the app being backgrounded/suspended while the user
/// is in the map app, not to be shared with the Share Extension process
/// itself (that only ever writes the photo, via `SharedImportStore`'s own
/// App Group container).
enum MapOpenContext {
    private static let cardIDKey = "mapOpenContext.cardID"
    private static let timestampKey = "mapOpenContext.timestamp"

    /// A screenshot shared back after this long is more likely to be
    /// unrelated to the map open that started this — treated as expired
    /// rather than risk silently misattributing it to the wrong card.
    private static let validityWindow: TimeInterval = 30 * 60

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
