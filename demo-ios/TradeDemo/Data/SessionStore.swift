import Foundation

/// The only thing this app persists: who is signed in (and on which plan), and which symbols they
/// favourited.
///
/// `UserDefaults`, which is what the Android demo's `SharedPreferences` is. Two keys read once at
/// startup do not need a database or another dependency, and the SDK next door makes the same
/// call for the same reason.
final class SessionStore {

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var username: String? {
        get { defaults.string(forKey: Keys.username) }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Keys.username)
            } else {
                defaults.removeObject(forKey: Keys.username)
            }
        }
    }

    /// The day the signed-in account's pro plan next renews, as `YYYY-MM-DD`, or nil on the free
    /// plan. Kept so a relaunch's re-identify sends the same day the sign-in did
    /// (`AppState.identify`).
    var planRenewsOn: String? {
        get { defaults.string(forKey: Keys.planRenewsOn) }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Keys.planRenewsOn)
            } else {
                defaults.removeObject(forKey: Keys.planRenewsOn)
            }
        }
    }

    var favourites: Set<String> {
        get { Set(defaults.stringArray(forKey: Keys.favourites) ?? []) }
        // Sorted on the way out so the stored value does not churn between launches for no
        // reason; a set has no order and UserDefaults would record a different array each time.
        set { defaults.set(newValue.sorted(), forKey: Keys.favourites) }
    }

    /// True until the first sign-up or sign-in, so favourites can be seeded exactly once.
    var isFirstRun: Bool { defaults.object(forKey: Keys.favourites) == nil }

    func clearUser() {
        username = nil
        planRenewsOn = nil
    }

    private enum Keys {
        static let username = "trade-demo.username"
        static let favourites = "trade-demo.favourites"
        static let planRenewsOn = "trade-demo.plan-renews-on"
    }
}
