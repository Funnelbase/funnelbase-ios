import XCTest
@testable import TradeDemo

/// Invariants of the generated data.
///
/// The prices are random by design, so these assert the *shape* rather than any value — which is
/// exactly what caught the bug the Android versions of these tests were written after: an
/// `abs()` in the rounding helper meant to guard prices also stripped the sign off every change,
/// and the entire market rendered green. A hundred launches would not have looked wrong enough
/// to notice.
final class MarketDataTests: XCTestCase {

    private func generate(_ seed: UInt64) -> MarketData {
        MarketData.generate(SeededRandom(seed: seed))
    }

    func testFiftyInstrumentsAllDistinct() {
        let instruments = generate(1).instruments
        XCTAssertEqual(instruments.count, 50)
        XCTAssertEqual(Set(instruments.map(\.symbol)).count, 50)
    }

    func testChangesGoBothWays() {
        // Across 50 instruments a fair coin gives all-one-direction odds of about 1 in 5.6e14.
        // If this fails, the sign is being lost somewhere, not drawn unluckily.
        let changes = generate(7).instruments.map(\.changePercent)
        XCTAssertTrue(changes.contains { $0 < 0 }, "no instrument fell — is the sign being stripped?")
        XCTAssertTrue(changes.contains { $0 > 0 }, "no instrument rose")
    }

    func testTheDaysRangeContainsTheDay() {
        for instrument in generate(3).instruments {
            XCTAssertTrue(
                instrument.dayLow <= instrument.price && instrument.price <= instrument.dayHigh,
                "\(instrument.symbol): price outside range"
            )
            XCTAssertTrue(
                instrument.dayLow <= instrument.open && instrument.open <= instrument.dayHigh,
                "\(instrument.symbol): open outside range"
            )
            XCTAssertTrue(
                instrument.dayLow <= instrument.previousClose && instrument.previousClose <= instrument.dayHigh,
                "\(instrument.symbol): previous close outside range"
            )
        }
    }

    func testChangePercentAgreesWithPreviousClose() {
        for instrument in generate(5).instruments {
            let implied = (instrument.price - instrument.previousClose) / instrument.previousClose * 100
            XCTAssertTrue(
                abs(implied - instrument.changePercent) < 0.01,
                "\(instrument.symbol): \(instrument.changePercent)% stated, \(implied)% implied"
            )
        }
    }

    func testOrderCostIsQuantityTimesPrice() {
        for order in generate(9).orders {
            XCTAssertEqual(Double(order.quantity) * order.price, order.cost, accuracy: 1e-9)
        }
    }

    func testEveryOrderStatusIsRepresentedSoNoChipIsEverEmpty() {
        let statuses = Set(generate(11).orders.map(\.status))
        XCTAssertEqual(statuses, Set(OrderStatus.allCases))
    }

    func testPortfolioTotalIsInvestedPlusCashAndDayChangeIsSummedFromHoldings() {
        let portfolio = generate(13).portfolio
        XCTAssertEqual(portfolio.investedValue + portfolio.cashUsd, portfolio.totalValue, accuracy: 1e-9)
        let summed = portfolio.holdings.reduce(0.0) { $0 + Double($1.quantity) * $1.instrument.changeAbsolute }
        XCTAssertEqual(summed, portfolio.dayChange, accuracy: 1e-9)
    }

    func testOrdersAndHoldingsReferenceInstrumentsFromTheSameGeneratedSet() {
        // The reason MarketData exists at all: three screens showing three different prices for
        // AAPL is the failure mode of generating per screen.
        let data = generate(17)
        let symbols = Set(data.instruments.map(\.symbol))
        XCTAssertTrue(data.orders.allSatisfy { symbols.contains($0.symbol) })
        XCTAssertTrue(data.portfolio.holdings.allSatisfy { symbols.contains($0.instrument.symbol) })
        XCTAssertTrue(data.news.allSatisfy { article in
            symbols.contains { article.headline.hasPrefix("\($0):") }
        })
    }

    func testNewsIsOrderedMostRecentFirst() {
        let ages = generate(19).news.map(\.minutesAgo)
        XCTAssertEqual(ages.sorted(), ages)
    }

    func testDefaultFavouritesAreNonEmptySoTheDashboardWidgetHasContent() {
        XCTAssertFalse(generate(23).defaultFavourites.isEmpty)
    }
}
