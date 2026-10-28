import SwiftUI

/// The whole navigation graph.
///
/// Onboarding and the signed-in app are two different shells rather than one stack with a start
/// destination, which is where the port parts company with Android: there, one `NavHost` avoids
/// recreating the host and losing the tab back stacks whenever the signed-in flag changes; here
/// the tab paths live in `Navigator`, outside the views, so swapping the shell loses nothing.
struct RootView: View {

    @StateObject private var appState = AppState()
    @StateObject private var navigator = Navigator()
    @ObservedObject private var inbox = PushInbox.shared

    var body: some View {
        Group {
            if appState.isSignedIn {
                MainTabs()
            } else {
                OnboardingFlow()
            }
        }
        .environmentObject(appState)
        .environmentObject(navigator)
        .tradeDemoTheme()
        .onAppear { follow(inbox.route) }
        .onChange(of: inbox.route) { follow($0) }
    }

    private func follow(_ route: String?) {
        guard let route else { return }
        // A push that arrives before anyone has signed in leads nowhere: the screens behind it
        // need an account, and the open has been recorded either way.
        if appState.isSignedIn {
            navigator.follow(route)
        }
        inbox.route = nil
    }
}

/// The four tabs, each with a stack of its own.
struct MainTabs: View {

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var navigator: Navigator

    var body: some View {
        TabView(selection: $navigator.tab) {
            NavigationStack(path: $navigator.dashboard) {
                DashboardScreen()
                    .navigationDestination(for: AppRoute.self) { destination($0) }
            }
            .tabItem { Label(Tab.dashboard.label, systemImage: Tab.dashboard.icon) }
            .tag(Tab.dashboard)

            NavigationStack(path: $navigator.markets) {
                MarketsScreen()
                    .navigationDestination(for: AppRoute.self) { destination($0) }
            }
            .tabItem { Label(Tab.markets.label, systemImage: Tab.markets.icon) }
            .tag(Tab.markets)

            NavigationStack(path: $navigator.orders) {
                OrdersScreen()
                    .navigationDestination(for: AppRoute.self) { destination($0) }
            }
            .tabItem { Label(Tab.orders.label, systemImage: Tab.orders.icon) }
            .tag(Tab.orders)

            NavigationStack(path: $navigator.news) {
                NewsScreen()
                    .navigationDestination(for: AppRoute.self) { destination($0) }
            }
            .tabItem { Label(Tab.news.label, systemImage: Tab.news.icon) }
            .tag(Tab.news)
        }
        .toolbarBackground(TradeDemoColors.surface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }

    /// The two pages that are not tabs. The bar is hidden under both — the instrument detail is
    /// a full-screen page, and notifications are a setting rather than a section of the product.
    @ViewBuilder
    private func destination(_ route: AppRoute) -> some View {
        switch route {
        case .instrument(let symbol):
            InstrumentDetailScreen(symbol: symbol)
                .toolbar(.hidden, for: .tabBar)
        case .pushSettings:
            PushScreen()
                .toolbar(.hidden, for: .tabBar)
        case .notificationSettings:
            NotificationSettingsScreen()
                .toolbar(.hidden, for: .tabBar)
        }
    }
}

private enum OnboardingRoute: Hashable {
    case signIn
    case signUp
}

/// Welcome, and the two ways out of it. Signing in swaps the whole shell, which is this port's
/// equivalent of clearing the onboarding back stack: back from the dashboard cannot return to a
/// login form because the form is no longer in the graph.
struct OnboardingFlow: View {

    @EnvironmentObject private var appState: AppState
    @State private var path: [OnboardingRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeScreen(
                onSignUp: { path.append(.signUp) },
                onSignIn: { path.append(.signIn) }
            )
            .navigationDestination(for: OnboardingRoute.self) { route in
                switch route {
                case .signIn:
                    SignInScreen(onSignedIn: { appState.signIn($0, pro: $1) })
                case .signUp:
                    SignUpFlow(
                        onSignedUp: { appState.signUp($0) },
                        onBack: { if !path.isEmpty { path.removeLast() } }
                    )
                }
            }
        }
    }
}

extension View {
    /// The top bar drawn on the app's own background rather than a translucent system grey,
    /// which is what the Android demo's `containerColor = background` does on every top app bar.
    func tradeDemoNavigationBar() -> some View {
        toolbarBackground(TradeDemoColors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }

    /// The app's ground, under a scrolling screen. SwiftUI would otherwise draw the system's.
    func tradeDemoScreenBackground() -> some View {
        background(TradeDemoColors.background.ignoresSafeArea())
    }
}
