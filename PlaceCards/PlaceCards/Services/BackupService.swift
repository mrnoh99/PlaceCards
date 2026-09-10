import Foundation
import SwiftUI
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
/// metadata. PlaceCards does have photos (`PlaceCard.media`), but this
/// follows Peragra's scope exactly and does **not** bundle the actual
/// image files — only `MediaItem`'s filename references travel with the
/// backup (harmless on a same-device restore, where those files are
/// still on disk; on a different device or after a reinstall, a restored
/// card's photos just won't have a thumbnail, same as Peragra never
/// having had media in the first place). `SettingsView` says as much in
/// the footer text next to the buttons that use this.
enum BackupService {
    struct BackupData: Codable {
        var app = "placecards"
        var version = 1
        var exportedAt: Date = Date()
        var boards: [Board]
        var placeCards: [PlaceCard]
    }

    enum BackupError: LocalizedError {
        case invalidFile

        var errorDescription: String? {
            "PlaceCards 백업 파일이 아닙니다."
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

    static func filename(at date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return "placecards_\(formatter.string(from: date))"
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
    static func exportData(storageService: StorageService) throws -> Data {
        let backup = BackupData(boards: storageService.boards, placeCards: storageService.placeCards)
        return try makeEncoder().encode(backup)
    }

    /// One board and only its own place cards — used by "게시판
    /// 내보내기" (Export Board), shared via `ShareLink`.
    @MainActor
    static func exportBoard(_ board: Board, storageService: StorageService) throws -> Data {
        let backup = BackupData(boards: [board], placeCards: storageService.placeCards(inBoard: board.id))
        return try makeEncoder().encode(backup)
    }

    /// Replaces every board and place card with what's in `data` —
    /// mirrors Peragra's `restore(from:context:)`: a full wipe and
    /// rebuild, not a merge, keeping every id exactly as it was in the
    /// backup (so restoring the same file twice is idempotent). Version
    /// compatibility is checked the same minimal way Peragra does — only
    /// the `app` tag, not `version` itself, since `Board`/`PlaceCard`
    /// already tolerate an old file missing a newer optional field (every
    /// field added since this app's first release is `Optional`, for
    /// exactly this kind of forward/backward decode safety — see
    /// `PlaceCard.memo`'s own doc comment).
    @MainActor
    static func restore(from data: Data, storageService: StorageService) throws {
        let backup: BackupData
        do {
            backup = try makeDecoder().decode(BackupData.self, from: data)
        } catch {
            throw BackupError.invalidFile
        }
        guard backup.app == "placecards" else { throw BackupError.invalidFile }

        storageService.replaceAll(boards: backup.boards, placeCards: backup.placeCards)
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
