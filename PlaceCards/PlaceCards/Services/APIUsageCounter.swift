import Foundation
import Combine

/// How many billable requests this device has sent, by kind, today and
/// this month.
///
/// Every external call this app makes is paid for by the user directly,
/// on their own Google/AI account (BYOK) — and until this existed the app
/// was the only party in that arrangement who could see how much it was
/// spending. The user found out from a bill. The protection the README
/// recommends is a per-API daily quota rather than a key restriction, so
/// "how close am I to the quota I set" is a question with a real answer
/// that only this side can give.
///
/// What this is not: a bill. It counts requests this app believes were
/// accepted, which is an approximation of what gets charged — a request
/// rejected before it reached the API isn't counted (see `record` call
/// sites, all after a successful response), and nothing here knows the
/// user's actual quota, tier or price. Settings says so rather than
/// implying a number it can't know.
@MainActor
final class APIUsageCounter: ObservableObject {
    static let shared = APIUsageCounter()

    /// One counted kind of request. Raw values are persisted, so they are
    /// never renamed — an unrecognized key just reads back as zero, which
    /// is a wrong count rather than a crash, but there is no reason to
    /// spend even that.
    enum Call: String, CaseIterable, Identifiable {
        /// `places:searchText` — both the place lookup and the address
        /// geocode go here, because Google bills and quotas them as the
        /// same `SearchTextRequest` method. One auto-verified row spends
        /// two of these (see `PlaceCardViewModel.autoVerifyUnambiguousRows`).
        case googleTextSearch
        /// `places/{id}` — `GetPlaceRequest`.
        case googlePlaceDetails
        /// `places/{id}/photos/…/media` — `GetPhotoMediaRequest`.
        case googlePhoto
        /// One AI provider request that came back without throwing
        /// (`AIProviderChain.run`). A fallback chain that tries two
        /// providers counts only the one that answered — a provider that
        /// failed outright is the case least likely to have been billed,
        /// and counting guesses would make every number here suspect.
        case aiRequest

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .googleTextSearch: return "Google 장소 검색".localized
            case .googlePlaceDetails: return "Google 장소 상세".localized
            case .googlePhoto: return "Google 사진".localized
            case .aiRequest: return "AI 요청".localized
            }
        }

        /// The per-day quota README tells the user to set for this method,
        /// shown only as the reference it is. Nothing here can read the
        /// quota actually configured in their Cloud console, so this is
        /// labelled as a recommendation in Settings and never as a limit
        /// this app is enforcing or measuring against. `nil` for AI
        /// requests, which have no equivalent recommended number.
        var recommendedDailyLimit: Int? {
            switch self {
            case .googleTextSearch: return 200
            case .googlePlaceDetails: return 50
            case .googlePhoto: return 200
            case .aiRequest: return nil
            }
        }
    }

    @Published private(set) var today: [Call: Int] = [:]
    @Published private(set) var month: [Call: Int] = [:]

    private static let dayStampKey = "apiUsageDayStamp"
    private static let monthStampKey = "apiUsageMonthStamp"

    private init() {
        rolloverIfNeeded()
        reload()
    }

    /// Records one accepted request, from wherever it happened.
    ///
    /// `nonisolated` with a hop inside rather than leaving the hop to each
    /// caller: `GooglePlacesService` is a plain class whose methods run on
    /// whatever executor the caller gave them, and threading a main-actor
    /// await through each of its four request paths would put a
    /// concurrency concern into code that is otherwise just HTTP. The hop
    /// also serializes the read-modify-write — two calls finishing at once
    /// on different threads would otherwise be free to lose one of the two
    /// increments.
    nonisolated static func record(_ call: Call) {
        Task { @MainActor in shared.increment(call) }
    }

    func clear() {
        let defaults = UserDefaults.standard
        for call in Call.allCases {
            defaults.removeObject(forKey: Self.dayKey(call))
            defaults.removeObject(forKey: Self.monthKey(call))
        }
        reload()
    }

    /// Whether anything has been counted at all — Settings hides the whole
    /// section until there is something to show, so a user who has never
    /// made a request doesn't get a screenful of zeroes.
    var hasAnyUsage: Bool {
        month.values.contains { $0 > 0 }
    }

    private func increment(_ call: Call) {
        rolloverIfNeeded()
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: Self.dayKey(call)) + 1, forKey: Self.dayKey(call))
        defaults.set(defaults.integer(forKey: Self.monthKey(call)) + 1, forKey: Self.monthKey(call))
        reload()
    }

    private func reload() {
        let defaults = UserDefaults.standard
        today = Dictionary(
            uniqueKeysWithValues: Call.allCases.map { ($0, defaults.integer(forKey: Self.dayKey($0))) }
        )
        month = Dictionary(
            uniqueKeysWithValues: Call.allCases.map { ($0, defaults.integer(forKey: Self.monthKey($0))) }
        )
    }

    /// Zeroes the day's counters when the day has changed, and the
    /// month's when the month has. Checked on every increment rather than
    /// scheduled, since an app that was backgrounded across midnight would
    /// never run a timer, and the only moment the number has to be right
    /// is when it's about to change or be read.
    private func rolloverIfNeeded() {
        let defaults = UserDefaults.standard
        let now = Date()

        let day = Self.dayStamp(now)
        if defaults.string(forKey: Self.dayStampKey) != day {
            for call in Call.allCases { defaults.removeObject(forKey: Self.dayKey(call)) }
            defaults.set(day, forKey: Self.dayStampKey)
        }

        let month = Self.monthStamp(now)
        if defaults.string(forKey: Self.monthStampKey) != month {
            for call in Call.allCases { defaults.removeObject(forKey: Self.monthKey(call)) }
            defaults.set(month, forKey: Self.monthStampKey)
        }
    }

    /// Local time, matching how a person reads "today" — deliberately not
    /// the UTC day Google's own quota resets on (Pacific, in fact), since
    /// this number exists to answer "have I been using this a lot" rather
    /// than to mirror a billing period exactly.
    private static func dayStamp(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

    private static func monthStamp(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)"
    }

    private static func dayKey(_ call: Call) -> String { "apiUsageDay." + call.rawValue }
    private static func monthKey(_ call: Call) -> String { "apiUsageMonth." + call.rawValue }
}
