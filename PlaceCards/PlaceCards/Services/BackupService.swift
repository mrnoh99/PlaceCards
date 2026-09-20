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
/// metadata. PlaceCards does have photos (`PlaceCard.media`), and unlike
/// the first version of this file (ported from Peragra's own scope
/// exactly), this now bundles the actual image bytes too — `mediaFiles`
/// below, base64-encoded inline by `Data`'s own `Codable` conformance
/// (simplest option within Foundation alone; no zip/archive library this
/// project depends on) — so a restore/import on a *different* device or
/// after a reinstall actually brings photos back, not just metadata
/// pointing at files that were never there. `SettingsView`'s footer text
/// next to the buttons that use this was written for the old,
/// metadata-only behavior and needs to stay in sync with this comment.
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
    /// file is identifiable at a glance instead of just a timestamp.
    static func boardFilename(for board: Board, at date: Date = .now) -> String {
        let slug = board.name
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return "placecards_board_\(slug.isEmpty ? "board" : slug)_\(formatter.string(from: date)).json"
    }

    /// Every board and place card in one file — used by the Settings
    /// screen's full Backup ("전체 백업") and by the automatic
    /// folder backup (`AutoBackupService`).
    @MainActor
    static func exportData(storageService: StorageService) async throws -> Data {
        try await encodeOffMainActor(boards: storageService.boards, placeCards: storageService.placeCards)
    }

    /// One board and only its own place cards — used by "게시판
    /// 내보내기" (Export Board), shared via `ShareLink`.
    @MainActor
    static func exportBoard(_ board: Board, storageService: StorageService) async throws -> Data {
        try await encodeOffMainActor(boards: [board], placeCards: storageService.placeCards(inBoard: board.id))
    }

    /// Reads every photo's bytes and base64-encodes the whole document off
    /// the main actor. Only the snapshot of what to export is taken on the
    /// main actor (by the two callers above, since `StorageService` is
    /// `@MainActor`); the expensive part is not. This matters because
    /// `collectMediaFiles` pulls in every photo's actual bytes and
    /// `JSONEncoder` then base64-encodes all of them inline (see this
    /// type's own doc comment) — for a real library that's tens to
    /// hundreds of megabytes, and `CloudBackupService.backup` runs it on
    /// every foreground/background transition where anything changed. Done
    /// on the main actor, that froze the UI for the whole encode on the
    /// very transitions a user notices most (backgrounding right after
    /// editing a card), with iOS's own background-transition watchdog as
    /// the worst case.
    private static func encodeOffMainActor(boards: [Board], placeCards: [PlaceCard]) async throws -> Data {
        try await Task.detached(priority: .utility) {
            let backup = BackupData(
                boards: boards, placeCards: placeCards, mediaFiles: collectMediaFiles(for: placeCards)
            )
            return try makeEncoder().encode(backup)
        }.value
    }

    /// Every referenced photo's actual bytes for `placeCards`, keyed by
    /// filename — read straight from disk (`MediaStore.loadData`, no
    /// `UIImage` decode/re-encode round trip), so a backup carries
    /// pixel-identical copies of whatever's already stored rather than a
    /// lossy recompression. Deduplicated by filename, though two different
    /// cards sharing one file name shouldn't happen in the first place
    /// (`StorageService.delete` treats each card's media as its own).
    private static func collectMediaFiles(for placeCards: [PlaceCard]) -> [String: Data] {
        var files: [String: Data] = [:]
        for card in placeCards {
            for item in card.media.allItems where files[item.localPath] == nil {
                if let data = MediaStore.loadData(fileName: item.localPath) {
                    files[item.localPath] = data
                }
            }
        }
        return files
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
    /// `CloudBackupService.loadRestorableBackup()`, and internally by
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

    /// Brings in every board and place card in `data` that this device
    /// doesn't already have, and replaces the ones whose copy here is
    /// older than the backup's — see `StorageService.merge`.
    ///
    /// It used to replace the library wholesale (Peragra's own
    /// `restore(from:context:)` still does). Ids are kept exactly as the
    /// backup has them either way, which is what makes restoring the same
    /// file twice a no-op the second time — and, now, what identifies
    /// which cards are already here.
    ///
    /// Decoding and writing the photos back out both happen off the main
    /// actor, same reasoning as `encodeOffMainActor` — a backup carries
    /// every photo's bytes inline, so neither step is cheap.
    ///
    /// Returns how much was actually added and replaced, so the caller can
    /// say so rather than claiming a restore that changed nothing — and so
    /// a replacement is never silent.
    @MainActor
    @discardableResult
    static func restore(
        from data: Data, storageService: StorageService
    ) async throws -> (boards: Int, added: Int, updated: Int) {
        let backup = try await Task.detached(priority: .utility) { try decode(data) }.value
        return try await restore(backup, storageService: storageService)
    }

    /// The already-decoded form of `restore(from:storageService:)` — for a
    /// caller that had to decode the payload anyway (see
    /// `CloudBackupService.loadRestorableBackup()`), so the whole document
    /// isn't decoded a second time just to apply it.
    @MainActor
    @discardableResult
    static func restore(
        _ backup: BackupData, storageService: StorageService
    ) async throws -> (boards: Int, added: Int, updated: Int) {
        let added = storageService.merge(boards: backup.boards, placeCards: backup.placeCards)
        // Every photo in the backup, not just the added cards': a card
        // already on this device can still be missing its image file
        // (that is what a restore is *for*), so writing them all repairs
        // those too. It overwrites rather than skipping, which is safe
        // here — `MediaStore.saveImage` names files by UUID, so the same
        // name is the same photo.
        let mediaFiles = backup.mediaFiles
        await Task.detached(priority: .utility) { writeMediaFiles(mediaFiles) }.value
        return added
    }

    /// Adds a board (and its place cards) from a shared/exported file
    /// into the current data, without touching anything already there —
    /// mirrors Peragra's `importBoard(_:context:)`. Unlike `restore`,
    /// every id is regenerated fresh so it can never collide with (or
    /// silently overwrite) existing data, even importing the same file
    /// twice. Takes an already-`decode`d `BackupData` rather than raw
    /// `Data`, so the caller (`ImportBoardSheet`) can show a preview of
    /// what's about to be imported before committing to it.
    @MainActor
    @discardableResult
    static func importBoard(_ backup: BackupData, storageService: StorageService) -> [Board] {
        writeMediaFiles(backup.mediaFiles)

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

/// The `FileDocument` wrapper `.fileExporter` needs to save a backup —
/// mirrors Peragra's `BackupDocument` exactly (a plain `Data` passthrough,
/// since the payload is already-encoded JSON by the time this is built).
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
