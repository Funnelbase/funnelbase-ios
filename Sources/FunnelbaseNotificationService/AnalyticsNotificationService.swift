import Foundation
import UserNotifications
@_exported import FunnelbaseCore

/// The notification service extension: what turns a plain alert into the notification a campaign
/// asked for, and the only place on Apple devices that can report a push arrived.
///
/// An app subclasses it, overrides `appGroup`, and writes nothing else:
///
/// ```swift
/// class NotificationService: AnalyticsNotificationService {
///     override var appGroup: String? { "group.com.example.app" }
/// }
/// ```
///
/// Three things happen here, in the ~30 seconds Apple allows:
///
/// 1. **The receipt.** The extension is a separate process and the app may never be opened again,
///    so the receipt is written to the shared queue and one upload is attempted straight away.
/// 2. **The buttons.** Apple takes buttons from a category the app registered, and the payload can
///    only name one — so the category for *this* message's buttons is registered here, as the push
///    arrives. That is what lets a campaign add a button without an app release.
/// 3. **The image.** Downloaded to disk and attached, which is the whole of a rich notification.
///
/// Whatever fails, the notification is still delivered: a push with no picture is worth more than
/// no push. Apple runs this only for a payload marked `mutable-content`, which the backend sets
/// whenever the SDK is the renderer.
open class AnalyticsNotificationService: UNNotificationServiceExtension {

    /// The app group the app and this extension share, so a receipt reaches the app's queue and is
    /// recorded under the app's identity. Nil means no sharing: the receipt is then only what this
    /// extension manages to upload itself.
    open var appGroup: String? { nil }

    /// Whether an image over plain http may be fetched. False, as Apple's transport security
    /// wants; a laptop pointing at a local provider over http overrides it.
    open var allowInsecureImages: Bool { false }

    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var content: UNMutableNotificationContent?

    override open func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        let mutable = request.content.mutableCopy() as? UNMutableNotificationContent
        self.contentHandler = contentHandler
        self.content = mutable

        guard let mutable, let payload = PushParser.parse(request.content.userInfo) else {
            // Not ours, or nothing to change: deliver what arrived.
            contentHandler(request.content)
            return
        }

        let plan = NotificationPlan.of(payload, allowInsecureImages: allowInsecureImages)

        // Reported before the slow part, so a download that overruns still leaves the receipt sent.
        PassiveEventWriter(appGroup: appGroup).recordReceipt(for: payload)

        if let categoryIdentifier = plan.categoryIdentifier {
            register(buttons: plan.buttons, under: categoryIdentifier)
            mutable.categoryIdentifier = categoryIdentifier
        }
        if let thread = plan.threadIdentifier {
            mutable.threadIdentifier = thread
        }

        guard let imageUrl = plan.imageUrl else {
            contentHandler(mutable)
            return
        }
        attach(imageUrl, to: mutable) { enriched in
            contentHandler(enriched)
        }
    }

    /// Apple is about to stop us. Deliver whatever has been made so far: the alternative is the
    /// system showing the unmodified payload, which loses the thread and the buttons too.
    override open func serviceExtensionTimeWillExpire() {
        if let contentHandler, let content {
            contentHandler(content)
        }
    }

    /// Registers a category for this message's buttons.
    ///
    /// The identifier is a function of the buttons, so this replaces an identical category rather
    /// than adding one per push. Existing categories are kept: an app that registered its own
    /// categories at launch must not lose them because a campaign arrived.
    private func register(buttons: [PushButton], under identifier: String) {
        let center = UNUserNotificationCenter.current()
        let actions = buttons.map { button in
            UNNotificationAction(
                identifier: button.id,
                title: button.title,
                // Foreground: a button on a campaign leads somewhere in the app, and the app is
                // what routes it. A background action would need the app to define the work.
                options: [.foreground]
            )
        }
        let category = UNNotificationCategory(
            identifier: identifier,
            actions: actions,
            intentIdentifiers: [],
            options: []
        )

        let waiting = DispatchSemaphore(value: 0)
        center.getNotificationCategories { existing in
            var categories = existing.filter { $0.identifier != identifier }
            categories.insert(category)
            center.setNotificationCategories(categories)
            waiting.signal()
        }
        // The banner must not be handed over before the category exists, or the buttons are
        // missing from the notification that is already on screen.
        _ = waiting.wait(timeout: .now() + AnalyticsNotificationService.categoryTimeout)
    }

    /// Downloads the image and attaches it. The file has to be on disk: Apple moves it into its own
    /// store, and refuses anything it cannot read as media.
    private func attach(
        _ url: URL,
        to content: UNMutableNotificationContent,
        completion: @escaping (UNNotificationContent) -> Void
    ) {
        let task = URLSession.shared.downloadTask(with: url) { location, response, _ in
            defer { completion(content) }
            guard let location else { return }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(status) else { return }

            // Named with the url's own extension, because Apple decides the media type from it.
            let suffix = url.pathExtension.isEmpty ? "png" : url.pathExtension
            let destination = location.deletingLastPathComponent()
                .appendingPathComponent("analytics-attachment-\(UUID().uuidString).\(suffix)")
            guard (try? FileManager.default.moveItem(at: location, to: destination)) != nil,
                  let attachment = try? UNNotificationAttachment(identifier: "image", url: destination, options: nil)
            else { return }
            content.attachments = [attachment]
        }
        task.resume()
    }

    /// Long enough for a local call, short enough to leave the download its time.
    private static let categoryTimeout: DispatchTimeInterval = .seconds(2)
}
