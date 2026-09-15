import Foundation

/// One open→close span from Google Places' `regularOpeningHours.periods`.
///
/// Stored alongside — not instead of — `PlaceCard.hoursDetail`'s
/// human-readable lines. The text is what the user reads and can edit by
/// hand; this is the machine-readable form, and the only thing that can
/// answer "지금 영업 중인가?" without the user reading a seven-row table
/// and working it out themselves. Google already sends this in the same
/// `regularOpeningHours` object the app was requesting anyway — it was
/// simply being decoded away — so keeping it costs no extra API call.
struct OpeningPeriod: Codable, Equatable {
    /// Google's own numbering: 0 = Sunday.
    var openDay: Int
    /// Minutes from midnight.
    var openMinute: Int
    /// Both `nil` for a place Google reports as always open — it omits the
    /// closing point entirely for those.
    var closeDay: Int?
    var closeMinute: Int?
}

enum OpenState: Equatable {
    /// `closingSoon` once the place shuts within the hour — the difference
    /// between "go now" and "don't bother", which a bare "영업 중" hides.
    case open(closingSoon: Bool)
    case closed
}

extension Array where Element == OpeningPeriod {
    private static var minutesPerDay: Int { 24 * 60 }
    private static var minutesPerWeek: Int { 7 * 24 * 60 }
    /// How close to closing time still counts as `closingSoon`.
    private static var closingSoonMinutes: Int { 60 }

    /// Whether the place is open at `date`, or `nil` when there are no
    /// periods to judge from (so callers can show nothing rather than
    /// guessing).
    ///
    /// Works in minutes-from-Sunday-midnight so a span running past
    /// midnight — or past Sunday into Monday, which a late-night bar's
    /// hours routinely do — is a simple range check rather than a pile of
    /// special cases.
    func openState(at date: Date, calendar: Calendar = .current) -> OpenState? {
        guard !isEmpty else { return nil }

        let weekday = calendar.component(.weekday, from: date) - 1
        let minuteOfDay = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let nowInWeek = weekday * Self.minutesPerDay + minuteOfDay

        for period in self {
            guard let closeDay = period.closeDay, let closeMinute = period.closeMinute else {
                // No closing point at all — Google's way of saying 24 hours.
                return .open(closingSoon: false)
            }

            let start = period.openDay * Self.minutesPerDay + period.openMinute
            var end = closeDay * Self.minutesPerDay + closeMinute
            if end <= start { end += Self.minutesPerWeek }

            // The second candidate catches a span that started late last
            // week and runs into this one.
            for candidate in [nowInWeek, nowInWeek + Self.minutesPerWeek] where candidate >= start && candidate < end {
                return .open(closingSoon: end - candidate <= Self.closingSoonMinutes)
            }
        }
        return .closed
    }
}

/// Ordering for the free-text day labels stored as `PlaceCard.hoursDetail`'s
/// keys.
///
/// Those keys come from Google's `weekdayDescriptions`, which arrives as an
/// **ordered** array starting at Monday — but the app stores it in a
/// dictionary, throwing that order away, and every screen then re-sorted
/// the keys as plain strings. Alphabetically that is nonsense in either
/// language: 금·목·수·월·일·토·화 in Korean, Friday·Monday·Saturday·
/// Sunday·Thursday·Tuesday·Wednesday in English. This puts them back in
/// real weekday order.
enum WeekdayLabel {
    /// Monday-first, matching both Google's own listing order and the
    /// usual Korean calendar.
    private static let koreanPrefixes = ["월", "화", "수", "목", "금", "토", "일"]
    private static let englishPrefixes = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
    /// Anything unrecognized ("매일", "공휴일", a hand-typed label) sorts
    /// after the real weekdays rather than being forced into one.
    private static let unknownIndex = 7

    static func sortIndex(for label: String) -> Int {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        if let index = koreanPrefixes.firstIndex(where: { trimmed.hasPrefix($0) }) { return index }
        let lowercased = trimmed.lowercased()
        if let index = englishPrefixes.firstIndex(where: { lowercased.hasPrefix($0) }) { return index }
        return unknownIndex
    }

    /// The one ordering every screen showing a card's hours should use —
    /// day/hours pairs in weekday order, unrecognized labels last and
    /// alphabetical among themselves.
    static func sortedByWeekday(_ hours: [String: String]) -> [(key: String, value: String)] {
        hours.sorted { left, right in
            let leftIndex = sortIndex(for: left.key)
            let rightIndex = sortIndex(for: right.key)
            if leftIndex != rightIndex { return leftIndex < rightIndex }
            return left.key.localizedCaseInsensitiveCompare(right.key) == .orderedAscending
        }
    }
}
