import Foundation
@_exported import FunnelbaseCore
#if canImport(UIKit)
import UIKit
#endif

/// The SDK's entire public surface, mirroring the Android SDK method for method.
///
/// ```swift
/// Analytics.initialize(AnalyticsConfig(apiKey: key, endpoint: "https://ingest.example.com"))
/// Analytics.track("checkout_completed", properties: ["cart_total": 42.5, "currency": "EUR"])
/// ```
///
/// Every method is safe from any thread and safe before `initialize` — an uninitialised SDK logs
/// and drops the call rather than trapping. Analytics is never worth taking someone's app down for.
///
/// What it sends, and when, is docs/event-contract.md: every event carries a `device_id`, an
/// `anonymous_id` and, while signed in, a `user_id`; `$session_start` goes in front of every
/// session's first event, and `$first_open` once per install.
public enum Analytics {

    private static let lock = NSLock()
    private static var client: AnalyticsClient?
    private static var lifecycle: LifecycleObserver?

    /// Wires up the SDK. Call once, as early as the app starts.
    public static func initialize(_ config: AnalyticsConfig) {
        lock.lock()
        defer { lock.unlock() }
        guard client == nil else {
            print("[Analytics] initialize called more than once — ignoring the later call")
            return
        }
        let instance = AnalyticsClient(config: config)
        client = instance
        AnalyticsPush.shared.attach(client: instance, appGroup: config.appGroup)
        AnalyticsTopics.shared.attach(client: instance)
        if config.trackApplicationLifecycle {
            lifecycle = LifecycleObserver { instance.flush() }
        }
    }

    /// Records a custom event. Values may be a string, a number, a boolean or a date; types are
    /// preserved end to end, so send `42` rather than `"42"` if you will ever filter on a range. A
    /// date goes out as ISO text, what a property declared `date` accepts: an `AnalyticsDay` as a
    /// calendar day (`2026-11-03`), a `Date` as an exact moment in UTC (`2026-11-03T09:00:00Z`).
    public static func track(_ eventName: String, properties: [String: Any?] = [:]) {
        guard !eventName.hasPrefix("$") else {
            print("[Analytics] '\(eventName)' is reserved — use one of the SDK's own methods")
            return
        }
        withClient("track") { $0.track(eventName, properties: properties) }
    }

    /// Records a screen view. The screen's name is the dimension a dashboard groups by.
    public static func screen(_ screenName: String, properties: [String: Any?] = [:]) {
        withClient("screen") {
            var merged = properties
            merged[ReservedEvents.screenViewScreenName] = screenName
            $0.track(ReservedEvents.screenView, properties: merged)
        }
    }

    /// Associates what follows with a known account, and updates their traits. Call at sign-in, at
    /// sign-up, and on every launch while signed in, before the first screen view of that launch.
    /// Traits take the same values as `track`'s properties, dates included — an `AnalyticsDay` such
    /// as a plan's renewal day goes out as `2026-11-03`, what a trait declared `date` accepts.
    public static func identify(_ userId: String, traits: [String: Any?] = [:]) {
        withClient("identify") {
            $0.identify(userId, traits: traits)
            // The registry keys a token by install, but a run's audience is people: the same
            // device is now a different person.
            AnalyticsPush.shared.identityChanged()
        }
    }

    /// Uploads queued events now instead of waiting for the next interval.
    public static func flush() {
        withClient("flush") { $0.flush() }
    }

    /// Sign-out: a new anonymous id and a new session. Without it, the next person to use the
    /// device inherits the last one's identity. The device id is untouched.
    public static func reset() {
        withClient("reset") {
            $0.reset()
            AnalyticsPush.shared.identityChanged()
        }
    }

    /// Push: registering this install's token, reporting a receipt and a tap.
    public static var push: AnalyticsPush { AnalyticsPush.shared }

    /// Notification topics: the app's list, and switching one on or off for this person.
    public static var topics: AnalyticsTopics { AnalyticsTopics.shared }

    private static func withClient(_ operation: String, _ block: (AnalyticsClient) -> Void) {
        lock.lock()
        let instance = client
        lock.unlock()
        guard let instance else {
            print("[Analytics] \(operation) called before initialize() — ignoring")
            return
        }
        block(instance)
    }
}

/// Flushes when the app goes to the background, which is the last chance before it may be
/// suspended with events still queued.
private final class LifecycleObserver {
    private var observers: [NSObjectProtocol] = []

    init(onBackground: @escaping () -> Void) {
        #if canImport(UIKit) && !os(macOS)
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { _ in onBackground() },
            center.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: nil) { _ in onBackground() },
        ]
        #endif
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }
}
