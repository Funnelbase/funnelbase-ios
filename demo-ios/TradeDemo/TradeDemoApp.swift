import Funnelbase
import SwiftUI
import UIKit
import UserNotifications

@main
struct TradeDemoApp: App {

    /// SwiftUI has no hook for the two things push needs — the APNs token and a tap — so there
    /// is still an app delegate. It is the only UIKit in the app.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// The three settings the app reads at runtime, from the Info.plist, from Build.xcconfig.
///
/// The key is a credential and is not in the repository: `Config.xcconfig` is gitignored and
/// absent on a clean clone, exactly as the Android demo's `local.properties` is. So a clone
/// builds with a blank key, and a blank key means the SDK is never initialised.
enum DemoConfig {

    static var apiKey: String { string("AnalyticsApiKey") }
    static var endpoint: String { string("AnalyticsEndpoint") }

    /// Shared with the notification service extension, and the reason a receipt recorded in that
    /// process reaches this one's upload queue. It has to match the entitlement on both targets.
    static let appGroup = "group.com.analytics.demo.trading"

    private static func string(_ key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        startAnalytics()

        // Set before launching finishes, or a tap that started the app is delivered to nobody
        // and the open it should have reported is lost.
        UNUserNotificationCenter.current().delegate = self
        registerForPushIfAlreadyAllowed(application)
        return true
    }

    /// Initialises the SDK, or says why it did not.
    ///
    /// **With no key configured the app runs normally and initialises no SDK.** That is
    /// deliberate, and the same choice the Android demo makes: a demo that crashes on a fresh
    /// clone is worse than one that quietly collects nothing.
    private func startAnalytics() {
        let key = DemoConfig.apiKey
        let endpoint = DemoConfig.endpoint
        guard !key.isEmpty, endpoint.hasPrefix("http") else {
            NSLog("[TradeDemo] No ingest key configured — analytics is off. "
                + "Copy demo-ios/Config.example.xcconfig to Config.xcconfig; see docs/demo-app.md.")
            return
        }

        var debugLogging = false
        #if DEBUG
        debugLogging = true
        #endif

        Analytics.initialize(
            AnalyticsConfig(
                apiKey: key,
                endpoint: endpoint,
                debugLogging: debugLogging,
                appGroup: DemoConfig.appGroup
            )
        )
    }

    /// Asks APNs for this install's token on every launch, when the person has already allowed
    /// notifications.
    ///
    /// A token can be reissued without the app being told, so an install whose token changed
    /// while the app was closed would never register the new one otherwise. Asking is free when
    /// permission is already granted — no prompt is shown. The Notifications screen is where a
    /// person who has not decided yet is asked.
    private func registerForPushIfAlreadyAllowed(_ application: UIApplication) {
        Analytics.push.notificationsEnabled { allowed in
            guard allowed else { return }
            DispatchQueue.main.async { application.registerForRemoteNotifications() }
        }
    }

    // MARK: - The token

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // Apple's own token, registered as it is. The platform talks to Apple directly, so there
        // is no other party to pair it with — and the SDK takes a token from whoever holds one,
        // which is what also lets an app on Firebase or on its own gateway use it
        // (docs/push.md).
        Analytics.push.setAPNSToken(deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // A simulator with no push support and a build with no provisioning both land here, and
        // neither is a reason to stop. The Notifications screen can register a token by hand,
        // which is how a custom HTTP integration is exercised without APNs at all.
        NSLog("[TradeDemo] APNs would not issue a token: %@", error.localizedDescription)
    }

    // MARK: - Arriving, and being tapped

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // No receipt reported from here, on purpose. On Apple devices the receipt belongs to the
        // notification service extension, which the system runs for every campaign push whatever
        // the app is doing — reporting it again here would count one delivery twice.
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // The SDK records the open and hands the push back. Where to go is the app's half of it,
        // because only the app knows its own screens.
        defer { completionHandler() }
        guard let payload = Analytics.push.handle(response: response) else { return }

        // A dismissal is not an open and leads nowhere: the person put the notification away.
        guard response.actionIdentifier != UNNotificationDismissActionIdentifier else { return }

        let actionId = response.actionIdentifier == UNNotificationDefaultActionIdentifier
            ? nil
            : response.actionIdentifier
        let route = PushRouting.routeFor(PushRouting.linkFor(payload, actionId: actionId))
        DispatchQueue.main.async { PushInbox.shared.route = route }
    }
}
