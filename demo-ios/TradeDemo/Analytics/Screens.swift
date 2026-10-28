/// Every screen name this app reports, in one place.
///
/// `screen_name` is a dashboard dimension, so these strings are the taxonomy — renaming one
/// splits a chart in two rather than relabelling it. Constants rather than route strings so a
/// navigation refactor cannot silently rewrite the analytics.
///
/// snake_case to match the event and property naming everywhere else in the platform, and the
/// same thirteen values the Android demo reports: one person on a phone and an iPad is one person,
/// and one screen on iOS and Android is one series.
enum Screens {
    static let welcome = "welcome"
    static let signIn = "sign_in"

    /// The paged sign-up intro. 1-based: `signup_intro_1` reads better in a chart than `_0`.
    static func signUpIntro(_ page: Int) -> String { "signup_intro_\(page + 1)" }

    static let signUpUsername = "signup_username"

    static let dashboard = "dashboard"
    static let markets = "markets"
    static let orders = "orders"
    static let news = "news"

    /// Which instrument is on it is an `Events.instrumentViewed` event, not a screen property.
    static let instrumentDetail = "instrument_detail"

    /// Notifications: the permission, this install's token, and the simulated campaigns.
    static let push = "push_settings"

    /// Which notification topics this person gets, from the app's list in the dashboard.
    static let notificationSettings = "notification_settings"
}
