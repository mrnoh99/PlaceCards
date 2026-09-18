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

    /// The device this backup was written on, as a filesystem-safe slug.
    ///
    /// A backup folder usually collects files from more than one device —
    /// an iCloud Drive folder an iPhone and an iPad both write to — and
    /// until now every one of them was named alike, so which machine made
    /// which file was unknowable from the listing.
    ///
    /// **What this actually yields:** since iOS 16 `UIDevice.name` returns
    /// the device's *model* name ("iPhone", "iPad"), not the name its
    /// owner gave it in Settings, unless the app carries the
    /// `com.apple.developer.device-information.user-assigned-device-name`
    /// entitlement — which Apple grants only on request, against a
    /// declared need this app doesn't have. So this tells an iPhone from
    /// an iPad, which is the case worth telling apart, but not one iPhone
    /// from another iPhone.
    ///
    /// Slugged the same way `boardFilename(for:)` slugs a board name.
    /// `CharacterSet.alphanumerics` is Unicode-wide, so a Korean device
    /// name survives it rather than being stripped to nothing.
    @MainActor
    private static func deviceSlug() -> String {
        let slug = UIDevice.current.name
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
        return slug.isEmpty ? "device" : slug
    }

    /// `placecards_<device>_<yyMMdd_HHmm>` — which machine wrote it and
    /// when, both short enough to take in at a glance in a folder listing.
    ///
    /// Seconds are deliberately gone from the timestamp: two backups
    /// inside the same minute now land on the same name, and the second
    /// replaces the first. That is the right outcome — a minute apart
    /// they hold essentially the same library, so the alternative was two
    /// extra digits on every filename forever to preserve a duplicate
    /// nobody wants.
    ///
    /// `en_US_POSIX`, as a fixed format always needs: without it the
    /// formatter follows the user's own calendar preference, and `yy`
    /// under a non-Gregorian one (Japanese, Buddhist, …) writes a year
    /// that doesn't match the rest of the folder — the exact trap a
    /// two-digit year makes easiest to fall into.
    @MainActor
    static func filename(at date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyMMdd_HHmm"
        return "placecards_\(deviceSlug())_\(formatter.string(from: date))"
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

    /// Replaces every board and place card with what's in `data` —
    /// mirrors Peragra's `restore(from:context:)`: a full wipe and
    /// rebuild, not a merge, keeping every id exactly as it was in the
    /// backup (so restoring the same file twice is idempotent). Decoding
    /// and writing the photos back out both happen off the main actor,
    /// same reasoning as `encodeOffMainActor` — a backup carries every
    /// photo's bytes inline, so neither step is cheap.
    @MainActor
    static func restore(from data: Data, storageService: StorageService) async throws {
        let backup = try await Task.detached(priority: .utility) { try decode(data) }.value
        try await restore(backup, storageService: storageService)
    }

    /// The already-decoded form of `restore(from:storageService:)` — for a
    /// caller that had to decode the payload anyway (see
    /// `CloudBackupService.loadRestorableBackup()`), so the whole document
    /// isn't decoded a second time just to apply it.
    @MainActor
    static func restore(_ backup: BackupData, storageService: StorageService) async throws {
        storageService.replaceAll(boards: backup.boards, placeCards: backup.placeCards)
        let mediaFiles = backup.mediaFiles
        await Task.detached(priority: .utility) { writeMediaFiles(mediaFiles) }.value
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
        var importedBoards: [Board] = []
        for board in backup.boards {
            var newBoard = board
            newBoard.id = UUID().uuidString
            let oldBoardID = board.id
            for card in backup.placeCards where card.boardId == oldBoardID {
                var newCard = card
                newCard.id = UUID().uuidString
                newCard.boardId = newBoard.id
                storageService.save(newCard)
            }
            storageService.saveBoard(newBoard)
            importedBoards.append(newBoard)
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
