import Foundation

/// Reads a Google Takeout export of someone's saved places and turns it
/// into a board, without calling Google once.
///
/// This is the bulk route the shared-list import (`GoogleMapsListParser`)
/// can't be. That one reads pins off a list's preview *image*, which caps
/// out around twenty places and yields a name and nothing else — every
/// row then has to be verified against Places to become a usable card. A
/// Takeout file has no cap and already carries the address and, in the
/// GeoJSON form, the coordinates. So a hundred saved places import for
/// **zero API calls**, and a card only spends anything if the user later
/// opens it and asks for a rating or a photo.
///
/// Two shapes come out of Takeout and both are handled:
///
/// - `Saved Places.json` — GeoJSON `FeatureCollection`. Name, address and
///   coordinates.
/// - One CSV per saved list (`Favorites.csv`, `Want to go.csv`, a custom
///   list's own name). Title, Note, URL, and sometimes an address column.
///   No coordinates at all.
enum TakeoutImport {
    /// `nil` when this isn't a Takeout file — the caller falls back to
    /// reporting it as an unrecognized file, same as before.
    ///
    /// `listName` is the file's own name where there is one: a Takeout CSV
    /// is named after the list it came from, which is exactly the board
    /// name the user expects.
    static func parse(_ data: Data, listName: String?) -> BackupService.BackupData? {
        let places = parseGeoJSON(data) ?? parseCSV(data)
        guard let places, !places.isEmpty else { return nil }
        return backup(named: listName ?? "Google Takeout", places: places)
    }

    struct Place {
        var name: String
        var address: String?
        var coordinates: Coordinates?
        var note: String?
        var mapURL: String?
    }

    // MARK: - Building the board

    private static func backup(named name: String, places: [Place]) -> BackupService.BackupData {
        let board = Board(name: name, subtitle: "Google Takeout", coverIcon: "map")
        let cards = places.map { place -> PlaceCard in
            let links = (place.mapURL?.isEmpty == false)
                ? [ExternalLink(platform: "Google Maps", url: place.mapURL!)]
                : []
            var card = PlaceCard(
                boardId: board.id,
                name: place.name,
                address: place.address ?? "",
                coordinates: place.coordinates,
                externalLinks: links
            )
            card.memo = place.note
            // Only what the file actually said. Nothing here is verified
            // against Places, so rating, category, hours and photo stay
            // empty until the user asks for them on a card they opened.
            card.sources = [
                SourceRecord(sourceType: .googleTakeout, dataProvided: ["name", "address"])
            ]
            return card
        }
        return BackupService.BackupData(boards: [board], placeCards: cards, mediaFiles: nil)
    }

    // MARK: - GeoJSON (Saved Places.json)

    private static func parseGeoJSON(_ data: Data) -> [Place]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = root["features"] as? [[String: Any]] else { return nil }

