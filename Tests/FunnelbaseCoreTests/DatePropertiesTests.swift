import XCTest
@testable import FunnelbaseCore

/// Dates in traits and properties (docs/event-contract.md, "Dates"): ISO-8601 text, a calendar day
/// as `YYYY-MM-DD` and an exact moment in UTC with `Z` — what the catalog's `date` type reads.
/// Mirrors Android's `DatePropertiesTest`, character for character.
final class DatePropertiesTests: XCTestCase {

    func testACalendarDayGoesOutAsYearMonthDay() {
        XCTAssertEqual(WireValue.of(AnalyticsDay(year: 2026, month: 11, day: 3)), .string("2026-11-03"))
    }

    func testADayFromADateIsTheDayInTheZoneAsked() {
        // 23:30 UTC on the 3rd is already the 4th in Istanbul (+03:00).
        let date = Date(timeIntervalSince1970: 1_793_748_600) // 2026-11-03T23:30:00Z
        XCTAssertEqual(AnalyticsDay(date, timeZone: TimeZone(identifier: "UTC")!).description, "2026-11-03")
        XCTAssertEqual(AnalyticsDay(date, timeZone: TimeZone(identifier: "Europe/Istanbul")!).description, "2026-11-04")
    }

    func testAMomentGoesOutInUtcWithZToTheMillisecond() {
        let date = Date(timeIntervalSince1970: 1_793_696_400.123_456) // 2026-11-03T09:00:00.123456Z
        XCTAssertEqual(WireValue.of(date), .string("2026-11-03T09:00:00.123Z"))
    }

    func testAWholeSecondMomentHasNoFraction() {
        let date = Date(timeIntervalSince1970: 1_793_696_400) // 2026-11-03T09:00:00Z
        XCTAssertEqual(WireValue.of(date), .string("2026-11-03T09:00:00Z"))
    }

    func testOtherTypesKeepTheirEncoding() {
        XCTAssertEqual(WireValue.of("x"), .string("x"))
        XCTAssertEqual(WireValue.of(42), .integer(42))
        XCTAssertEqual(WireValue.of(true), .bool(true))
        XCTAssertNil(WireValue.of(nil))
    }
}
