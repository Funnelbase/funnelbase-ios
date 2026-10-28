import Foundation

/// Every number the user sees passes through here.
///
/// Fixed to `en_US`/USD rather than the device locale: the instruments are S&P 500 constituents
/// priced in dollars, and formatting them with the phone's locale would render a US dollar
/// amount with European grouping — the digits would be right and the currency would be a lie.
///
/// A `NumberFormatter` is not cheap to build, but it is also not safe to share across threads,
/// and at the rate a list row formats a price the cost does not show. Per call it is.
enum Money {

    /// The pinned locale. Naming it rather than inlining it is what makes "the device locale is
    /// not consulted" a thing a reader can check in one place.
    static let locale = Locale(identifier: "en_US")

    /// `$1,234.56`.
    static func usd(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSNumber) ?? ""
    }

    /// `+$1,234.56` / `-$1,234.56` — always signed, because a change without a sign is ambiguous.
    static func signedUsd(_ value: Double) -> String {
        (value >= 0 ? "+" : "-") + usd(abs(value))
    }

    /// `+1.24%` / `-1.24%`.
    static func signedPercent(_ value: Double) -> String {
        String(format: "%+.2f%%", locale: locale, value)
    }

    /// `1,250` — quantities are whole shares, so no decimals.
    static func quantity(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: value as NSNumber) ?? ""
    }

    /// `12.4M`, `1.02B` — full digits would dominate a row that is mostly prices.
    static func compact(_ value: Double) -> String {
        let magnitude = abs(value)
        if magnitude >= 1_000_000_000_000 {
            return String(format: "%.2fT", locale: locale, value / 1_000_000_000_000)
        }
        if magnitude >= 1_000_000_000 {
            return String(format: "%.2fB", locale: locale, value / 1_000_000_000)
        }
        if magnitude >= 1_000_000 {
            return String(format: "%.1fM", locale: locale, value / 1_000_000)
        }
        if magnitude >= 1_000 {
            return String(format: "%.1fK", locale: locale, value / 1_000)
        }
        return String(format: "%.0f", locale: locale, value)
    }

    static func compactUsd(_ value: Double) -> String {
        "$" + compact(value)
    }

    /// `3m ago`, `4h ago`, `2d ago`.
    static func relativeTime(_ minutesAgo: Int) -> String {
        if minutesAgo < 60 { return "\(minutesAgo)m ago" }
        if minutesAgo < 60 * 24 { return "\(minutesAgo / 60)h ago" }
        return "\(minutesAgo / (60 * 24))d ago"
    }
}
