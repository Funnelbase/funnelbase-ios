import Foundation

/// Where the phone is set to: the language a template's copy is chosen by, and the clock its dates
/// are shown in. Part of a registration because the registry is where a run reads them from.
public struct DeviceRegion: Equatable, Sendable {
    public var locale: String
    public var timezone: String

    public init(locale: String = "", timezone: String = "") {
        self.locale = locale
        self.timezone = timezone
    }
}

/// The last push registration this install sent, so the next one says something new or is not sent.
///
/// Identical in behaviour to the Android store: the token is an event, sent on refresh, at every
/// identify and reset, and whenever the notification permission changes, which unchecked would be
/// an event per launch.
///
/// A registration is remembered when its `$push_token` is queued, but it is **confirmed** only when
/// an upload carrying that event is answered with a 2xx. An upload refused for good (any 4xx but a
/// 429 — a `403 plan_limit` while a workspace is capped, say) leaves it unconfirmed, and the next
/// recheck (`AnalyticsClient.registerPushToken`) sends it again once its event is no longer queued.
/// An install that updated from an SDK that kept no confirmation has none stored, which reads as
/// unconfirmed: it registers once more after the update, which heals a registration lost before.
public final class PushTokenStore {

    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public var token: String? {
        lock.lock()
        defer { lock.unlock() }
        return defaults.string(forKey: Keys.token)
    }

    public var kind: String? {
        lock.lock()
        defer { lock.unlock() }
        return defaults.string(forKey: Keys.kind)
    }

    /// A new token, another kind, a flipped permission — or a phone now set to another language or
    /// time zone, which the registry would otherwise keep sending the old copy by.
    public func shouldSend(token: String, kind: String, status: String, region: DeviceRegion = DeviceRegion()) -> Bool {
        guard !token.trimmed.isEmpty else { return false }
        lock.lock()
        defer { lock.unlock() }
        return token != defaults.string(forKey: Keys.token)
            || kind != defaults.string(forKey: Keys.kind)
            || status != defaults.string(forKey: Keys.status)
            || region.locale != defaults.string(forKey: Keys.locale)
            || region.timezone != defaults.string(forKey: Keys.timezone)
    }

    /// What was just queued, unconfirmed, with the `$push_token` that carries it.
    public func remember(token: String, kind: String, status: String, region: DeviceRegion = DeviceRegion(), eventId: String? = nil) {
        lock.lock()
        defer { lock.unlock() }
        defaults.set(token, forKey: Keys.token)
        defaults.set(kind, forKey: Keys.kind)
        defaults.set(status, forKey: Keys.status)
        defaults.set(region.locale, forKey: Keys.locale)
        defaults.set(region.timezone, forKey: Keys.timezone)
        if let eventId {
            defaults.set(eventId, forKey: Keys.eventId)
        } else {
            defaults.removeObject(forKey: Keys.eventId)
        }
        defaults.set(false, forKey: Keys.confirmed)
    }

    /// The `$push_token` that carries the remembered registration, while it may still be queued.
    public var eventId: String? {
        lock.lock()
        defer { lock.unlock() }
        return defaults.string(forKey: Keys.eventId)
    }

    /// Whether the server has answered an upload carrying the remembered registration with a 2xx.
    /// Missing — an install from an older SDK — is false.
    public var isConfirmed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return defaults.bool(forKey: Keys.confirmed)
    }

    /// An upload succeeded: if it carried the remembered registration, the server has it.
    public func confirm(acceptedLines lines: [String]) {
        lock.lock()
        defer { lock.unlock() }
        guard let eventId = defaults.string(forKey: Keys.eventId), lines.contains(where: { $0.contains(Self.marker(eventId)) }) else { return }
        defaults.set(true, forKey: Keys.confirmed)
    }

    /// An upload was refused for good: if it carried the remembered registration, the server will
    /// never have it, so it stays unconfirmed with no event waiting, and the next recheck resends it.
    public func unconfirm(droppedLines lines: [String]) {
        lock.lock()
        defer { lock.unlock() }
        guard let eventId = defaults.string(forKey: Keys.eventId), lines.contains(where: { $0.contains(Self.marker(eventId)) }) else { return }
        defaults.removeObject(forKey: Keys.eventId)
        defaults.set(false, forKey: Keys.confirmed)
    }

    /// A remembered registration the server does not have and no queued event is carrying: the
    /// event was dropped, or it predates the confirmation. `isQueued` asks the queue about an id.
    public func needsResend(isQueued: (String) -> Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let token = defaults.string(forKey: Keys.token), !token.trimmed.isEmpty else { return false }
        guard !defaults.bool(forKey: Keys.confirmed) else { return false }
        guard let eventId = defaults.string(forKey: Keys.eventId) else { return true }
        return !isQueued(eventId)
    }

    /// A reset: the same token is registered again, under the new identity.
    public func forget() {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: Keys.token)
        defaults.removeObject(forKey: Keys.kind)
        defaults.removeObject(forKey: Keys.status)
        defaults.removeObject(forKey: Keys.locale)
        defaults.removeObject(forKey: Keys.timezone)
        defaults.removeObject(forKey: Keys.eventId)
        defaults.removeObject(forKey: Keys.confirmed)
    }

    /// How a serialized event names its id, the same match a dropped topic choice is found by.
    static func marker(_ eventId: String) -> String { "\"event_id\":\"\(eventId)\"" }

    public static func statusFor(enabled: Bool) -> String {
        enabled ? TokenStatuses.active : TokenStatuses.disabled
    }

    /// An Apple device token as APNs writes it: lowercase hex, no separators.
    public static func hex(_ token: Data) -> String {
        token.map { String(format: "%02x", $0) }.joined()
    }

    private enum Keys {
        static let token = "com.analytics.sdk.push_token"
        static let kind = "com.analytics.sdk.push_token_kind"
        static let status = "com.analytics.sdk.push_token_status"
        static let locale = "com.analytics.sdk.push_token_locale"
        static let timezone = "com.analytics.sdk.push_token_timezone"
        static let eventId = "com.analytics.sdk.push_token_event_id"
        static let confirmed = "com.analytics.sdk.push_token_confirmed"
    }
}
