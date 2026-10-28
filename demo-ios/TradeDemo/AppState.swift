import Funnelbase
import Combine
import Foundation

/// The app's entire mutable state: who is signed in and what they favourited.
///
/// One `ObservableObject` held at the root, not a store per screen and no dependency graph.
/// There is no async work, nothing to restore beyond what `SessionStore` writes to disk, and two
/// fields — anything more would be ceremony around them.
///
/// This is also the one place that touches identity in the SDK. Keeping `identify` and `reset`
/// next to the state change they describe is what stops a screen from flipping the username
/// without telling analytics about it.
final class AppState: ObservableObject {

    @Published private(set) var username: String?
    @Published private(set) var favourites: Set<String>

    let market: MarketData
    private let store: SessionStore

    init(store: SessionStore = SessionStore(), market: MarketData = .current) {
        self.store = store
        self.market = market
        self.username = store.username

        if store.isFirstRun {
            // First run seeds a handful so the dashboard's favourites widget has something in
            // it. An empty-state screenshot is not what anyone wants from a demo's home tab.
            let seeded = market.defaultFavourites
            store.favourites = seeded
            self.favourites = seeded
        } else {
            self.favourites = store.favourites
        }

        // A relaunch of an already-signed-in app has to re-identify: the SDK keeps the user id
        // in its own store, but the traits and the `$identify` marking the start of this run
        // would otherwise be missing. It happens in the initialiser, which runs before any view
        // body and therefore before the first screen view — so the session's start, and the
        // install's `$first_open` on the day the SDK arrives, are sent signed in.
        if store.username != nil {
            identify()
        }
    }

    var isSignedIn: Bool { username != nil }

    /// Sign-in with any credentials, as specified — there is no auth backend.
    ///
    /// One `identify`, and that is the whole of it (docs/event-contract.md): the `$identify` it
    /// sends carries the device's anonymous id and the account together, which is the link
    /// between them. Signing in as a different account than the one before is an account switch,
    /// and the SDK resets the anonymous id and the session itself before identifying.
    func signIn(_ username: String, pro: Bool = false) {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        store.username = name
        self.username = name
        // There is no billing either: the sign-in screen's switch says which plan the account is
        // on, and a pro plan renews 30 days from the sign-in — a calendar day, which is what a
        // journey's "wait until a date" and a segment's "in the next N days" read.
        store.planRenewsOn = pro ? Self.day(Self.calendar.date(byAdding: .day, value: Self.planPeriodDays, to: Date())!) : nil
        identify()
    }

    /// Registration. The same `identify` as a sign-in — there is no alias call to make first.
    /// The onboarding pages this person viewed before creating the account were sent under the
    /// anonymous id the `$identify` now carries beside the new user id, so the backend attaches
    /// them to the account from that one event.
    func signUp(_ username: String) {
        signIn(username, pro: false)
    }

    /// Sign-out. `Analytics.reset()` uploads what is queued before clearing the identity, so the
    /// end of this person's session is not attributed to whoever signs in next — who starts with
    /// a fresh anonymous id and a session of their own.
    func signOut() {
        store.clearUser()
        username = nil
        Analytics.reset()
    }

    func toggleFavourite(_ symbol: String) {
        if favourites.contains(symbol) {
            favourites.remove(symbol)
        } else {
            favourites.insert(symbol)
        }
        store.favourites = favourites
    }

    func isFavourite(_ symbol: String) -> Bool {
        favourites.contains(symbol)
    }

    /// Sends `$identify` for whoever is signed in, with every trait the app knows: `username`,
    /// `plan`, and on pro `plan_renews_on` as an `AnalyticsDay`, which the SDK sends as
    /// `YYYY-MM-DD` (docs/event-contract.md, "Dates").
    private func identify() {
        guard let name = store.username else { return }
        var traits: [String: Any?] = ["username": name, "plan": "free"]
        if let renewsOn = currentRenewal() {
            traits["plan"] = "pro"
            traits["plan_renews_on"] = AnalyticsDay(renewsOn, timeZone: Self.calendar.timeZone)
        }
        Analytics.identify(UserId.forUsername(name), traits: traits)
    }

    /// The stored renewal day, moved on by whole periods when a relaunch comes long after the
    /// sign-in: the plan has renewed since, as often as it took. Nil on the free plan.
    private func currentRenewal() -> Date? {
        guard let stored = store.planRenewsOn, var renewsOn = Self.dayFormatter.date(from: stored) else { return nil }
        let today = Self.calendar.startOfDay(for: Date())
        while renewsOn < today {
            renewsOn = Self.calendar.date(byAdding: .day, value: Self.planPeriodDays, to: renewsOn)!
        }
        store.planRenewsOn = Self.day(renewsOn)
        return renewsOn
    }

    /// How often a pro plan renews; the trading simulator's renewals are 30 days apart too.
    private static let planPeriodDays = 30
    private static let calendar = Calendar(identifier: .gregorian)

    private static func day(_ date: Date) -> String {
        AnalyticsDay(date, timeZone: calendar.timeZone).description
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
