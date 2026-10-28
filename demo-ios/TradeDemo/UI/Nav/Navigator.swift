import SwiftUI

/// Which tab is showing and what is stacked on top of each one.
///
/// One path per tab rather than one for the whole app: a bottom bar is expected to remember
/// where each tab was, and back from a tab's root leaves the app rather than walking the history
/// of tabs visited. That is what Android's `popUpTo(startDestination) { saveState = true }` buys
/// there and what four `NavigationStack` paths buy here.
///
/// Four named arrays rather than a dictionary keyed by tab, because each one is bound straight
/// into a `NavigationStack` and a binding into a dictionary is not worth the ceremony.
final class Navigator: ObservableObject {

    @Published var tab: Tab = .dashboard
    @Published var dashboard: [AppRoute] = []
    @Published var markets: [AppRoute] = []
    @Published var orders: [AppRoute] = []
    @Published var news: [AppRoute] = []

    /// Pushes onto whichever tab is showing, so going back from an instrument returns to the
    /// list it was opened from.
    func push(_ route: AppRoute) {
        switch tab {
        case .dashboard: dashboard.append(route)
        case .markets: markets.append(route)
        case .orders: orders.append(route)
        case .news: news.append(route)
        }
    }

    func select(_ tab: Tab) {
        self.tab = tab
    }

    /// Follows a route a push asked for, as `PushRouting` read it. A tab link switches tabs; an
    /// instrument link opens that instrument on top of wherever the person already was.
    func follow(_ route: String) {
        if let tab = Tab.allCases.first(where: { $0.route == route }) {
            select(tab)
            return
        }
        if route.hasPrefix(Routes.instrumentPrefix) {
            push(.instrument(String(route.dropFirst(Routes.instrumentPrefix.count))))
        }
    }

    /// Sign-out: the signed-in screens must not still be stacked up behind the welcome page.
    func reset() {
        tab = .dashboard
        dashboard = []
        markets = []
        orders = []
        news = []
    }
}

/// Where a tapped push wants to go, parked until something can navigate.
///
/// The tap arrives on the app delegate, which has no view to move. A tap that launched the app
/// from cold arrives before there is a navigator at all, so it waits here and the root view
/// follows it when it appears. The SDK has already recorded the open by then — this is only the
/// navigation, which it cannot do for the app.
final class PushInbox: ObservableObject {
    static let shared = PushInbox()

    @Published var route: String?

    private init() {}
}
