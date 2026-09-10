import Foundation

/// Hands a photo shared into PlaceCards through the Share Extension
/// (`ShareViewController`, a separate target — see `PlaceCardsShare/`)
/// over to the main app. The extension and the app run as separate
/// processes and can't talk directly, so this uses a file inside their
/// shared App Group container as the hand-off point: the extension
/// writes it, and the app reads (and deletes) it once, right when it
/// next becomes active. Compiled into both targets — kept as one small
/// file with no dependency on anything else in either target so that's
/// safe.
enum SharedImportStore {
    private static let appGroupID = "group.com.mrnoh99.PlaceCards"
    private static let pendingFileName = "pending-shared-image.jpg"

    private static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    /// Called by the Share Extension once it has the shared item's bytes.
    static func savePendingImage(_ data: Data) {
        guard let url = containerURL?.appendingPathComponent(pendingFileName) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Reads and deletes the pending shared image, if any — this consumes
    /// it, so call it only once per hand-off (right when the main app
    /// becomes active).
    static func takePendingImage() -> Data? {
        guard let url = containerURL?.appendingPathComponent(pendingFileName),
              let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.removeItem(at: url)
        return data
    }
}
