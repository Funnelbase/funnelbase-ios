import XCTest
@testable import TradeDemo

final class MoneyTests: XCTestCase {

    /// The point of pinning the locale rather than taking the device's.
    ///
    /// The Android test sets the JVM's default locale to `tr-TR` and asserts the output is
    /// unchanged. Swift has no settable process-wide default to swap — `Locale.current` is the
    /// user's settings and is read-only — so the same fact is asserted from both sides instead:
    /// the output is pinned, the locale it is pinned to is named, and a Turkish rendering of the
    /// same amount is shown to be a different string. Swapping `Money.locale` for
    /// `Locale.current` would therefore produce `$1.234,56` on a Turkish phone: a dollar amount
    /// with Turkish grouping, digits right and currency a lie.
    func testFormatsAsUnitedStatesEnglishWhateverTheDeviceIsSetTo() {
        XCTAssertEqual(Money.usd(1234.56), "$1,234.56")
        XCTAssertEqual(Money.locale.identifier, "en_US")

        let turkish = NumberFormatter()
        turkish.locale = Locale(identifier: "tr_TR")
        turkish.numberStyle = .currency
        turkish.currencyCode = "USD"
        turkish.minimumFractionDigits = 2
        turkish.maximumFractionDigits = 2
        XCTAssertNotEqual(
            turkish.string(from: 1234.56 as NSNumber),
            Money.usd(1234.56),
            "a device-locale formatter renders this differently, which is the regression"
        )
    }

    func testChangesAlwaysCarryASign() {
        XCTAssertEqual(Money.signedUsd(12.5), "+$12.50")
        XCTAssertEqual(Money.signedUsd(-12.5), "-$12.50")
        // Zero reads as up, matching ChangeText treating >= 0 as a rise.
        XCTAssertEqual(Money.signedUsd(0), "+$0.00")
        XCTAssertEqual(Money.signedPercent(1.2449), "+1.24%")
        XCTAssertEqual(Money.signedPercent(-1.2449), "-1.24%")
    }

    func testCompactNotationSwitchesAtEachMagnitude() {
        XCTAssertEqual(Money.compact(7_800_000), "7.8M")
        XCTAssertEqual(Money.compact(1_530_000_000), "1.53B")
        XCTAssertEqual(Money.compact(1_530_000_000_000), "1.53T")
        XCTAssertEqual(Money.compact(950), "950")
        XCTAssertEqual(Money.compact(1_500), "1.5K")
    }

    func testRelativeTimeCollapsesIntoTheRightUnit() {
        XCTAssertEqual(Money.relativeTime(11), "11m ago")
        XCTAssertEqual(Money.relativeTime(125), "2h ago")
        XCTAssertEqual(Money.relativeTime(60 * 24 * 3 + 5), "3d ago")
    }

    func testQuantitiesAreGroupedAndWhole() {
        XCTAssertEqual(Money.quantity(1250), "1,250")
        XCTAssertEqual(Money.quantity(5), "5")
    }
}
