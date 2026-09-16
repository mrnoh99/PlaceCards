import Foundation
import UniformTypeIdentifiers

/// A spreadsheet of the library, for the thing the whole app is pointed at:
/// turning a pile of saved places into a trip plan someone can actually work
/// with. The JSON backup (`BackupService`) is for restoring this app and
/// nothing else — it embeds every photo as base64 and no spreadsheet will
/// ever open it. This is the other half, and it was missing.
enum CSVExport {
    /// One row per card, ordered board by board so a multi-board export
    /// reads as sections rather than a shuffle.
    static func csv(boards: [Board], placeCards: [PlaceCard]) -> Data {
        let boardNames = Dictionary(uniqueKeysWithValues: boards.map { ($0.id, $0.name) })
        let ordered = boards.flatMap { board in
            placeCards.filter { $0.boardId == board.id }
        }
        // A card whose board is gone would otherwise vanish from the export
        // without a word.
        let orphans = placeCards.filter { boardNames[$0.boardId] == nil }

        var text = row(headers)
        for card in ordered + orphans {
            text += row(fields(for: card, boardName: boardNames[card.boardId]))
        }

        // Excel reads a UTF-8 CSV as the system legacy encoding unless the
        // file opens with a byte-order mark, which turns every Korean name
        // in the sheet into mojibake. Numbers and Google Sheets don't need
        // it and don't mind it.
        return Data(utf8BOM) + Data(text.utf8)
    }

    static func filename(board: Board? = nil) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let stamp = formatter.string(from: Date())
        guard let board else { return "PinSpots-\(stamp).csv" }
        let safeName = board.name.replacingOccurrences(of: "/", with: "-")
        return "PinSpots-\(safeName)-\(stamp).csv"
    }

    // MARK: - Columns

    /// Computed, not stored, so the header row follows the app's current
    /// language the same way every other `.localized` call site does.
    private static var headers: [String] {
        [
            "게시판", "이름", "카테고리", "주소", "위도", "경도",
            "평점", "리뷰 수", "내 평점", "가격대",
            "전화번호", "웹사이트", "인스타그램",
            "영업시간", "라스트오더", "휴무일", "예약", "추천 메뉴",
            "입장료", "추천 소요 시간", "편의시설", "식이 옵션", "수상",
            "태그", "메모", "방문", "재방문 의향", "즐겨찾기", "방문 날짜", "추가한 날짜"
        ].map { $0.localized }
    }

    private static func fields(for card: PlaceCard, boardName: String?) -> [String] {
        [
            boardName ?? "",
            card.name,
            card.category ?? "",
            card.address,
            card.coordinates.map { String($0.latitude) } ?? "",
            card.coordinates.map { String($0.longitude) } ?? "",
            card.rating.map { String($0) } ?? "",
            card.reviewCount.map(String.init) ?? "",
            card.myRating.map { String($0) } ?? "",
            card.priceLevel?.symbol ?? "",
            card.phone ?? "",
            card.website ?? "",
            card.instagramURL ?? "",
            weekdayHours(card),
            card.closingTime ?? "",
            card.holidays ?? "",
            card.reservationInfo ?? "",
            card.recommendedMenu ?? "",
            card.admissionFee ?? "",
            card.suggestedDuration ?? "",
            card.amenities.joined(separator: ", "),
            card.dietaryOptions.joined(separator: ", "),
            card.awards.joined(separator: ", "),
            card.tags.joined(separator: ", "),
            card.memo ?? "",
            card.isVisited ? "O" : "",
            card.wouldRevisit.map { $0 ? "O" : "X" } ?? "",
            card.isFavorite ? "O" : "",
            card.visitDates.map(dayFormatter.string(from:)).joined(separator: ", "),
            dayFormatter.string(from: card.createdAt)
        ]
    }

    /// Opening hours collapse into one cell, in weekday order rather than
    /// the dictionary's own — the same ordering problem
    /// `WeekdayLabel.sortedByWeekday` exists to solve on screen.
    private static func weekdayHours(_ card: PlaceCard) -> String {
        guard let hours = card.hoursDetail, !hours.isEmpty else { return "" }
        return WeekdayLabel.sortedByWeekday(hours)
            .map { "\($0.key): \($0.value)" }
            .joined(separator: " / ")
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    // MARK: - CSV escaping

    private static let utf8BOM: [UInt8] = [0xEF, 0xBB, 0xBF]

    private static func row(_ fields: [String]) -> String {
        fields.map(escaped).joined(separator: ",") + "\r\n"
    }

    /// RFC 4180: a field containing a comma, a quote or a line break is
    /// wrapped in quotes, and its own quotes are doubled. A memo is free
    /// text and routinely contains all three, so skipping this would break
    /// the column alignment of every row after it.
    private static func escaped(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

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
