import Foundation

/// One tradable instrument, priced.
///
/// `changePercent` is the day's move and `price` is already the post-move price, so
/// `previousClose` is derived rather than stored — one of the two would otherwise be free to
/// drift out of agreement with the other.
struct Instrument: Identifiable, Hashable {
    let symbol: String
    let name: String
    let sector: String
    let price: Double
    let changePercent: Double
    let dayHigh: Double
    let dayLow: Double
    let open: Double
    let volume: Int64
    let marketCapUsd: Double
    let about: String

    var id: String { symbol }

    var previousClose: Double { price / (1 + changePercent / 100) }
    var changeAbsolute: Double { price - previousClose }
    var isUp: Bool { changePercent >= 0 }
}

/// The demo's instrument universe: 50 S&P 500 constituents, priced randomly at every launch.
///
/// Random per launch is the deliberate choice — the app is a demo of the analytics SDK, not of a
/// market data feed, and re-rolling the numbers each run makes it obvious that nothing here is
/// real. The *band* each price is drawn from is per-ticker though, so a share of Berkshire never
/// costs less than a share of Ford and the list stays plausible enough to read.
enum Instruments {

    /// symbol, company, sector, and the price band the launch draws from.
    private static let universe: [Ticker] = [
        Ticker("AAPL", "Apple Inc.", "Technology", 180, 240),
        Ticker("MSFT", "Microsoft Corporation", "Technology", 380, 470),
        Ticker("NVDA", "NVIDIA Corporation", "Technology", 95, 145),
        Ticker("AMZN", "Amazon.com, Inc.", "Consumer Discretionary", 170, 230),
        Ticker("GOOGL", "Alphabet Inc.", "Communication Services", 140, 200),
        Ticker("META", "Meta Platforms, Inc.", "Communication Services", 440, 620),
        Ticker("TSLA", "Tesla, Inc.", "Consumer Discretionary", 180, 400),
        Ticker("BRK.B", "Berkshire Hathaway Inc.", "Financials", 400, 490),
        Ticker("JPM", "JPMorgan Chase & Co.", "Financials", 190, 260),
        Ticker("V", "Visa Inc.", "Financials", 260, 320),
        Ticker("UNH", "UnitedHealth Group Inc.", "Health Care", 450, 600),
        Ticker("XOM", "Exxon Mobil Corporation", "Energy", 100, 125),
        Ticker("JNJ", "Johnson & Johnson", "Health Care", 140, 170),
        Ticker("MA", "Mastercard Incorporated", "Financials", 420, 540),
        Ticker("PG", "Procter & Gamble Co.", "Consumer Staples", 150, 180),
        Ticker("HD", "The Home Depot, Inc.", "Consumer Discretionary", 320, 420),
        Ticker("COST", "Costco Wholesale Corporation", "Consumer Staples", 700, 990),
        Ticker("ABBV", "AbbVie Inc.", "Health Care", 160, 205),
        Ticker("MRK", "Merck & Co., Inc.", "Health Care", 95, 135),
        Ticker("AVGO", "Broadcom Inc.", "Technology", 130, 250),
        Ticker("LLY", "Eli Lilly and Company", "Health Care", 700, 960),
        Ticker("PEP", "PepsiCo, Inc.", "Consumer Staples", 140, 180),
        Ticker("KO", "The Coca-Cola Company", "Consumer Staples", 58, 74),
        Ticker("WMT", "Walmart Inc.", "Consumer Staples", 60, 100),
        Ticker("BAC", "Bank of America Corporation", "Financials", 34, 48),
        Ticker("CVX", "Chevron Corporation", "Energy", 135, 170),
        Ticker("ADBE", "Adobe Inc.", "Technology", 400, 580),
        Ticker("CRM", "Salesforce, Inc.", "Technology", 230, 360),
        Ticker("NFLX", "Netflix, Inc.", "Communication Services", 600, 950),
        Ticker("AMD", "Advanced Micro Devices, Inc.", "Technology", 110, 210),
        Ticker("INTC", "Intel Corporation", "Technology", 19, 45),
        Ticker("CSCO", "Cisco Systems, Inc.", "Technology", 46, 62),
        Ticker("ACN", "Accenture plc", "Technology", 300, 390),
        Ticker("MCD", "McDonald's Corporation", "Consumer Discretionary", 250, 320),
        Ticker("TMO", "Thermo Fisher Scientific Inc.", "Health Care", 480, 620),
        Ticker("ABT", "Abbott Laboratories", "Health Care", 100, 130),
        Ticker("DIS", "The Walt Disney Company", "Communication Services", 84, 120),
        Ticker("VZ", "Verizon Communications Inc.", "Communication Services", 38, 46),
        Ticker("INTU", "Intuit Inc.", "Technology", 550, 720),
        Ticker("QCOM", "QUALCOMM Incorporated", "Technology", 145, 220),
        Ticker("TXN", "Texas Instruments Incorporated", "Technology", 160, 210),
        Ticker("NKE", "NIKE, Inc.", "Consumer Discretionary", 60, 100),
        Ticker("PFE", "Pfizer Inc.", "Health Care", 23, 32),
        Ticker("CAT", "Caterpillar Inc.", "Industrials", 300, 420),
        Ticker("GE", "GE Aerospace", "Industrials", 150, 210),
        Ticker("BA", "The Boeing Company", "Industrials", 130, 200),
        Ticker("UPS", "United Parcel Service, Inc.", "Industrials", 95, 145),
        Ticker("HON", "Honeywell International Inc.", "Industrials", 190, 230),
        Ticker("GS", "The Goldman Sachs Group, Inc.", "Financials", 420, 610),
        Ticker("F", "Ford Motor Company", "Consumer Discretionary", 9, 14),
    ]

    /// Every instrument, priced for this launch, in the order shown on the Markets screen.
    static func generate(_ random: SeededRandom) -> [Instrument] {
        universe.map { $0.priced(random) }
    }

    private struct Ticker {
        let symbol: String
        let name: String
        let sector: String
        let low: Double
        let high: Double

        init(_ symbol: String, _ name: String, _ sector: String, _ low: Double, _ high: Double) {
            self.symbol = symbol
            self.name = name
            self.sector = sector
            self.low = low
            self.high = high
        }

        func priced(_ random: SeededRandom) -> Instrument {
            let price = Instruments.round2(random.double(low, high))
            // ±5%, as a day's move. Bounded rather than normal: a demo list where one row shows
            // -40% reads as a bug rather than as a market.
            let changePercent = Instruments.round2(random.double(-5, 5))
            let previousClose = price / (1 + changePercent / 100)

            // The day's range must actually contain both ends of the day, or the detail screen
            // shows a high below the current price.
            let spread = price * random.double(0.005, 0.03)
            let dayHigh = Instruments.round2(max(price, previousClose) + spread)
            let dayLow = Instruments.round2(min(price, previousClose) - spread)
            let open = Instruments.round2(random.double(dayLow, dayHigh))

            return Instrument(
                symbol: symbol,
                name: name,
                sector: sector,
                price: price,
                changePercent: changePercent,
                dayHigh: dayHigh,
                dayLow: dayLow,
                open: open,
                volume: random.int64(2_000_000, 90_000_000),
                marketCapUsd: price * Double(random.int64(400_000_000, 9_000_000_000)),
                about: "\(name) operates in the \(sector.lowercased()) sector. "
                    + Lorem.paragraph(random, sentences: 4)
            )
        }
    }

    // No `abs` here. It was tempting, since every price is positive — but changePercent goes
    // through the same helper, and stripping its sign made every instrument in the list green.
    private static func round2(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}
