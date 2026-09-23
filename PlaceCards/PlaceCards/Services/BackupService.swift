import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Whole-app JSON export/backup/restore, ported from Peragra's own
/// `BackupService` — same shape (a single `app`-tagged, versioned JSON
/// document; `.fileExporter`/`.fileImporter`/`ShareLink` for the actual
/// file movement; "restore" replaces everything, board export is
/// additive-only-by-sharing). Unlike Peragra, `Board`/`PlaceCard` are
/// already plain `Codable` structs (no SwiftData model layer to bridge),
/// so this embeds them directly instead of re-declaring every field in a
/// parallel `Backup*` struct.
///
/// Peragra has no photo/media model at all, so its backups are pure
/// metadata. PlaceCards does have photos (`PlaceCard.media`), and a
/// backup carries them too — otherwise a restore on a *different* device
/// or after a reinstall brings back metadata pointing at files that were
/// never there.
///
/// **백업 한 벌은 폴더 하나다** — `metadata.json`과 `photos/`
/// (`bundleMetadataName` 아래). 처음에는 사진을 base64로 그 JSON 안에
/// 박았는데(Foundation만으로 되는 가장 간단한 길이었고, 이 프로젝트는
/// zip 라이브러리를 안 쓴다), 그 방식은 **인코딩할 때 사진을 세 벌로
/// 메모리에 올려** 328장/400MB에서 앱을 `EXC_RESOURCE`로 죽였다. 지금은
/// `FileManager.copyItem`으로 한 장씩 옮기므로 바이트가 메모리를 거치지
/// 않는다.
///
/// 옛 형식은 **읽기만** 남아 있다(`mediaFiles`·`writeMediaFiles`). 이
/// 변경 전에 만든 백업이 사용자 폴더와 iCloud에 남아 있기 때문이다.
///
/// `SettingsView`의 버튼 옆 설명 문구는 이 주석과 발을 맞춰야 한다.
enum BackupService {
    struct BackupData: Codable {
        var app = "placecards"
        var version = 1
        var exportedAt: Date = Date()
        var boards: [Board]
        var placeCards: [PlaceCard]
        /// Every referenced photo's actual bytes, keyed by
        /// `MediaItem.localPath` (the filename `MediaStore` resolves).
        /// Added after this backup format's first release, so an older
        /// backup file simply decodes this as `nil` — its cards restore
        /// with no photos, exactly like this format always behaved before
        /// this field existed (every field added since first release is
        /// `Optional` for exactly this forward/backward decode safety —
        /// see `PlaceCard.memo`'s own doc comment).
        var mediaFiles: [String: Data]?
    }

    enum BackupError: LocalizedError {
        case invalidFile

        var errorDescription: String? {
            "PinSpots 백업 파일이 아닙니다.".localized
        }
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// The device this backup was written on, as a filesystem-safe tag.
    ///
    /// A backup folder usually collects files from more than one device —
    /// an iCloud Drive folder an iPhone and an iPad both write to — and
    /// until this existed every file was named alike, so which machine
    /// made which was unknowable from the listing.
    ///
    /// Prefers what the user typed in Settings (`BackupFolderSettings
    /// .deviceName`) and falls back to what iOS reports. The fallback is
    /// the weaker half on purpose: since iOS 16 `UIDevice.name` returns
    /// the device's *model* ("iPhone", "iPad"), not the name its owner
    /// gave it, unless the app carries the
    /// `com.apple.developer.device-information.user-assigned-device-name`
    /// entitlement — granted only on request, against a declared need
    /// this app doesn't have. So the fallback tells an iPhone from an
    /// iPad but never one iPhone from another, which is exactly the gap
    /// the Settings field fills.
    ///
    /// Case is preserved, unlike `boardFilename(for:)`'s lowercasing: a
    /// user who types "XX" as their tag means "XX", and this sits beside
    /// an uppercase `PS` prefix anyway. Non-alphanumerics become `_`;
    /// `CharacterSet.alphanumerics` is Unicode-wide, so a Korean tag
    /// survives rather than being stripped to nothing.
    @MainActor
    private static func deviceTag() -> String {
        let typed = BackupFolderSettings.shared.deviceName
        let source = typed.isEmpty ? UIDevice.current.name : typed
        let tag = source
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
        return tag.isEmpty ? "device" : tag
    }

