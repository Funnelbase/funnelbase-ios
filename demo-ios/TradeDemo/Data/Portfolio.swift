import Foundation

struct Holding: Identifiable, Hashable {
    let instrument: Instrument
    let quantity: Int

    var id: String { instrument.symbol }
    var marketValue: Double { Double(quantity) * instrument.price }
    var dayChange: Double { Double(quantity) * instrument.changeAbsolute }
}

/// The signed-in user's positions.
///
/// Day change is summed from the holdings rather than generated, so the percentage on the
/// dashboard is the one the Markets screen implies. A separately-invented portfolio number would
/// contradict the instrument list the moment anyone added it up.
struct Portfolio {
    let holdings: [Holding]
    let cashUsd: Double

    var investedValue: Double { holdings.reduce(0) { $0 + $1.marketValue } }
    var totalValue: Double { investedValue + cashUsd }
    var dayChange: Double { holdings.reduce(0) { $0 + $1.dayChange } }

    /// Against yesterday's close of the same positions; cash does not move, so it is excluded.
    var dayChangePercent: Double {
        let previous = investedValue - dayChange
        return previous <= 0 ? 0 : dayChange / previous * 100
    }

    var isUp: Bool { dayChange >= 0 }
}

enum Portfolios {

    static func generate(_ random: SeededRandom, instruments: [Instrument]) -> Portfolio {
        let held = Array(random.shuffled(instruments).prefix(random.int(5, 9)))
        return Portfolio(
            holdings: held.map { Holding(instrument: $0, quantity: random.element(quantities)) },
            cashUsd: (random.double(1_500, 25_000) * 100).rounded() / 100
        )
    }

    private static let quantities = [4, 8, 12, 15, 20, 30, 45, 60, 80, 120]
}
