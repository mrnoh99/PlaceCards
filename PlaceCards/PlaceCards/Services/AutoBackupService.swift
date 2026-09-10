import Foundation

/// Scheduled backup-to-a-folder logic, ported from Peragra's own
/// `AutoBackupService` — including its explicit design choice to *not*
/// use `BGTaskScheduler`/any real OS background task (Peragra has no
/// `UIBackgroundModes` entitlement wired up, and neither does PlaceCards):
/// this only ever runs while the app is actually open, checked at cold
/// launch and on every foreground transition (see `MainTabView`), gated
/// by comparing `lastAutoBackupAt` against the configured interval so it
/// doesn't write a fresh file every single time the app comes forward.
enum AutoBackupService {
    private static func resolveFolderURL() -> URL? {
        guard let bookmark = BackupFolderSettings.shared.folderBookmark else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale
        ) else {
            BackupFolderSettings.shared.setNeedsReauthorization(true)
            return nil
        }
        if isStale, let refreshed = try? url.bookmarkData() {
            BackupFolderSettings.shared.setFolder(bookmark: refreshed, displayName: url.lastPathComponent)
        }
        return url
    }

    /// Writes a fresh backup to the chosen folder right now, regardless
    /// of the interval — used by both "지금 백업" (manual, in Settings)
    /// and `runIfDue` once it's decided a run is actually due.
    @MainActor
    @discardableResult
    static func runNow(storageService: StorageService) -> Bool {
        guard let folderURL = resolveFolderURL() else { return false }
        let accessed = folderURL.startAccessingSecurityScopedResource()
        defer { if accessed { folderURL.stopAccessingSecurityScopedResource() } }

        guard let data = try? BackupService.exportData(storageService: storageService) else { return false }
        let fileURL = folderURL.appendingPathComponent(BackupService.filename() + ".json")
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            BackupFolderSettings.shared.setNeedsReauthorization(true)
            return false
        }
        BackupFolderSettings.shared.setLastAutoBackupAt(.now)
        return true
    }

    /// Called from `MainTabView` at cold launch and on every foreground
    /// transition — a no-op unless automatic backup is on *and* the
    /// configured interval has actually elapsed since the last run.
    @MainActor
    static func runIfDue(storageService: StorageService) {
        let settings = BackupFolderSettings.shared
        guard settings.autoBackupEnabled else { return }
        let intervalSeconds = TimeInterval(settings.autoBackupIntervalDays) * 24 * 60 * 60
        if let lastAutoBackupAt = settings.lastAutoBackupAt,
           Date.now.timeIntervalSince(lastAutoBackupAt) < intervalSeconds {
            return
        }
        runNow(storageService: storageService)
    }
}