    /// `PS_<device>_<yyMMdd>_<HHmm>` — e.g. `PS_XX_260918_0648`.
    ///
    /// `PS`, not `placecards`: the full name ate most of the width a
    /// folder listing gives a filename before the part that distinguishes
    /// one backup from another even began.
    ///
    /// Seconds are gone from the timestamp. Two backups inside the same
    /// minute now land on the same name and the second replaces the
    /// first, which is the right outcome — a minute apart they hold
    /// essentially the same library, so the alternative was two more
    /// digits on every filename forever to keep a duplicate nobody wants.
    ///
    /// The month and day stay zero-padded (`260918`, not `26918`). An
    /// unpadded month costs a character but breaks the listing: `26918`
    /// (September) sorts *after* `261018` (October), because the
    /// comparison is per-character and `9` > `1`, so a folder sorted by
    /// name stops being in date order the moment the year turns over
    /// into a two-digit month.
    ///
    /// `en_US_POSIX`, as a fixed format always needs: without it the
    /// formatter follows the user's own calendar preference, and `yy`
    /// under a non-Gregorian one (Japanese, Buddhist, …) writes a year
    /// that doesn't match the rest of the folder.
    @MainActor
    static func filename(at date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyMMdd_HHmm"
        return "PS_\(deviceTag())_\(formatter.string(from: date))"
    }

    /// Mirrors Peragra's `BackupService.boardFilename(for:)` — a
    /// filesystem-safe slug of the board's own name, so a shared board
    /// is identifiable at a glance instead of just a timestamp.
    ///
    /// **확장자를 붙이지 않는다.** 게시판 내보내기도 이제 파일 하나가 아니라
    /// 폴더 한 벌이다(`writeBundle`). `.json`이 붙어 있으면 폴더 이름이
    /// 파일인 척하게 된다.
    static func boardFilename(for board: Board, at date: Date = .now) -> String {
        let slug = board.name
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return "placecards_board_\(slug.isEmpty ? "board" : slug)_\(formatter.string(from: date))"
    }

    // 사진을 base64로 JSON 안에 인라인해 **통째로 인코딩하던** 쓰기 경로는
    // 지웠다(`exportData`·`exportBoard`·`encodeOffMainActor`·
    // `collectMediaFiles`). 그것이 사진을 세 벌로 메모리에 올려
    // `EXC_RESOURCE`로 앱을 죽였고, 쓰는 쪽은 전부 아래 폴더 형식으로
    // 옮겼다. **다시 만들지 말 것** — 남겨 두면 누군가 부르는 순간 같은
    // 크래시가 돌아온다.
    //
    // 읽는 쪽(`BackupData.mediaFiles`·`writeMediaFiles`)은 그대로 있다.
    // 이 변경 전에 만든 백업이 사용자 폴더와 iCloud에 남아 있고, 그것도
    // 계속 복원할 수 있어야 한다.

    // MARK: - 폴더 형식 (사진을 파일로 따로 둔다)

    /// 백업 폴더 안의 두 이름.
    ///
    /// 위의 `mediaFiles` 인라인 형식은 **사진 전체를 두 벌로 메모리에
    /// 올린다** — 원본 바이트를 담은 사전 하나, `JSONEncoder`가 만드는
    /// base64 문자열 하나, 그리고 직렬화된 출력 하나. 사진 400MB짜리
    /// 라이브러리에서 최고점이 2GB에 닿아 `EXC_RESOURCE`로 앱이 죽었다
    /// (328장/400MB에서 실제로 났다).
    ///
    /// 폴더 형식은 그 셋을 전부 없앤다. 메타데이터만 JSON이고 사진은
    /// `FileManager.copyItem`으로 **한 장씩 파일에서 파일로** 옮긴다 —
    /// 바이트가 메모리를 거치지 않으므로 라이브러리가 아무리 커도
    /// 최고점이 자라지 않는다.
    static let bundleMetadataName = "metadata.json"
    static let bundlePhotosDirectoryName = "photos"

    /// 이 위치가 폴더 형식 백업인가. 옛 단일 JSON과 가르는 데 쓴다 —
    /// 둘 다 계속 읽어야 한다(이 변경 전에 만든 백업이 남아 있다).
    static func isBundle(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: url.appendingPathComponent(bundleMetadataName).path, isDirectory: &isDirectory
        )
        return exists && !isDirectory.boolValue
    }

