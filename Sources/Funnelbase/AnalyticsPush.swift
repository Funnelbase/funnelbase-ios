import Foundation
import FunnelbaseCore
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

/// A tap, handed to the app: the push, and which button was tapped, or nil for the notification
/// itself. Return true to say the app has routed it.
public typealias PushTapHandler = (PushPayload, String?) -> Bool

/// Push, as the SDK sees it: a token to register, a receipt to report, and a tap to report
/// (docs/push.md, "Rendering").
///
/// The SDK knows nothing about Firebase or APNs. Whoever holds the token hands it over, so an app
/// on Firebase, on Apple directly, or on a gateway of its own all work the same way. Reached as
/// `Analytics.push`.
///
/// Rendering on Apple devices is not here: Apple draws the notification from the payload, and the
/// image and the buttons are the notification service extension's work, which runs in its own
/// process before the banner appears. See `AnalyticsNotificationService`.
public final class AnalyticsPush {

    public static let shared = AnalyticsPush()

    private let lock = NSLock()
    private var client: AnalyticsClient?
    private var tokens: PushTokenStore?
    private var handler: PushTapHandler?
    private var observers: [NSObjectProtocol] = []

    private init() {}

    internal func attach(client: AnalyticsClient, appGroup: String?) {
        lock.lock()
        defer { lock.unlock() }
        self.client = client
        // The app's own store, not the group's: a group container survives the app being deleted,
        // and a remembered registration is one the SDK would never send again.
        self.tokens = PushTokenStore(defaults: Storage.appDefaults())
        // The registry holds the phone's language and time zone, and a run picks a template's copy
        // by them — so a change to either is registered at the next launch without the app asking,
        // and while the app runs, when the system says one changed.
        if observers.isEmpty {
            let center = NotificationCenter.default
            observers = [NSLocale.currentLocaleDidChangeNotification, .NSSystemTimeZoneDidChange].map { name in
                center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in self?.refreshToken() }
            }
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in self?.refreshToken() }
    }

    // MARK: - The token

    /// Registers this install's push token, sending `$push_token` when it says something the
    /// registry does not already know. Safe to call on every launch.
    public func setToken(_ token: String, kind: String = TokenKinds.fcm) {
        withAuthorization { [weak self] status in
            self?.send(token: token, kind: kind, status: status)
        }
    }

    /// The same, for an Apple device token as `didRegisterForRemoteNotificationsWithDeviceToken`
    /// hands it over: raw bytes, which APNs addresses as lowercase hex.
    public func setAPNSToken(_ token: Data) {
        setToken(PushTokenStore.hex(token), kind: TokenKinds.apns)
    }

    /// Re-registers the last token if the notification permission, the phone's language or its time
    /// zone has changed under it. The SDK calls it at startup and when the language or time zone
    /// changes; call it after asking for permission, and on returning to the foreground if the app
    /// cares.
    public func refreshToken() {
        guard let token = tokens?.token else { return }
        setToken(token, kind: tokens?.kind ?? TokenKinds.fcm)
    }

    /// The token last registered, for a settings or debug screen.
    public func registeredToken() -> String? { tokens?.token }

    /// A sign-in, an account switch or a sign-out: the registration is sent again, to be joined to
    /// whoever this device is now.
    internal func identityChanged() {
        guard let tokens, let token = tokens.token else { return }
        let kind = tokens.kind ?? TokenKinds.fcm
        tokens.forget()
        setToken(token, kind: kind)
    }

    // MARK: - Asking, and being asked

    /// Asks for permission and registers the answer. Sugar: an app may ask on its own and call
    /// `refreshToken` instead, and one that wants a considered prompt should.
    public func requestAuthorization(
        options: UNAuthorizationOptions = [.alert, .sound, .badge],
        completion: ((Bool) -> Void)? = nil
    ) {
        UNUserNotificationCenter.current().requestAuthorization(options: options) { [weak self] granted, _ in
            self?.refreshToken()
            #if canImport(UIKit) && !os(macOS)
            if granted {
                DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
            }
            #endif
            completion?(granted)
        }
    }

    /// Whether notifications are allowed right now. Apple answers asynchronously, always.
    public func notificationsEnabled(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            completion(AnalyticsPush.allowed(settings.authorizationStatus))
        }
    }

    // MARK: - Receipt and tap

    /// Reports that a push arrived, for an app that receives one itself — in the foreground, or
    /// through a background refresh. The extension reports the ones that arrive while the app is
    /// not running, so this is not the usual path.
    ///
    /// False, having done nothing, when the notification is not ours.
    @discardableResult
    public func handleNotification(userInfo: [AnyHashable: Any]) -> Bool {
        guard let payload = PushParser.parse(userInfo) else { return false }
        client?.trackPassive(
            ReservedEvents.pushReceived,
            properties: [
                ReservedEvents.pushDeliveryId: payload.deliveryId,
                ReservedEvents.pushRunId: payload.runId,
            ]
        )
        return true
    }

    /// Reports a tap and hands it to the app. Call it from
    /// `userNotificationCenter(_:didReceive:withCompletionHandler:)`; the payload comes back so the
    /// app can route, which the SDK will not do for it.
    @discardableResult
    public func handle(response: UNNotificationResponse) -> PushPayload? {
        let userInfo = response.notification.request.content.userInfo
        guard let payload = PushParser.parse(userInfo) else { return nil }

        // A dismissal is not an open: the person put it away without acting.
        guard response.actionIdentifier != UNNotificationDismissActionIdentifier else { return payload }

        let actionId = response.actionIdentifier == UNNotificationDefaultActionIdentifier ? nil : response.actionIdentifier
        reportOpen(payload: payload, actionId: actionId)
        _ = handler?(payload, actionId)
        return payload
    }

    /// The open, on its own, for an app that reads the response itself.
    public func reportOpen(payload: PushPayload, actionId: String?) {
        var properties: [String: Any?] = [
            ReservedEvents.pushDeliveryId: payload.deliveryId,
            ReservedEvents.pushRunId: payload.runId,
        ]
        if let actionId, !actionId.isEmpty { properties[ReservedEvents.pushActionId] = actionId }
        client?.track(ReservedEvents.pushOpened, properties: properties)
    }

    /// Registers the app's router for taps, or clears it with nil.
    public func setTapHandler(_ handler: PushTapHandler?) {
        lock.lock()
        defer { lock.unlock() }
        self.handler = handler
    }

    // MARK: - Internals

    private func send(token: String, kind: String, status: String) {
        guard let tokens, let client else { return }
        let region = DeviceInfo.region()
        guard tokens.shouldSend(token: token, kind: kind, status: status, region: region) else { return }
        tokens.remember(token: token, kind: kind, status: status, region: region)
        client.trackPassive(
            ReservedEvents.pushToken,
            properties: [
                ReservedEvents.pushTokenToken: token,
                ReservedEvents.pushTokenKind: kind,
                ReservedEvents.pushTokenStatus: status,
            ]
        )
    }

    private func withAuthorization(_ body: @escaping (String) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            body(PushTokenStore.statusFor(enabled: AnalyticsPush.allowed(settings.authorizationStatus)))
        }
    }

    /// Provisional counts as allowed: a quiet notification is still delivered. So does the
    /// ephemeral grant an App Clip gets, where that exists.
    private static func allowed(_ status: UNAuthorizationStatus) -> Bool {
        if status == .authorized || status == .provisional { return true }
        #if os(iOS)
        if #available(iOS 14.0, *), status == .ephemeral { return true }
        #endif
        return false
    }
}
