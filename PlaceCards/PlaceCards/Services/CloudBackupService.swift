import Foundation

/// A silent iCloud-container JSON snapshot, independent of the user-facing
/// Backup/Restore and folder-schedule features — ported from Peragra's own
/// `CloudBackupService`. Not triggered by any button; `MainTabView` calls
/// it on every foreground/background transition, and calls
/// `restoreIfAvailable` once at cold launch (only when local storage is
/// still empty, so a legitimately empty first run is never clobbered) —
/// a last-resort safety net for "I reinstalled the app / got a new
/// phone and never made a manual backup."
///
/// Requires the `com.apple.developer.icloud-container-identifiers` /
/// `com.apple.developer.ubiquity-container-identifiers` entitlements
/// (`PlaceCards.entitlements`) and the iCloud capability to actually be
/// provisioned for this app in Xcode/the Apple Developer account — same
/// class of setup step as the Share Extension's App Group earlier in
/// this project, and the same failure mode if it's missing: every call
/// below just silently no-ops (`resolveContainerDocumentsURL()` returns
/// nil) rather than crashing.
enum CloudBackupService {
    private static let filename = "placecards_auto_backup.json"

    /// Resolving the ubiquity container URL can block for a long time on
    /// first launch, so this is only ever done off the main thread — and
    /// cached, since the container's own URL never changes mid-session.
    /// `nil` cached inside the optional-of-optional means "resolved, and
    /// there's no container" (e.g. iCloud Drive off, not signed in),
    /// which is distinct from "not resolved yet".
    @MainActor
    private static var cachedContainerDocumentsURL: URL??

    @MainActor
    private static func resolveContainerDocumentsURL() async -> URL? {
        if let cached = cachedContainerDocumentsURL { return cached }
        let resolved = await Task.detached(priority: .utility) {
            FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents")
        }.value
        cachedContainerDocumentsURL = resolved
        return resolved
    }

    /// Best-effort — exports the full data set and overwrites the single
    /// snapshot file in the app's iCloud container. Never throws; a
    /// failure here (no container, no iCloud account, a write error)
    /// just means this particular snapshot didn't happen.
    @MainActor
    static func backup(storageService: StorageService) async {
        guard let containerURL = await resolveContainerDocumentsURL() else { return }
        guard let data = try? BackupService.exportData(storageService: storageService) else { return }
        try? FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
        let fileURL = containerURL.appendingPathComponent(filename)
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Whether a real, non-empty snapshot exists — checked before
    /// `restoreIfAvailable` actually applies anything, and before
    /// `MainTabView` shows its "iCloud에서 복원됨" alert.
    static func hasRestorableBackup() async -> Bool {
        guard let containerURL = await resolveContainerDocumentsURL() else { return false }
        let fileURL = containerURL.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? BackupService.decode(data) else { return false }
        return !decoded.boards.isEmpty
    }

    @MainActor
    static func restoreIfAvailable(storageService: StorageService) async {
        guard let containerURL = await resolveContainerDocumentsURL() else { return }
        let fileURL = containerURL.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: fileURL) else { return }
        try? BackupService.restore(from: data, storageService: storageService)
    }
}