    /// 고른 것이 iCloud Drive에 있고 **아직 안 내려온** 것이면 내려받기를
    /// 걸고 기다린다.
    ///
    /// 파일 선택기는 **안 내려온 파일도 고르게 해 준다.** 목록에는 보이지만
    /// 이 기기에는 플레이스홀더만 있어서, 그대로 읽으면 조용히 실패한다 —
    /// 사용자 신고: "icloud 폴더에 download 안된 파일을 선택한 경우 진행이
    /// 안된다".
    ///
    /// 폴더 형식이면 `metadata.json`을 먼저 받아 읽고 **거기 적힌 이름으로**
    /// 사진을 받는다. 디렉터리 목록을 쓰지 않는 이유는 안 내려온 파일이
    /// 플레이스홀더 이름으로 나오고 그 이름 규칙을 되돌리는 것은 추측이기
    /// 때문이다(CLAUDE.md §4). `CloudBackupService`가 같은 이유로 같은
    /// 방식을 쓴다.
    ///
    /// iCloud에 있지 않은 파일에는 아무 일도 안 일어난다 —
    /// `startDownloadingUbiquitousItem`이 던지고 그대로 넘어간다.
    static func ensureDownloaded(at url: URL) async {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)

        guard isDirectory.boolValue else {
            await downloadIfNeeded([url], waitingUpTo: fileDownloadWaitSeconds)
            return
        }

