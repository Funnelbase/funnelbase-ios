import SwiftUI

/// Navigation routes.
///
/// Separate from `Screens` on purpose. These are addresses the navigation stack resolves; those
/// are the dimension a dashboard groups by. Reusing one string for both means a routing refactor
/// silently rewrites the analytics taxonomy, and the chart that has been tracking `markets` for
/// six months starts a new series.
///
/// They are strings rather than cases because a push's deep link is a string and this is what it
/// is resolved against — `PushRouting` produces one of these.
enum Routes {
    static let dashboard = "dashboard"
    static let markets = "markets"
    static let orders = "orders"
    static let news = "news"

    static func instrumentDetail(_ symbol: String) -> String { "instrument/\(symbol)" }

    static let instrumentPrefix = "instrument/"
}

/// The four bottom-bar tabs, in display order.
enum Tab: String, CaseIterable, Hashable {
    case dashboard
    case markets
    case orders
    case news

    var route: String {
        switch self {
        case .dashboard: return Routes.dashboard
        case .markets: return Routes.markets
        case .orders: return Routes.orders
        case .news: return Routes.news
        }
    }

    var label: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .markets: return "Markets"
        case .orders: return "Orders"
        case .news: return "News"
        }
    }

    /// Labels are always shown: four tabs fit comfortably, and an icon-only bar makes people
    /// guess what a candlestick glyph means.
    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .markets: return "chart.bar"
        case .orders: return "list.bullet.rectangle"
        case .news: return "newspaper"
        }
    }
}

/// Everything pushed on top of a tab. The tab bar is hidden on both of them — an instrument is a
/// full-screen page, and push is a setting rather than a section of the product.
enum AppRoute: Hashable {
    case instrument(String)
    case pushSettings
    /// The topics a person may switch off, reached from the notifications screen.
    case notificationSettings
}
