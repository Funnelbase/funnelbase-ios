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

    public func remember(token: String, kind: String, status: String, region: DeviceRegion = DeviceRegion()) {
        lock.lock()
        defer { lock.unlock() }
        defaults.set(token, forKey: Keys.token)
        defaults.set(kind, forKey: Keys.kind)
        defaults.set(status, forKey: Keys.status)
        defaults.set(region.locale, forKey: Keys.locale)
        defaults.set(region.timezone, forKey: Keys.timezone)
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
    }

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
    }
}
