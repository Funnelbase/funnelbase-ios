import Foundation

struct NewsArticle: Identifiable, Hashable {
    let id: String
    let headline: String
    let summary: String
    let source: String
    let minutesAgo: Int
}

/// The news feed: generated headlines and summaries.
///
/// Headlines are prefixed with a real ticker from the launch's instrument list so the feed looks
/// like it belongs to this app rather than to a lorem ipsum generator, while the body stays
/// obviously synthetic.
enum News {

    private static let sources = ["Market Wire", "Global Desk", "Trading Floor", "The Ticker Report"]

    static func generate(_ random: SeededRandom, instruments: [Instrument], count: Int = 20) -> [NewsArticle] {
        // Accumulated, not `index * random(...)`: multiplying is not monotonic — article 1 could
        // draw 69 and article 2 draw 2x9=18 — and the feed would show "1h ago" above "12m ago".
        // Adding a positive gap each time is what actually makes the list order the sort order.
        var minutesAgo = 0

        return (0..<count).map { index in
            let instrument = random.element(instruments)
            minutesAgo += random.int(9, 70)

            return NewsArticle(
                id: "news-\(index)",
                headline: "\(instrument.symbol): \(Lorem.headline(random))",
                summary: Lorem.paragraph(random, sentences: random.int(2, 4)),
                source: random.element(sources),
                minutesAgo: minutesAgo
            )
        }
    }
}
