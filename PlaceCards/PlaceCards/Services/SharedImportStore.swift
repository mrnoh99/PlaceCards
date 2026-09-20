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
    /// `savePendingImages` and `takePendingImages` are no-ops without a
    /// container. Exposed so Settings can surface this instead of leaving
    /// "the shared photo never showed up" a mystery.
    static var isAppGroupAvailable: Bool { containerURL != nil }

    /// How many photos one share can hand over. Matches
    /// `AddPlaceCardView.maxPhotos` — the same ceiling the in-app picker
    /// uses — and `NSExtensionActivationSupportsImageWithMaxCount` in the
    /// extension's own Info.plist, which is what actually decides whether
    /// PinSpots even appears in the share sheet for a multi-photo
    /// selection.
    static let maxPendingImages = 10

    /// The first photo keeps the original file name, and the rest get a
    /// numbered one. That is deliberate rather than tidy: a build of the
    /// app that predates multi-photo sharing reads only the base name, so
    /// it still finds the first photo instead of finding nothing at all.
    private static func pendingImageURL(index: Int) -> URL? {
        guard let containerURL else { return nil }
        return containerURL.appendingPathComponent(
            index == 0 ? pendingFileName : "pending-shared-image-\(index).jpg"
        )
    }

    /// Called by the Share Extension once it has the shared items' bytes.
    /// Anything past `maxPendingImages` is dropped here rather than
    /// written and ignored later.
    static func savePendingImages(_ datas: [Data]) {
        guard containerURL != nil else { return }
        // Clear the whole set first. Without this, a share of three
        // photos followed by a share of one would leave the previous
        // share's second and third photos on disk, and the next read
        // would hand all three to the app as if they had arrived
        // together.
        removePendingImageFiles()
        for (index, data) in datas.prefix(maxPendingImages).enumerated() {
            guard let url = pendingImageURL(index: index) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Reads and deletes every pending shared photo — this consumes them,
    /// so call it only once per hand-off (right when the main app becomes
    /// active). Empty when nothing is waiting.
    ///
    /// Stops at the first gap rather than scanning the whole range, so a
    /// leftover numbered file from an interrupted write can never graft
    /// itself onto an unrelated later share. Every slot is deleted
    /// afterwards regardless, gap or not.
    static func takePendingImages() -> [Data] {
        var datas: [Data] = []
        for index in 0..<maxPendingImages {
            guard let url = pendingImageURL(index: index),
                  let data = try? Data(contentsOf: url) else { break }
            datas.append(data)
        }
        removePendingImageFiles()
        return datas
    }

    private static func removePendingImageFiles() {
        for index in 0..<maxPendingImages {
            guard let url = pendingImageURL(index: index) else { return }
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Written by the Share Extension at every branch of its handling
    /// (found/not found, load error, unreadable data, success) — since the
    /// extension has no visible console once installed on-device, this
    /// file is the only way to see *why* a share didn't produce a pending
    /// image (as opposed to `isAppGroupAvailable`, which only says whether
    /// the container itself resolves). Overwritten each time, so it always
    /// holds the most recent attempt, successful or not.
    ///
    /// Read out of band — the App Group container, via Xcode's device
    /// container download or the Files app — rather than from anywhere in
    /// the app. Settings used to print it as a "마지막 공유 시도" row,
    /// which showed an end user a developer's log line they had no use
    /// for; this is a diagnostic for whoever is debugging the extension,
    /// and that person has the container.
    static func recordDebugStatus(_ message: String) {
        guard let url = containerURL?.appendingPathComponent(debugStatusFileName) else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm:ss"
        let stamped = "\(formatter.string(from: Date())) — \(message)"
        try? stamped.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    /// Called by the Share Extension when the shared item is a link or
    /// plain text (e.g. the URL iOS offers to share right after a
    /// screenshot taken inside Safari/a web view, or Naver Map's own
    /// "공유" text) rather than an image — a separate pending slot from
    /// `savePendingImages` so an image share and a link share in quick
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