        let places = features.compactMap { feature -> Place? in
            guard let properties = feature["properties"] as? [String: Any],
                  let location = properties["location"] as? [String: Any] else { return nil }
            let name = (location["name"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { return nil }

            return Place(
                name: name.strippingInvisibleFormatCharacters(),
                address: (location["address"] as? String)?.strippingInvisibleFormatCharacters(),
                coordinates: coordinates(from: feature["geometry"]),
                // Takeout writes the user's own note here on a starred
                // place; absent for most.
                note: (properties["comment"] as? String) ?? (properties["note"] as? String),
                mapURL: properties["google_maps_url"] as? String
            )
        }
        return places.isEmpty ? nil : places
    }

    /// GeoJSON orders a Point as `[longitude, latitude]` — the reverse of
    /// how every other API in this app spells a coordinate, and an easy
    /// way to put every imported place in the wrong hemisphere.
    private static func coordinates(from geometry: Any?) -> Coordinates? {
        guard let geometry = geometry as? [String: Any],
              let pair = geometry["coordinates"] as? [Double], pair.count == 2 else { return nil }
        let coordinate = Coordinates(latitude: pair[1], longitude: pair[0])
        // Takeout is documented to write 0,0 for places it couldn't
        // resolve. Treated as no coordinate at all, exactly as
        // `PhotoMetadata.extractLocation` treats the same value in a
        // photo's GPS block — nobody saved a restaurant in the Gulf of
        // Guinea, and a card with a real address and no coordinate is far
        // more useful than one pinned to Null Island.
        guard coordinate.latitude != 0 || coordinate.longitude != 0 else { return nil }
        guard (-90...90).contains(coordinate.latitude),
              (-180...180).contains(coordinate.longitude) else { return nil }
        return coordinate
    }

    // MARK: - CSV (one per saved list)

    private static func parseCSV(_ data: Data) -> [Place]? {
        guard var text = String(data: data, encoding: .utf8) else { return nil }
        // Google writes these with a byte-order mark, which would
        // otherwise end up glued to the first header name and stop the
        // "title" lookup below from matching.
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        var rows = CSVReader.rows(in: text)
        guard let header = rows.first, header.count >= 2 else { return nil }
        rows.removeFirst()

        // Column order isn't guaranteed and Takeout's own set has changed
        // over time, so columns are found by name rather than position.
        // A file with no Title column isn't a Takeout list.
        //
        // **`Dictionary(uniqueKeysWithValues:)`를 쓰지 않는다.** 그것은 키가
        // 겹치면 그 자리에서 앱을 죽인다. 실제로 죽였다 — 빌드 50 크래시
        // 리포트의 스택이 `_NativeDictionary.merge(trappingOnDuplicates:)`
        // 였고, 사용자 신고 "가져오기하면 파일을 가져오면 crash"가 이것이다.
        //
        // 헤더는 **남이 만든 파일에서 온다.** 겹치지 않는다는 보장이 없다 —
        // 줄 끝에 쉼표가 하나 더 붙은 파일은 빈 이름이 둘이 되고, 같은 칸
        // 이름이 두 번 적힌 파일도 있다. 바깥에서 온 자료로 트랩을 거는 것은
        // 그 자체가 틀렸다. 못 읽는 파일은 "아니다"라고 말하고 돌아서야 하고,
        // 이 함수에는 그 길이 이미 있다(`return nil`).
        //
        // 먼저 나온 칸이 이긴다 — 뒤의 빈 칸이나 중복이 앞의 진짜 칸을
        // 밀어내면 안 된다. 이름이 빈 칸은 담지 않는다. 찾을 일이 없다.
        let index = Dictionary(
            header.enumerated()
                .map { ($1.lowercased().trimmingCharacters(in: .whitespaces), $0) }
                .filter { !$0.0.isEmpty },
            uniquingKeysWith: { first, _ in first }
        )
        guard let titleColumn = index["title"] ?? index["name"] else { return nil }

        func value(_ row: [String], _ keys: [String]) -> String? {
            for key in keys {
                guard let column = index[key], column < row.count else { continue }
                let text = row[column].trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return text }
            }
            return nil
        }

        let places = rows.compactMap { row -> Place? in
            guard titleColumn < row.count else { return nil }
            let name = row[titleColumn].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            return Place(
                name: name.strippingInvisibleFormatCharacters(),
                address: value(row, ["address"])?.strippingInvisibleFormatCharacters(),
                coordinates: nil,
                note: value(row, ["note", "comment"]),
                mapURL: value(row, ["url"])
            )
        }
        return places.isEmpty ? nil : places
    }
}

/// The reading half of RFC 4180, to `CSVExport`'s writing half. A Takeout
/// note is free text and arrives quoted with embedded commas, quotes and
/// line breaks, so splitting on commas would misread those rows.
enum CSVReader {
    static func rows(in text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character?

        func endField() {
            row.append(field)
            field = ""
        }
        func endRow() {
            endField()
            // A trailing newline shouldn't add a phantom row.
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
            row = []
        }

        while let character = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if character == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
                continue
            }
            switch character {
            case "\"": inQuotes = true
            case ",": endField()
            case "\r": break
            case "\n": endRow()
            default: field.append(character)
            }
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }
}
