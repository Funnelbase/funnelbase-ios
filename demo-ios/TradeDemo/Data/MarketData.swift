import Foundation

/// Everything the app displays, generated once per process.
///
/// A single object rather than one generator per screen: the dashboard's portfolio, the orders
/// list and the news feed all reference instruments, and regenerating them per screen would show
/// three different prices for AAPL depending on which tab you were looking at.
///
/// Deliberately not persisted and deliberately unseeded in the app — a fresh random set every
/// launch, which is what makes it self-evident that none of it is real data. The tests hand in a
/// seed instead, because an invariant that fails has to be reproducible.
final class MarketData {

    let instruments: [Instrument]
    let portfolio: Portfolio
    let orders: [Order]
    let news: [NewsArticle]

    private let bySymbol: [String: Instrument]

    private init(instruments: [Instrument], portfolio: Portfolio, orders: [Order], news: [NewsArticle]) {
        self.instruments = instruments
        self.portfolio = portfolio
        self.orders = orders
        self.news = news
        self.bySymbol = Dictionary(uniqueKeysWithValues: instruments.map { ($0.symbol, $0) })
    }

    func instrument(_ symbol: String) -> Instrument? { bySymbol[symbol] }

    /// The symbols favourited by default on a first run, so the dashboard is never empty.
    var defaultFavourites: Set<String> { Set(instruments.prefix(4).map(\.symbol)) }

    /// Built on first access rather than at launch — generating fifty instruments plus their
    /// lorem prose is not much work, but it is not work that belongs on the path to the first
    /// frame either. A Swift static is lazy, which is all this needs.
    static let current: MarketData = generate(SeededRandom.unseeded())

    static func generate(_ random: SeededRandom) -> MarketData {
        let instruments = Instruments.generate(random)
        return MarketData(
            instruments: instruments,
            portfolio: Portfolios.generate(random, instruments: instruments),
            orders: Orders.generate(random, instruments: instruments),
            news: News.generate(random, instruments: instruments)
        )
    }
}
