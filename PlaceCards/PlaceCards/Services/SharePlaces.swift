import Foundation

/// A lightweight, privacy-scrubbed place-sharing format — separate from
/// `BackupService`'s own full-fidelity schema — ported from Peragra's
/// `SharePlaces`. Deliberately excludes id, board, coordinates, visited/
/// favorite status, tags, and media: none of those are meaningful (or,
/// for visited/favorite, private) outside the sender's own board — this
/// is for handing a place or two to someone else, not moving/restoring a
/// board (that's what "게시판 내보내기"/`BackupService.exportBoard`, and
/// its counterpart `importBoard`, are for). Used by `BoardDetailView`'s
/// "내보내기" toolbar menu (Copy as Text / Share as File).
enum SharePlaces {
    struct SharedPlace: Codable {
        let name: String
        let category: String
        let address: String
        let phone: String?
        let notes: String
        let linkURL: String?

        enum CodingKeys: String, CodingKey {
            case name, category, address, phone, notes
            case linkURL = "linkUrl"
        }
    }

    struct SharedPlacesPayload: Codable {
        var app = "placecards"
        var kind = "places"
        var version = 1
        var places: [SharedPlace]
    }

    static func buildPayload(from cards: [PlaceCard]) -> SharedPlacesPayload {
        SharedPlacesPayload(
            places: cards.map { card in
                SharedPlace(
                    name: card.name,
                    category: card.category ?? "",
                    address: card.address,
                    phone: card.phone,
                    notes: card.memo ?? "",
                    linkURL: card.website
                )
            }
        )
    }

    /// Compact (not pretty-printed) — used for the `ShareLink` file, kept
    /// small since it's just being handed off, not read by a person.
    static func encode(_ payload: SharedPlacesPayload) throws -> Data {
        try JSONEncoder().encode(payload)
    }

    /// Pretty-printed and sorted — used for "텍스트로 복사", where a
    /// person may actually look at what got copied.
    static func toText(_ payload: SharedPlacesPayload) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func filename(at date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return "placecards_places_\(formatter.string(from: date)).json"
    }

    /// Writes a compact-encoded payload to a temp file for `ShareLink`,
    /// mirroring Peragra's `writeTempFile`.
    static func writeTempFile(_ payload: SharedPlacesPayload) -> URL? {
        guard let data = try? encode(payload) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename())
        guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return url
    }
}
