import FunnelbaseNotificationService

/// The whole of the extension.
///
/// Everything a notification service extension does for this platform's pushes — the receipt, the
/// buttons, the image — is in the SDK, because none of it is app-specific (docs/push.md,
/// "Rendering"). What the app supplies is the app group, which is what lets a
/// receipt recorded in this process reach the app's upload queue and be sent under the app's
/// identity.
///
/// The app group and `aps-environment` are entitlements, so a build for a device needs a real
/// developer team to sign. A simulator build needs neither, which is why the tests and the build
/// in the definition of done are simulator ones.
class NotificationService: AnalyticsNotificationService {

    override var appGroup: String? { "group.com.analytics.demo.trading" }

    // A local push provider serves the image over plain http, and Apple's transport security
    // would otherwise refuse it here even though the Info.plist allows local networking.
    override var allowInsecureImages: Bool { true }
}
