import Foundation

/// A silent iCloud-container JSON snapshot, independent of the user-facing
/// Backup/Restore and folder-schedule features — ported from Peragra's own
/// `CloudBackupService`. Not triggered by any button; `MainTabView` calls
/// it on every foreground/background transition, and calls
/// `loadRestorableBackup` once at cold launch (only when local storage is
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
    private static let isEnabledKey = "cloudBackupEnabled"

    /// Whether the silent snapshot is allowed to run at all.
    ///
    /// This used to have no switch and no disclosure: it wrote the entire
    /// library — every photo's bytes included, since `BackupService`
    /// started embedding those — into iCloud on every foreground and
    /// background transition, and the user was told only if it ever
    /// restored something. The data goes to the user's own iCloud account
    /// rather than any server of ours, which is why it stays on by
    /// default (turning it off for everyone would silently retire the
    /// safety net that people who reinstall or change phones are already
    /// relying on, without them asking for that either). What was
    /// actually missing was the user being able to see it and say no, so
    /// Settings now shows it, explains what goes there, and can turn it
    /// off — which also deletes what is already stored.
    static var isEnabled: Bool {
        // `object(forKey:)`, not `bool(forKey:)` — the latter reads an
        // unset key as `false`, which would read as "the user turned this
        // off" for every install that predates the switch.
        UserDefaults.standard.object(forKey: isEnabledKey) as? Bool ?? true
    }

    @MainActor
    static func setEnabled(_ enabled: Bool) async {
        UserDefaults.standard.set(enabled, forKey: isEnabledKey)
        if enabled {
            // Forget what was last written so re-enabling actually
            // produces a snapshot on the next transition, rather than
            // matching a fingerprint left over from before and skipping.
            lastBackedUpFingerprint = nil
        } else {
            await deleteStoredBackup()
        }
    }

    /// Removes the snapshot from iCloud. Turning the setting off has to
    /// take the already-stored copy with it — otherwise "off" would only
    /// mean "stop adding to it", and the library sitting in iCloud from
    /// before would stay there with no way to remove it from inside the
    /// app.
    @MainActor
    static func deleteStoredBackup() async {
        guard let containerURL = await resolveContainerDocumentsURL() else { return }
        let fileURL = containerURL.appendingPathComponent(filename)
        await Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: fileURL)
        }.value
        lastBackedUpFingerprint = nil
    }

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

    /// A cheap "did anything actually change" fingerprint, checked before
    /// paying for a full re-export — `BackupService.exportData` now embeds
    /// every photo's actual bytes (see its own doc comment), so where this
    /// used to be a small, harmless JSON re-write on every single
    /// foreground/background transition `MainTabView` triggers it from,
    /// skipping it here when nothing's new avoids repeatedly re-reading
    /// and re-writing however many megabytes of photos this device has.
    /// Card count/deletion and any card edit are both covered by
    /// `updatedAt`; a board-only edit (a rename, no card touched) can slip
    /// past this undetected — an acceptable trade for how rarely that
    /// happens against how often this fires otherwise, and it's still
    /// caught the next time any card actually changes.
    @MainActor
    private static var lastBackedUpFingerprint: Int?

    @MainActor
    private static func fingerprint(for storageService: StorageService) -> Int {
        var hasher = Hasher()
        hasher.combine(storageService.boards.count)
        hasher.combine(storageService.placeCards.count)
        hasher.combine(storageService.placeCards.map(\.updatedAt).max())
        return hasher.finalize()
    }

    /// Best-effort — exports the full data set and overwrites the single
    /// snapshot file in the app's iCloud container. Never throws; a
    /// failure here (no container, no iCloud account, a write error)
    /// just means this particular snapshot didn't happen.
    @MainActor
    static func backup(storageService: StorageService) async {
        guard isEnabled else { return }
        let currentFingerprint = fingerprint(for: storageService)
        guard currentFingerprint != lastBackedUpFingerprint else { return }
        guard let containerURL = await resolveContainerDocumentsURL() else { return }
        guard let data = try? await BackupService.exportData(storageService: storageService) else { return }
        await Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
            try? data.write(to: containerURL.appendingPathComponent(filename), options: .atomic)
        }.value
        lastBackedUpFingerprint = currentFingerprint
    }

    /// The snapshot itself, decoded, or `nil` when there's nothing
    /// restorable (no container, no file, undecodable, or an empty
    /// backup). Returns the decoded payload rather than just a yes/no so
    /// the caller can hand it straight to
    /// `BackupService.restore(_:storageService:)` — this used to be a
    /// `hasRestorableBackup()` bool that fully decoded the document (every
    /// photo's base64 bytes included) only to check `boards.isEmpty`, and
    /// then a separate `restoreIfAvailable` that read and decoded the exact
    /// same document all over again, both at cold launch with the startup
    /// intro screen held up behind them.
    static func loadRestorableBackup() async -> BackupService.BackupData? {
        guard isEnabled else { return nil }
        guard let containerURL = await resolveContainerDocumentsURL() else { return nil }
        let fileURL = containerURL.appendingPathComponent(filename)
        return await Task.detached(priority: .utility) { () -> BackupService.BackupData? in
            // On a device that has never opened this file, iCloud keeps it
            // as a metadata-only placeholder until something asks for the
            // real bytes — `Data(contentsOf:)` alone just fails there. That
            // is exactly the "new phone / reinstall" case this whole
            // service exists for, so the download is requested and waited
            // on rather than treated as "no backup".
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                try? FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
                for _ in 0..<Int(downloadWaitSeconds * 10) {
                    if FileManager.default.fileExists(atPath: fileURL.path) { break }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }
            guard let data = try? Data(contentsOf: fileURL),
                  let decoded = try? BackupService.decode(data),
                  !decoded.boards.isEmpty else { return nil }
            return decoded
        }.value
    }

    /// How long `loadRestorableBackup()` waits for iCloud to materialize a
    /// placeholder file before giving up — long enough for a snapshot to
    /// come down on a normal connection, short enough that a device with
    /// no usable iCloud never holds the launch screen up for it.
    private static let downloadWaitSeconds: TimeInterval = 10
}
