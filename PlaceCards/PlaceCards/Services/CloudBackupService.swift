import Foundation

/// A silent iCloud-container JSON snapshot, independent of the user-facing
/// Backup/Restore and folder-schedule features — ported from Peragra's own
/// `CloudBackupService`. Not triggered by any button; `MainTabView` calls
/// it on every foreground/background transition, and calls
/// `restoreAll` once at cold launch (only when local storage is
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
    /// (`restoreAll`). 카드마다 `updatedAt`으로 최신이
    /// 이기므로(`StorageService.merge`) 합치는 것이 안전하다.
    /// **이제 파일이 아니라 폴더다**(`BackupService`의 폴더 형식 —
    /// `metadata.json` 하나와 `photos/`). 사진을 base64로 인라인하던 옛
    /// 단일 파일은 인코딩할 때 사진 전체를 두 벌로 메모리에 올려,
    /// 라이브러리가 커지자 앱이 `EXC_RESOURCE`로 죽었다. 옛 파일은 읽을
    /// 때 아직 본다(`legacyDeviceFilename`).
    private static var bundleName: String { "placecards_auto_backup_\(deviceID)" }

    /// 이 기기가 폴더 형식 이전에 쓰던 단일 파일. 지울 때와 읽을 때만 쓴다.
    private static var legacyDeviceFilename: String { "placecards_auto_backup_\(deviceID).json" }

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
        // 셋이다 — 이 기기의 폴더, 이 기기가 폴더 형식 이전에 쓰던 파일,
        // 그리고 기기를 나누기 전의 공용 파일. 하나라도 남기면 "끄기"가
        // 절반만 된다.
        let ownURLs = [bundleName, legacyDeviceFilename, legacyFilename]
            .map { containerURL.appendingPathComponent($0) }
        await Task.detached(priority: .utility) {
            for url in ownURLs {
                try? FileManager.default.removeItem(at: url)
            }
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
    /// paying for a full re-export — `BackupService.writeBundle` copies
    /// every photo the cards reference into the backup folder, so where
    /// this used to be a small, harmless JSON re-write on every single
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
        await Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
        }.value
        do {
            try await BackupService.writeBundle(
                to: containerURL.appendingPathComponent(bundleName), storageService: storageService
            )
        } catch {
            return
        }
        lastBackedUpFingerprint = currentFingerprint
    }

    /// 있는 백업을 **오래된 것부터 한 벌씩** 이 기기에 합친다. 하나라도
    /// 실제로 복원했으면 `true`.
    ///
    /// 예전에는 `loadRestorableBackups()`가 후보를 **전부 디코드해**
    /// `[BackupData]`로 돌려줬다. 사진이 인라인이던 형식에서 그것은 기기
    /// 수만큼의 사진 전체가 한꺼번에 메모리에 있다는 뜻이라, 쓰는 쪽과
    /// 똑같은 이유로 터질 자리였다. 이제 위치만 받아 한 벌씩 처리하고,
    /// 합치는 일도 여기서 한다 — 호출부(`MainTabView`)가 iCloud의 사정을
    /// 알 필요가 없다.
    @MainActor
    static func restoreAll(into storageService: StorageService) async -> Bool {
        guard isEnabled else { return false }
        guard let containerURL = await resolveContainerDocumentsURL() else { return false }
        let candidates = await candidateURLs(in: containerURL)
        guard !candidates.isEmpty else { return false }

        var restoredAny = false
        for url in candidates {
            // 이름으로 가른다. 폴더 형식에는 확장자가 없고, 옛 형식은
            // `.json`이다. 아직 안 내려온 것은 어느 쪽도 디스크에 없으므로
            // 내용을 봐서는 가릴 수 없다.
            if url.pathExtension == "json" {
                if await restoreLegacyFile(at: url, into: storageService) { restoredAny = true }
            } else {
                if await restoreBundle(at: url, into: storageService) { restoredAny = true }
            }
        }
        return restoredAny
    }

    /// 폴더 형식 한 벌. `metadata.json`을 먼저 내려받아 읽고, **거기 적힌
    /// 사진 이름으로** 사진을 내려받는다.
    ///
    /// 디렉터리 목록이 아니라 메타데이터에서 이름을 얻는 것이 중요하다.
    /// 아직 안 내려온 파일은 목록에 플레이스홀더 이름으로 나오는데, 그
    /// 이름 규칙을 추측해 되돌리는 것은 이 저장소가 하지 않는 일이다
    /// (CLAUDE.md §4). 메타데이터에 적힌 `localPath`가 곧 진짜 이름이라
    /// 그걸로 URL을 지으면 추측이 없다.
    @MainActor
    private static func restoreBundle(at bundleURL: URL, into storageService: StorageService) async -> Bool {
        let metadataURL = bundleURL.appendingPathComponent(BackupService.bundleMetadataName)
        await downloadIfNeeded([metadataURL], waitingUpTo: downloadWaitSeconds)

        let photoNames = await Task.detached(priority: .utility) { () -> [String]? in
            guard let decoded = try? BackupService.decodeBundle(at: bundleURL),
                  !decoded.boards.isEmpty else { return nil }
            return BackupService.referencedPhotoNames(in: decoded.placeCards)
        }.value
        guard let photoNames else { return false }

        let photosURL = bundleURL.appendingPathComponent(BackupService.bundlePhotosDirectoryName)
        await downloadIfNeeded(
            photoNames.map { photosURL.appendingPathComponent($0) },
            waitingUpTo: photoDownloadWaitSeconds
        )

        // 못 내려온 사진은 그냥 빠진다 — `BackupService.writePhotos`가
        // 디스크에 실제로 있는 것만 옮긴다. 카드는 전부 돌아오고 사진만
        // 일부 비는 편이, 기다리다 못해 아무것도 못 돌리는 것보다 낫다.
        guard (try? await BackupService.restore(bundleAt: bundleURL, storageService: storageService)) != nil
        else { return false }
        return true
    }

    /// 폴더 형식 이전에 만들어진 단일 JSON. 사진이 base64로 박혀 있어
    /// 읽는 것만으로도 무겁지만, **한 번에 한 벌씩만** 든다.
    @MainActor
    private static func restoreLegacyFile(at url: URL, into storageService: StorageService) async -> Bool {
        await downloadIfNeeded([url], waitingUpTo: downloadWaitSeconds)
        // 임시 폴더로 옮겨 놓고 폴더 쪽 길을 탄다. 디코딩한 사진 사전을
        // 들고 있는 시간이 그만큼 짧아진다 — 여기까지 오는 것은 콜드
        // 런치이고, 그때 수백 MB를 쥐고 있을 이유가 없다.
        guard let staged = try? await BackupService.stageLegacyBackup(at: url),
              !staged.backup.boards.isEmpty else { return false }
        defer { BackupService.discardStagedBundle(at: staged.bundleURL) }
        guard (try? await BackupService.restore(
            bundleAt: staged.bundleURL, storageService: storageService
        )) != nil else { return false }
        return true
    }

    /// 아직 안 내려온 것들의 내려받기를 **전부 먼저 걸고, 기다리는 것은 한
    /// 번만** 한다. 파일마다 따로 기다리면 개수만큼 시작 화면이 붙잡힌다.
    private static func downloadIfNeeded(_ urls: [URL], waitingUpTo seconds: TimeInterval) async {
        await Task.detached(priority: .utility) {
            let missing = urls.filter { !FileManager.default.fileExists(atPath: $0.path) }
            guard !missing.isEmpty else { return }
            for url in missing {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            }
            for _ in 0..<Int(seconds * 10) {
                if missing.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }.value
    }

    /// 컨테이너 안의 백업들, **오래된 것부터.**
    ///
    /// 카드는 `updatedAt`으로 최신이 이기므로 순서를 안 타지만, 게시판에는
    /// `updatedAt`이 없어 같은 id가 겹치면 나중에 넘긴 쪽이 남는다.
    ///
    /// 이 기기가 한 번도 열어 본 적 없는 것은 iCloud가 자리만 잡아 두어
    /// 목록에 안 잡힐 수 있다. 새 기기·재설치가 바로 그 경우라, 이름을
    /// 아는 셋(이 기기의 폴더, 이 기기의 옛 파일, 기기를 나누기 전의 공용
    /// 파일)은 목록에 없어도 끝에 붙여 둔다.
    private static func candidateURLs(in containerURL: URL) async -> [URL] {
        await Task.detached(priority: .utility) { () -> [URL] in
            let names = (try? FileManager.default.contentsOfDirectory(atPath: containerURL.path)) ?? []
            let found = names
                // 짓는 도중의 임시 폴더는 건너뛴다 — 반만 쓰인 것을 복원에
                // 쓰면 안 된다(`BackupService.writeBundle`이 `.building`으로
                // 짓고 마지막에 자리를 바꾼다).
                .filter { $0.hasPrefix(filenamePrefix) && !$0.hasSuffix(".building") }
                .map { containerURL.appendingPathComponent($0) }
                .sorted { left, right in
                    let leftDate = modificationDate(of: left) ?? .distantPast
                    let rightDate = modificationDate(of: right) ?? .distantPast
                    return leftDate < rightDate
                }
            var candidates = found
            for known in [bundleName, legacyDeviceFilename, legacyFilename] {
                let url = containerURL.appendingPathComponent(known)
                if !candidates.contains(url) { candidates.append(url) }
            }
            return candidates
        }.value
    }

    /// 사진을 기다리는 시간. `downloadWaitSeconds`보다 훨씬 길다 — 여기까지
    /// 오는 것은 **로컬이 비어 있는 첫 실행**뿐이고(`MainTabView`), 화면에
    /// 진행 표시가 떠 있으며, 사진 수백 장이 오는 데는 그만큼 걸린다.
    /// 다 오지 않아도 온 만큼은 복원된다.
    private static let photoDownloadWaitSeconds: TimeInterval = 60

    /// How long a metadata/legacy file download waits for iCloud to materialize a
    /// placeholder file before giving up — long enough for a snapshot to
    /// come down on a normal connection, short enough that a device with
    /// no usable iCloud never holds the launch screen up for it.
    private static let downloadWaitSeconds: TimeInterval = 10

    private static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}
