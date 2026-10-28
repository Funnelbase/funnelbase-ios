import Foundation

/// A calendar day with no time and no zone — a plan's renewal day, a birthday — read in whichever
/// zone asks. Sent as `YYYY-MM-DD`, what a property or trait declared `date` in the catalog accepts
/// (docs/event-contract.md, "Dates"). Android's mirror is `java.time.LocalDate`.
///
/// A `Date` is the other kind of date: an exact moment, sent in UTC with `Z`. Use this type when
/// the value is a day, so it does not shift by the device's offset on the way.
public struct AnalyticsDay: Hashable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// The day as given. Nothing is normalised: `AnalyticsDay(year: 2026, month: 2, day: 30)` is
    /// sent as written and refused by ingestion, the same as a wrong type would be.
    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The day `date` falls on in `timeZone` — the device's own by default, which is what "today"
    /// or "thirty days from now" means to the person holding it.
    public init(_ date: Date, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year!, month: parts.month!, day: parts.day!)
    }

    /// `YYYY-MM-DD`.
    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}

extension WireJson {
    /// A moment as a date property carries it: ISO 8601 in UTC with `Z`, to the millisecond, with
    /// no fraction when there is none — character for character what Android's
    /// `Instant.truncatedTo(MILLIS).toString()` writes, so the two SDKs send the same text.
    public static func moment(_ date: Date) -> String {
        let millis = (date.timeIntervalSince1970 * 1000).rounded(.down)
        let whole = millis.truncatingRemainder(dividingBy: 1000) == 0
        // A tenth of a microsecond in: `millis / 1000` is not exact in binary, and the formatter
        // truncates, so .123 could otherwise print as .122.
        let instant = Date(timeIntervalSince1970: millis / 1000 + 0.000_000_1)
        return (whole ? wholeSeconds : timestampFormatter).string(from: instant)
    }

    private static let wholeSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}
