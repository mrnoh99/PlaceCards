import Foundation

/// A silent iCloud-container JSON snapshot, independent of the user-facing
/// Backup/Restore and folder-schedule features — ported from Peragra's own
/// `CloudBackupService`. Not triggered by any button; `MainTabView` calls
/// it on every foreground/background transition, and calls
/// `loadRestorableBackups` once at cold launch (only when local storage is
/// still empty, so a legitimately empty first run is never clobbered) —
/// a last-resort safety net for "I reinstalled the app / got a new
/// phone and never made a manual backup."
///
/// **기기마다 제 파일에 쓴다**(`filename`). 이름이 하나였을 때는 한 사람이
/// 기기 둘을 쓰면 서로 덮어써서, iCloud에 남는 것이 마지막에 쓴 기기의
/// 사본 하나뿐이었다 — 그 상태에서 다른 기기를 초기화하면 그 기기에만
/// 있던 카드는 복원할 데가 없었다. 복원할 때는 있는 파일을 전부 합친다.
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
    /// 기기 하나가 쓰는 파일 이름. **기기마다 다르다.**
    ///
    /// 예전에는 이름이 하나(`legacyFilename`)여서 모든 기기가 같은 파일에
    /// 썼다. 한 사람이 기기 둘을 쓰면 나중에 쓴 쪽이 앞의 것을 통째로
    /// 덮었고, iCloud에는 "마지막에 쓴 기기의 사본" 하나만 남았다. 그
    /// 상태에서 다른 기기를 초기화하면 그 기기에만 있던 카드는 복원할
    /// 데가 없어 사라진다 — 백업이 있는데도 잃는다.
    ///
    /// 나눠 두면 서로 덮지 않고, 복원은 **있는 파일을 전부 합친다**
    /// (`loadRestorableBackups`). 카드마다 `updatedAt`으로 최신이
    /// 이기므로(`StorageService.merge`) 합치는 것이 안전하다.
    private static var filename: String { "placecards_auto_backup_\(deviceID).json" }

    /// 기기를 나누기 전에 쓰던 이름. 읽을 때는 아직 본다 — 이 변경 전에
    /// 백업해 둔 사람이 새 기기에서 복원할 때 필요한 유일한 파일이다.
    private static let legacyFilename = "placecards_auto_backup.json"

    /// 파일 이름을 고를 때 쓰는 공통 앞부분. 컨테이너에서 백업 파일만
    /// 골라내는 데에도 쓴다.
    private static let filenamePrefix = "placecards_auto_backup"

    private static let isEnabledKey = "cloudBackupEnabled"
    private static let deviceIDKey = "cloudBackupDeviceID"

    /// 이 설치본을 가리키는 id. 한 번 만들어 `UserDefaults`에 둔다.
    ///
    /// `UIDevice.identifierForVendor`를 쓰지 않는다. 그 값은 최신 SDK에서
    /// 메인 액터에 묶여 있어 여기(백그라운드에서도 불린다)에서 읽기가
    /// 번거롭고, 앱을 지웠다 깔면 어차피 새 값이 된다 — 직접 만드는 것과
    /// 수명이 같다.
    ///
    /// 지웠다 깔면 새 id가 되므로 예전 파일이 iCloud에 남는다. 그래도
    /// 복원은 남은 것까지 전부 합치므로 손해가 아니라 이득이다.
    private static var deviceID: String {
        if let existing = UserDefaults.standard.string(forKey: deviceIDKey) { return existing }
        let created = UUID().uuidString
        UserDefaults.standard.set(created, forKey: deviceIDKey)
        return created
    }

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
    ///
    /// 지우는 것은 **이 기기가 쓴 파일과 옛 공용 파일**뿐이다. 다른 기기가
    /// 쓴 파일은 그 기기의 것이고, 이 설정은 기기마다 따로다. 옛 공용
    /// 파일을 같이 지우는 것은 그것이 누가 썼는지 알 길이 없기 때문이다 —
    /// 이 기기가 썼을 수 있는 것을 남겨 두면 "끄기"가 절반만 되는 셈이다.
    /// 아직 켜 둔 다른 기기가 있다면 다음 실행에서 제 파일을 다시 쓴다.
    @MainActor
    static func deleteStoredBackup() async {
        guard let containerURL = await resolveContainerDocumentsURL() else { return }
        let ownURL = containerURL.appendingPathComponent(filename)
        let legacyURL = containerURL.appendingPathComponent(legacyFilename)
        await Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: ownURL)
            try? FileManager.default.removeItem(at: legacyURL)
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
    static func loadRestorableBackups() async -> [BackupService.BackupData] {
        guard isEnabled else { return [] }
        guard let containerURL = await resolveContainerDocumentsURL() else { return [] }
        let candidates = await candidateFileURLs(in: containerURL)
        guard !candidates.isEmpty else { return [] }

        return await Task.detached(priority: .utility) { () -> [BackupService.BackupData] in
            // 아직 안 내려온 것들의 내려받기를 **전부 먼저 걸고, 기다리는
            // 것은 한 번만** 한다. 파일마다 따로 기다리면 기기 수만큼
            // 시작 화면이 붙잡힌다 — 기기 셋이면 30초다.
            let missing = candidates.filter { !FileManager.default.fileExists(atPath: $0.path) }
            for url in missing {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            }
            if !missing.isEmpty {
                for _ in 0..<Int(downloadWaitSeconds * 10) {
                    if missing.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) { break }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }
            // 내려오지 못한 것은 그냥 빠진다. 하나라도 읽히면 그만큼은
            // 복원되고, 못 읽은 기기 것은 다음 실행에서 다시 시도된다.
            return candidates.compactMap { (url: URL) -> BackupService.BackupData? in
                guard let data = try? Data(contentsOf: url),
                      let decoded = try? BackupService.decode(data),
                      !decoded.boards.isEmpty else { return nil }
                return decoded
            }
        }.value
    }

    /// 컨테이너 안의 백업 파일들, **오래된 것부터.**
    ///
    /// 카드는 `updatedAt`으로 최신이 이기므로 순서를 안 타지만, 게시판에는
    /// `updatedAt`이 없어 같은 id가 겹치면 나중에 넘긴 쪽이 남는다.
    ///
    /// 이 기기가 한 번도 열어 본 적 없는 파일은 iCloud가 자리만 잡아 두어
    /// 목록에 안 잡힐 수 있다. 새 기기·재설치가 바로 그 경우라, 이름을
    /// 아는 둘(이 기기 것과 옛 공용 파일)은 목록에 없어도 끝에 붙여 둔다 —
    /// 내려받기는 저쪽에서 건다. 날짜를 모르니 끝에 놓이는데, 위의 게시판
    /// 규칙에서만 의미가 있는 차이라 그대로 둔다.
    private static func candidateFileURLs(in containerURL: URL) async -> [URL] {
        await Task.detached(priority: .utility) { () -> [URL] in
            let names = (try? FileManager.default.contentsOfDirectory(atPath: containerURL.path)) ?? []
            let found = names
                .filter { $0.hasPrefix(filenamePrefix) && $0.hasSuffix(".json") }
                .map { containerURL.appendingPathComponent($0) }
                .sorted { left, right in
                    let leftDate = modificationDate(of: left) ?? .distantPast
                    let rightDate = modificationDate(of: right) ?? .distantPast
                    return leftDate < rightDate
                }
            var candidates = found
            for known in [filename, legacyFilename] {
                let url = containerURL.appendingPathComponent(known)
                if !candidates.contains(url) { candidates.append(url) }
            }
            return candidates
        }.value
    }

    /// How long `loadRestorableBackups()` waits for iCloud to materialize a
    /// placeholder file before giving up — long enough for a snapshot to
    /// come down on a normal connection, short enough that a device with
    /// no usable iCloud never holds the launch screen up for it.
    private static let downloadWaitSeconds: TimeInterval = 10

    private static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}