        await downloadIfNeeded(
            [url.appendingPathComponent(bundleMetadataName)], waitingUpTo: fileDownloadWaitSeconds
        )
        guard let decoded = try? decodeBundle(at: url) else { return }
        let photosURL = url.appendingPathComponent(bundlePhotosDirectoryName)
        await downloadIfNeeded(
            referencedPhotoNames(in: decoded.placeCards).map { photosURL.appendingPathComponent($0) },
            waitingUpTo: photoDownloadWaitSeconds
        )
    }

    /// 아직 안 내려온 것들의 내려받기를 **전부 먼저 걸고, 기다리는 것은 한
    /// 번만** 한다. 파일마다 따로 기다리면 개수만큼 화면이 붙잡힌다.
    static func downloadIfNeeded(_ urls: [URL], waitingUpTo seconds: TimeInterval) async {
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

    /// 파일 하나(또는 메타데이터 하나)를 기다리는 시간.
    static let fileDownloadWaitSeconds: TimeInterval = 20

    /// 사진을 기다리는 시간. 위보다 훨씬 길다 — 수백 장이 올 수 있고,
    /// 부르는 쪽은 진행 표시를 띄워 둔다.
    static let photoDownloadWaitSeconds: TimeInterval = 60

    /// 폴더 하나로 백업한다 — `metadata.json` 하나와 `photos/` 아래 사진들.
    @MainActor
    static func writeBundle(to bundleURL: URL, storageService: StorageService) async throws {
        try await writeBundle(
            to: bundleURL, boards: storageService.boards, placeCards: storageService.placeCards
        )
    }

    /// 게시판 하나와 그 게시판의 카드만 폴더 한 벌로 — "게시판 내보내기"가
    /// 쓴다. 전체 백업과 같은 구조라 받는 쪽이 둘을 구별할 필요가 없다.
    @MainActor
    static func writeBundle(to bundleURL: URL, board: Board, storageService: StorageService) async throws {
        try await writeBundle(
            to: bundleURL, boards: [board], placeCards: storageService.placeCards(inBoard: board.id)
        )
    }

    /// 사진을 뺀 메타데이터만 JSON으로.
    ///
    /// "텍스트로 복사"가 쓴다. 예전에는 `exportBoard`의 결과를 그대로 넘겨
    /// **사진 전체를 base64로 클립보드에 올렸다** — 붙여 넣을 곳에서 쓸모가
    /// 없을뿐더러 사진이 쌓인 게시판에서는 그것만으로도 메모리가 터진다.
    @MainActor
    static func metadataText(board: Board, storageService: StorageService) async -> String? {
        let boards = [board]
        let placeCards = storageService.placeCards(inBoard: board.id)
        return await Task.detached(priority: .utility) { () -> String? in
            let metadata = BackupData(boards: boards, placeCards: placeCards, mediaFiles: nil)
            guard let data = try? makeEncoder().encode(metadata) else { return nil }
            return String(data: data, encoding: .utf8)
        }.value
    }

    /// 짓는 동안에는 **옆에 임시 폴더로** 짓고 마지막에 자리를 바꾼다.
    /// 도중에 멈춰도 이미 있던 백업이 반쯤 쓰인 것으로 바뀌지 않는다 —
    /// 단일 파일일 때 `.atomic`이 해 주던 일이다.
    private static func writeBundle(
        to bundleURL: URL, boards: [Board], placeCards: [PlaceCard]
    ) async throws {
        try await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            let stagingURL = bundleURL.deletingLastPathComponent()
                .appendingPathComponent(bundleURL.lastPathComponent + ".building")
            try? fileManager.removeItem(at: stagingURL)
            let photosURL = stagingURL.appendingPathComponent(bundlePhotosDirectoryName)
            try fileManager.createDirectory(at: photosURL, withIntermediateDirectories: true)

            // 메타데이터에는 `mediaFiles`를 싣지 않는다. 그 필드는 옵셔널이라
            // 안 실으면 `nil`로 디코딩되고, 사진은 옆의 `photos/`에 있다.
            let metadata = BackupData(boards: boards, placeCards: placeCards, mediaFiles: nil)
            let encoded = try makeEncoder().encode(metadata)
            try encoded.write(
                to: stagingURL.appendingPathComponent(bundleMetadataName), options: .atomic
            )

            for fileName in referencedPhotoNames(in: placeCards) {
                let source = MediaStore.fileURL(fileName: fileName)
                guard fileManager.fileExists(atPath: source.path) else { continue }
                try? fileManager.copyItem(at: source, to: photosURL.appendingPathComponent(fileName))
            }

            try? fileManager.removeItem(at: bundleURL)
            try fileManager.moveItem(at: stagingURL, to: bundleURL)
        }.value
    }

    /// 카드들이 가리키는 사진 이름, 중복 없이. `collectMediaFiles`와 같은
    /// 것을 고르되 **바이트는 읽지 않는다.**
    ///
    /// `CloudBackupService`도 쓴다 — 아직 안 내려온 사진의 내려받기를
    /// 걸려면 이름이 필요한데, 디렉터리 목록에는 플레이스홀더 이름으로
    /// 나오기 때문에 메타데이터 쪽에서 얻어야 한다.
    static func referencedPhotoNames(in placeCards: [PlaceCard]) -> [String] {
        var seen: Set<String> = []
        var names: [String] = []
        for card in placeCards {
            for item in card.media.allItems where seen.insert(item.localPath).inserted {
                names.append(item.localPath)
            }
        }
        return names
    }

    /// 옛 단일 파일을 **임시 폴더 형식으로 옮겨 놓고** 메타데이터만 돌려준다.
    ///
    /// 옛 형식은 사진이 base64로 JSON 안에 박혀 있어, 읽는 것만으로도
    /// 파일 바이트(base64라 원본의 4/3)와 디코딩된 사진 사전이 **동시에**
    /// 메모리에 있다. 그 자체는 피할 수 없다 — `JSONDecoder`는 통째로
    /// 준다. 피할 수 있는 것은 그 다음이다:
    ///
    /// - **메인 액터에서 하지 않는다.** 가져오기 화면이 이걸 그대로
    ///   `handleFilePicked` 안에서 했고, 사진이 쌓인 백업에서 앱이 죽었다.
    /// - **사진을 계속 들고 있지 않는다.** 디코딩하자마자 임시 폴더로
    ///   내려놓고 메타데이터만 남긴다. 예전에는 미리보기가 사진 전체를
    ///   쥔 채로 사용자가 "가져오기"를 누를 때까지 화면에 떠 있었다.
    ///
    /// 돌려준 폴더는 폴더 형식 백업과 똑같은 모양이라, 호출부는 그 뒤로
    /// 둘을 구별할 필요가 없다. 다 쓴 뒤 `discardStagedBundle(at:)`로
    /// 치운다.
    static func stageLegacyBackup(at url: URL) async throws -> (backup: BackupData, bundleURL: URL) {
        try await Task.detached(priority: .utility) { () -> (backup: BackupData, bundleURL: URL) in
            let decoded = try decode(Data(contentsOf: url))

            let stagingURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("PinSpotsImport-\(UUID().uuidString)")
            let photosURL = stagingURL.appendingPathComponent(bundlePhotosDirectoryName)
            try FileManager.default.createDirectory(at: photosURL, withIntermediateDirectories: true)
            for (fileName, data) in decoded.mediaFiles ?? [:] {
                try? data.write(to: photosURL.appendingPathComponent(fileName), options: .atomic)
            }

            // 사진을 떼어 낸 사본만 남긴다. 이게 화면이 들고 있을 값이다.
            var metadata = decoded
            metadata.mediaFiles = nil
            try makeEncoder().encode(metadata).write(
                to: stagingURL.appendingPathComponent(bundleMetadataName), options: .atomic
            )
            return (metadata, stagingURL)
        }.value
    }

    /// `stageLegacyBackup`이 만든 임시 폴더를 치운다. 안 치워도 iOS가
    /// 언젠가 임시 디렉터리를 비우지만, 사진 수백 장이 그때까지 남는다.
    static func discardStagedBundle(at bundleURL: URL) {
        try? FileManager.default.removeItem(at: bundleURL)
    }

    /// 폴더 백업의 **메타데이터만** 읽는다. 사진은 건드리지 않는다 —
    /// 복원할 후보를 훑을 때 기기 수만큼의 사진을 한꺼번에 들고 있던 것이
    /// `loadRestorableBackups`가 크래시하던 이유다.
    static func decodeBundle(at bundleURL: URL) throws -> BackupData {
        guard let data = try? Data(
            contentsOf: bundleURL.appendingPathComponent(bundleMetadataName)
        ) else { throw BackupError.invalidFile }
        return try decode(data)
    }

    /// 폴더 백업의 사진을 `MediaStore`로 **한 장씩** 옮긴다.
    /// `writeMediaFiles`가 인라인 형식에 하는 일과 같되 메모리를 안 쓴다.
    private static func writePhotos(fromBundleAt bundleURL: URL) {
        let fileManager = FileManager.default
        let photosURL = bundleURL.appendingPathComponent(bundlePhotosDirectoryName)
        let names = (try? fileManager.contentsOfDirectory(atPath: photosURL.path)) ?? []
        // 점으로 시작하는 이름은 건너뛴다. iCloud가 아직 안 내려온 파일을
        // `.<이름>.icloud` 플레이스홀더로 목록에 보여 주므로, 거르지 않으면
        // 그 껍데기가 사진인 양 `MediaStore`에 복사된다. `.DS_Store` 같은
        // 것도 같이 걸러진다. `MediaStore`가 짓는 이름은 `UUID().jpg`라
        // 점으로 시작하는 일이 없다.
        for name in names where !name.hasPrefix(".") {
            let destination = MediaStore.fileURL(fileName: name)
            try? fileManager.removeItem(at: destination)
            try? fileManager.copyItem(at: photosURL.appendingPathComponent(name), to: destination)
        }
    }

    /// 폴더 백업을 이 기기에 합친다. 규칙은 `restore(_:storageService:)`와
    /// 똑같고(없으면 추가, `updatedAt`이 더 나중이면 교체), 사진을 어디서
    /// 가져오는지만 다르다.
    @MainActor
    @discardableResult
    static func restore(
        bundleAt bundleURL: URL, storageService: StorageService
    ) async throws -> (boards: Int, added: Int, updated: Int) {
        let backup = try await Task.detached(priority: .utility) {
            try decodeBundle(at: bundleURL)
        }.value
        let added = storageService.merge(boards: backup.boards, placeCards: backup.placeCards)
        await Task.detached(priority: .utility) { writePhotos(fromBundleAt: bundleURL) }.value
        return added
    }

    /// Writes every embedded photo back to `MediaStore` under its original
    /// filename — a same-device restore just overwrites identical bytes
    /// (harmless), while a cross-device restore/import is exactly the case
    /// this exists for: without it, a restored/imported card's
    /// `MediaItem.localPath` would point at a filename nothing on the
    /// receiving device has ever written.
    private static func writeMediaFiles(_ mediaFiles: [String: Data]?) {
        guard let mediaFiles else { return }
        for (fileName, data) in mediaFiles {
            try? MediaStore.writeData(data, fileName: fileName)
        }
    }

    /// Decodes a `BackupData` payload without applying it anywhere — used
    /// on its own by `ImportBoardSheet` (to preview a board/place count
    /// before the user commits to importing it) and by
    /// `CloudBackupService.loadRestorableBackups()`, and internally by
    /// `restore(from:storageService:)`. Version compatibility is checked
    /// the same minimal way Peragra does — only the `app` tag, not
    /// `version` itself, since `Board`/`PlaceCard` already tolerate an
    /// old file missing a newer optional field (every field added since
    /// this app's first release is `Optional`, for exactly this kind of
    /// forward/backward decode safety — see `PlaceCard.memo`'s own doc
    /// comment).
    static func decode(_ data: Data) throws -> BackupData {
        let backup: BackupData
        do {
            backup = try makeDecoder().decode(BackupData.self, from: data)
        } catch {
            throw BackupError.invalidFile
        }
        guard backup.app == "placecards" else { throw BackupError.invalidFile }
        return backup
    }

    // 사진이 박힌 payload를 **통째로 받아** 복원하던 두 함수
    // (`restore(from:)`·`restore(_:)`)는 지웠다. 둘 다 디코딩된 사진 사전을
    // 손에 쥔 채 돌았고, 읽는 쪽에 남아 있던 마지막 메모리 구멍이었다.
    // 옛 단일 파일은 이제 `stageLegacyBackup`이 임시 폴더로 옮긴 뒤
    // `restore(bundleAt:)`이 한 장씩 처리한다.

    /// Adds a board (and its place cards) from a shared/exported file
    /// into the current data, without touching anything already there —
    /// mirrors Peragra's `importBoard(_:context:)`. Unlike `restore`,
    /// every id is regenerated fresh so it can never collide with (or
    /// silently overwrite) existing data, even importing the same file
    /// twice. Takes an already-`decode`d `BackupData` rather than raw
    /// `Data`, so the caller (`ImportBoardSheet`) can show a preview of
    /// what's about to be imported before committing to it.
    ///
    /// `photosFrom`이 주어지면 사진을 **그 폴더에서** 가져온다(폴더 형식).
    /// 옛 단일 파일은 사진이 `backup.mediaFiles`에 박혀 있으므로 nil이다.
    @MainActor
    @discardableResult
    static func importBoard(
        _ backup: BackupData, photosFrom bundleURL: URL? = nil, storageService: StorageService
    ) -> [Board] {
        if let bundleURL {
            writePhotos(fromBundleAt: bundleURL)
        } else {
            writeMediaFiles(backup.mediaFiles)
        }

        // 보드 id를 먼저 전부 새로 매긴 뒤, 카드는 그 다음에 한 번만
        // 돈다. 예전에는 보드마다 그 안의 카드를 돌며 새 id를 붙였는데,
        // 카드가 여러 보드에 들어갈 수 있게 된 지금 그렇게 하면 두 보드에
        // 든 카드가 서로 다른 id를 단 두 장으로 복제된다.
        var newBoardIDs: [String: String] = [:]
        var importedBoards: [Board] = []
        for board in backup.boards {
            var newBoard = board
            newBoard.id = UUID().uuidString
            newBoardIDs[board.id] = newBoard.id
            storageService.saveBoard(newBoard)
            importedBoards.append(newBoard)
        }

        for card in backup.placeCards {
            // 이 가져오기에 들어 있지 않은 보드는 버린다. 백업이 카드가
            // 속한 보드를 전부 담고 있다는 보장이 없다.
            let mapped = card.boardIDs.compactMap { newBoardIDs[$0] }
            guard !mapped.isEmpty else { continue }
            var newCard = card
            newCard.id = UUID().uuidString
            newCard.boardIDs = mapped
            // 바깥에서 받아 들여온 카드는 "가져오기"에도 들어간다. 파일로
            // 받은 게시판도, Google Takeout도(TakeoutImport가 만든
            // BackupData가 결국 여기로 온다) 같은 길이다.
            //
            // `restore`는 이 길을 타지 않는다. 그쪽은 남의 정보를 들여오는
            // 것이 아니라 제 백업을 되돌리는 것이라, 표시하면 쓰던 카드가
            // 전부 가져오기로 쏟아진다.
            newCard.isImported = true
            storageService.save(newCard)
        }
        return importedBoards
    }
}
