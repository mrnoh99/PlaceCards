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
    private static let pendingLinkFileName = "pending-shared-link.txt"
    private static let debugStatusFileName = "share-debug-status.txt"

    private static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    /// Whether the App Group container actually resolves — `nil` here
    /// (from `containerURL`, and so every call below) almost always means
    /// the "App Groups" capability with `group.com.mrnoh99.PlaceCards`
    /// hasn't actually been provisioned for this build (Xcode → target →
    /// Signing & Capabilities → +Capability → App Groups, on **both** the
    /// PlaceCards and PlaceCardsShare targets, with a team selected so
    /// Xcode can register the group with Apple) — everything else in this
    /// flow fails silently when that's missing, since both
    /// `savePendingImage` and `takePendingImage` are no-ops without a
    /// container. Exposed so Settings can surface this instead of leaving
    /// "the shared photo never showed up" a mystery.
    static var isAppGroupAvailable: Bool { containerURL != nil }

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

    /// Written by the Share Extension at every branch of its handling
    /// (found/not found, load error, unreadable data, success) — since the
    /// extension has no visible console once installed on-device, this is
    /// the only way to see *why* a share didn't produce a pending image
    /// (as opposed to `isAppGroupAvailable`, which only says whether the
    /// container itself resolves). Read-only from the app side via
    /// `lastDebugStatus()`; not cleared automatically so it always shows
    /// the most recent share attempt, successful or not.
    static func recordDebugStatus(_ message: String) {
        guard let url = containerURL?.appendingPathComponent(debugStatusFileName) else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm:ss"
        let stamped = "\(formatter.string(from: Date())) — \(message)"
        try? stamped.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    static func lastDebugStatus() -> String? {
        guard let url = containerURL?.appendingPathComponent(debugStatusFileName),
              let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Called by the Share Extension when the shared item is a link or
    /// plain text (e.g. the URL iOS offers to share right after a
    /// screenshot taken inside Safari/a web view, or Naver Map's own
    /// "공유" text) rather than an image — a separate pending slot from
    /// `savePendingImage` so an image share and a link share in quick
    /// succession can't clobber each other.
    static func savePendingLink(_ text: String) {
        guard let url = containerURL?.appendingPathComponent(pendingLinkFileName) else { return }
        try? text.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    static func takePendingLink() -> String? {
        guard let url = containerURL?.appendingPathComponent(pendingLinkFileName),
              let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.removeItem(at: url)
        return String(data: data, encoding: .utf8)
    }
}
