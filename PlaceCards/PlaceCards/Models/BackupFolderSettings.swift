import Foundation

/// Settings for PlaceCards' automatic "backup to a folder" feature —
/// ported from Peragra's own `BackupFolderSettings`. UserDefaults-backed
/// (not Keychain: a security-scoped folder bookmark and a schedule
/// preference aren't secrets) so both the Settings screen and
/// `AutoBackupService` (invoked from `MainTabView`'s own lifecycle hooks,
/// not just from Settings) can read/write it without going through a
/// view hierarchy — a plain `ObservableObject` singleton (`.shared`)
/// rather than Peragra's `@Observable` macro, matching how every other
/// settings-style class in this app (`SettingsViewModel`) is written.
@MainActor
final class BackupFolderSettings: ObservableObject {
    static let shared = BackupFolderSettings()

    private static let bookmarkKey = "autoBackupFolderBookmark"
    private static let folderNameKey = "autoBackupFolderName"
    private static let enabledKey = "autoBackupEnabled"
    private static let intervalDaysKey = "autoBackupIntervalDays"
    private static let lastBackupAtKey = "autoBackupLastAt"
    private static let needsReauthorizationKey = "autoBackupNeedsReauthorization"

    /// A security-scoped bookmark to the user-picked folder — not a plain
    /// `URL`, since a raw URL to somewhere outside the app's sandbox
    /// (Files app / iCloud Drive / another provider) stops working the
    /// next time the app launches without one.
    @Published private(set) var folderBookmark: Data?
    @Published private(set) var folderDisplayName: String?
    @Published private(set) var autoBackupEnabled: Bool
    /// Only "매일"(1)/"매주"(7) are offered in Settings, but nothing here
    /// enforces just those two values.
    @Published private(set) var autoBackupIntervalDays: Int
    @Published private(set) var lastAutoBackupAt: Date?
    /// Set when writing to the bookmarked folder fails (revoked access,
    /// a stale bookmark that failed to resolve) — surfaced in Settings so
    /// the user knows to re-pick the folder rather than backups just
    /// silently stopping.
    @Published private(set) var needsReauthorization: Bool

    private init() {
        let defaults = UserDefaults.standard
        folderBookmark = defaults.data(forKey: Self.bookmarkKey)
        folderDisplayName = defaults.string(forKey: Self.folderNameKey)
        autoBackupEnabled = defaults.bool(forKey: Self.enabledKey)
        let storedInterval = defaults.integer(forKey: Self.intervalDaysKey)
        autoBackupIntervalDays = storedInterval > 0 ? storedInterval : 1
        lastAutoBackupAt = defaults.object(forKey: Self.lastBackupAtKey) as? Date
        needsReauthorization = defaults.bool(forKey: Self.needsReauthorizationKey)
    }

    func setFolder(bookmark: Data, displayName: String) {
        folderBookmark = bookmark
        folderDisplayName = displayName
        needsReauthorization = false
        let defaults = UserDefaults.standard
        defaults.set(bookmark, forKey: Self.bookmarkKey)
        defaults.set(displayName, forKey: Self.folderNameKey)
        defaults.set(false, forKey: Self.needsReauthorizationKey)
    }

    func clearFolder() {
        folderBookmark = nil
        folderDisplayName = nil
        autoBackupEnabled = false
        needsReauthorization = false
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.bookmarkKey)
        defaults.removeObject(forKey: Self.folderNameKey)
        defaults.set(false, forKey: Self.enabledKey)
        defaults.set(false, forKey: Self.needsReauthorizationKey)
    }

    func setAutoBackupEnabled(_ enabled: Bool) {
        autoBackupEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
    }

    func setAutoBackupIntervalDays(_ days: Int) {
        autoBackupIntervalDays = days
        UserDefaults.standard.set(days, forKey: Self.intervalDaysKey)
    }

    func setLastAutoBackupAt(_ date: Date) {
        lastAutoBackupAt = date
        UserDefaults.standard.set(date, forKey: Self.lastBackupAtKey)
    }

    func setNeedsReauthorization(_ value: Bool) {
        needsReauthorization = value
        UserDefaults.standard.set(value, forKey: Self.needsReauthorizationKey)
    }
}
