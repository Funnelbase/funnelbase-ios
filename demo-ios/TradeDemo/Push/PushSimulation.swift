import Funnelbase
import Foundation
import UserNotifications

/// Payloads shaped exactly as the backend sends them, so the app can show what a campaign
/// will look like without APNs, a certificate, or a network at all.
///
/// They exist because the parts of push a developer most wants to see — the buttons, the
/// collapsing, the tap and where it leads — are the parts that need a provider to arrive.
///
/// On Apple devices there is a limit the Android demo does not have: nothing local can make the
/// system run a notification service extension, and the extension is what attaches the image and
/// reports the receipt. So a simulated push is posted as a **local** notification carrying the
/// same `userInfo` keys a real one arrives with — the text, the buttons, the thread and the tap
/// are the real thing, and the image and the `$push_received` receipt are not.
///
/// The image url points at a local push provider's sample image (port 9099) as the simulator
/// reaches it, for the day a real push is sent to this build from a laptop.
enum PushSimulation {

    /// The simulator shares the host's loopback, so `localhost` is the host — no `10.0.2.2`
    /// alias the way an Android emulator needs one.
    static let localImageUrl = "http://localhost:9099/media/sample.png"

    /// The run id a simulated push claims. A real one is a uuid the dashboard shows; this is
    /// deliberately not one, so an open from a simulation is recognisable in the data rather
    /// than counting against a campaign that was never sent.
    static let simulatedRun = "simulated-local-run"

    /// Title, body, a deep link, and nothing else: what most campaigns are.
    static func basic(deliveryId: String) -> [String: String] {
        [
            "delivery_id": deliveryId,
            "run_id": simulatedRun,
            "title": "AAPL is up 2.4%",
            "body": "Apple leads the index this morning after yesterday's close.",
            "deep_link": "trade://instrument/AAPL",
        ]
    }

    /// An image, a long body and two buttons that lead to different places.
    static func rich(deliveryId: String, imageUrl: String = localImageUrl) -> [String: String] {
        [
            "delivery_id": deliveryId,
            "run_id": simulatedRun,
            "title": "Your order filled",
            "body": "12 shares of MSFT at $412.80. The rest of the order was cancelled at the "
                + "close, and the cash is back in your account.",
            "image_url": imageUrl,
            "deep_link": "trade://orders",
            "buttons": #"[{"id":"view_order","title":"View order","deep_link":"trade://instrument/MSFT"},"#
                + #"{"id":"markets","title":"Markets","deep_link":"trade://markets"}]"#,
        ]
    }

    /// Two of these replace one another in the notification list rather than stacking, which is
    /// what a collapse key is for.
    static func collapsing(deliveryId: String) -> [String: String] {
        [
            "delivery_id": deliveryId,
            "run_id": simulatedRun,
            "title": "Market close",
            "body": "The index finished at \(Int.random(in: 4_800...5_200)), a new print each time.",
            "collapse_key": "market_close",
        ]
    }

    /// Posts one, as a local notification.
    ///
    /// `NotificationPlan` is the SDK's own decision about what a push should become, and the
    /// service extension builds a real one from exactly this — so the category identifier here
    /// is the identifier a real delivery of the same payload would use, and the buttons are
    /// registered under it the same way. What is missing is the image, which is a download the
    /// extension does and this does not.
    ///
    /// A few seconds of delay so the banner can be seen after backgrounding the app, which is
    /// where a notification is actually worth looking at.
    static func post(_ data: [String: String], after delay: TimeInterval = 3) {
        guard let payload = PushParser.parse(data) else { return }
        let plan = NotificationPlan.of(payload, allowInsecureImages: true)

        let content = UNMutableNotificationContent()
        content.title = payload.title
        content.body = payload.body
        content.sound = .default
        content.userInfo = data
        if let thread = plan.threadIdentifier {
            content.threadIdentifier = thread
        }
        if let category = plan.categoryIdentifier {
            register(buttons: plan.buttons, under: category)
            content.categoryIdentifier = category
        }

        // A collapse key replaces: the request identifier is what the system de-duplicates on,
        // so two of these become one notification rather than two.
        let identifier = payload.collapseKey ?? payload.deliveryId
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(delay, 1), repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Existing categories are kept: an app that registered its own must not lose them because
    /// a simulated campaign was posted.
    private static func register(buttons: [PushButton], under identifier: String) {
        let center = UNUserNotificationCenter.current()
        let actions = buttons.map {
            UNNotificationAction(identifier: $0.id, title: $0.title, options: [.foreground])
        }
        let category = UNNotificationCategory(
            identifier: identifier,
            actions: actions,
            intentIdentifiers: [],
            options: []
        )
        center.getNotificationCategories { existing in
            var categories = existing.filter { $0.identifier != identifier }
            categories.insert(category)
            center.setNotificationCategories(categories)
        }
    }

    /// A delivery id per simulated push, so each one is its own notification and its own open.
    static func deliveryId() -> String {
        "sim-" + UUID().uuidString.prefix(8).lowercased()
    }
}
