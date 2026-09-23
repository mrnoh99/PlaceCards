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
    @MainActor
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
    ///
    /// **폴더 형식으로 쓴다**(`BackupService.writeBundle`): 확장자 없는
    /// 폴더 하나에 `metadata.json`과 `photos/`가 들어간다. 예전에는 사진을
    /// base64로 인라인한 `.json` 파일 하나였는데, 그 인코딩이 사진 전체를
    /// 두 벌로 메모리에 올려 라이브러리가 커지자 앱이 죽었다 —
    /// `BackupService.bundleMetadataName`의 주석에 전말이 있다.
    ///
    /// `async`인 이유는 그대로다. 사진을 옮기는 일이 메인 액터에서
    /// 돌면 시작할 때와 포그라운드로 올 때마다 화면이 멈춘다.
    ///
    /// 보안 스코프는 이제 **쓰는 일 전체를 감싼다.** 예전에는 데이터가
    /// 손에 들어온 뒤에만 열었는데, 그때는 오래 걸리는 부분이 인코딩이고
    /// 쓰기는 한 번이었다. 지금은 사진을 한 장씩 그 폴더 안으로 복사하는
    /// 것이 오래 걸리는 부분이라 그 내내 열려 있어야 한다.
    @MainActor
    @discardableResult
    static func runNow(storageService: StorageService) async -> Bool {
        guard let folderURL = resolveFolderURL() else { return false }

        let accessed = folderURL.startAccessingSecurityScopedResource()
        defer { if accessed { folderURL.stopAccessingSecurityScopedResource() } }
        let bundleURL = folderURL.appendingPathComponent(BackupService.filename())
        do {
            try await BackupService.writeBundle(to: bundleURL, storageService: storageService)
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
    static func runIfDue(storageService: StorageService) async {
        let settings = BackupFolderSettings.shared
        guard settings.autoBackupEnabled else { return }
        let intervalSeconds = TimeInterval(settings.autoBackupIntervalDays) * 24 * 60 * 60
        if let lastAutoBackupAt = settings.lastAutoBackupAt,
           Date.now.timeIntervalSince(lastAutoBackupAt) < intervalSeconds {
            return
        }
        await runNow(storageService: storageService)
    }
}
