import Foundation

enum OrderStatus: String, CaseIterable, Hashable {
    case pending, filled, cancelled

    var label: String {
        switch self {
        case .pending: return "Pending"
        case .filled: return "Filled"
        case .cancelled: return "Cancelled"
        }
    }
}

enum OrderSide: String, Hashable {
    case buy, sell

    var label: String {
        switch self {
        case .buy: return "Buy"
        case .sell: return "Sell"
        }
    }
}

/// One order.
///
/// `cost` is computed, not stored, so quantity × price and the displayed total can never
/// disagree — which is exactly the kind of thing a reader checks with a calculator on a demo
/// screen.
struct Order: Identifiable, Hashable {
    let id: String
    let symbol: String
    let companyName: String
    let side: OrderSide
    let status: OrderStatus
    let quantity: Int
    let price: Double
    let placedMinutesAgo: Int

    var cost: Double { Double(quantity) * price }
}

enum Orders {

    /// Sample orders across all three statuses.
    ///
    /// Prices come from the instruments generated for this launch rather than being invented, so
    /// an order for AAPL sits in the same range as AAPL does on the Markets screen. Filled orders
    /// are priced slightly off the current price — an order that filled earlier in the day at
    /// exactly the current price would be a coincidence on every row.
    static func generate(_ random: SeededRandom, instruments: [Instrument]) -> [Order] {
        let statuses = Array(repeating: OrderStatus.pending, count: 7)
            + Array(repeating: OrderStatus.filled, count: 8)
            + Array(repeating: OrderStatus.cancelled, count: 5)

        // The reference is what a list row is keyed by, and a repeated key makes SwiftUI merge
        // two rows into one rather than complain — so a redraw is enough to lose an order. Five
        // digits collide about once in five hundred runs, which is far too often to leave.
        var used = Set<String>()

        let orders = statuses.enumerated().map { index, status -> Order in
            let instrument = random.element(instruments)
            let drift: Double
            switch status {
            case .filled: drift = random.double(-0.04, 0.04)
            // A resting limit order sits away from the market, which is why it is resting.
            case .pending: drift = random.double(-0.08, 0.08)
            case .cancelled: drift = random.double(-0.12, 0.12)
            }

            var reference = String(format: "ORD-%05d", random.int(10_000, 99_999))
            while used.contains(reference) {
                reference = String(format: "ORD-%05d", random.int(10_000, 99_999))
            }
            used.insert(reference)

            return Order(
                id: reference,
                symbol: instrument.symbol,
                companyName: instrument.name,
                side: random.bool() ? .buy : .sell,
                status: status,
                quantity: random.element(quantities),
                price: (instrument.price * (1 + drift) * 100).rounded() / 100,
                placedMinutesAgo: (index + 1) * random.int(7, 90)
            )
        }

        return orders.sorted { $0.placedMinutesAgo < $1.placedMinutesAgo }
    }

    // Round lots, the way someone actually types an order — not a draw from 1...500.
    private static let quantities = [5, 10, 15, 20, 25, 40, 50, 75, 100, 120, 150, 200, 250, 500]
}
