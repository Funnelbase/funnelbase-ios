import Foundation

/// The three ids of docs/event-contract.md, on disk.
///
/// `deviceId` names the install and never changes. `anonymousId` names one stretch of use and
/// restarts at every sign-out and account switch. `userId` is the account, while signed in.
///
/// Stored in `UserDefaults` — the app group's when there is one, so the notification service
/// extension records a receipt under the same identity the app is using.
public final class IdentityStore {

    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public var deviceId: String {
        lock.lock()
        defer { lock.unlock() }
        return existingOrNew(Keys.deviceId)
    }

    public var anonymousId: String {
        lock.lock()
        defer { lock.unlock() }
        return existingOrNew(Keys.anonymousId)
    }

    public var userId: String? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return defaults.string(forKey: Keys.userId)
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            if let newValue { defaults.set(newValue, forKey: Keys.userId) } else { defaults.removeObject(forKey: Keys.userId) }
        }
    }

    /// Whether this install still owes a `$first_open`.
    public var isFirstOpenPending: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !defaults.bool(forKey: Keys.firstOpenRecorded)
    }

    public func markFirstOpenRecorded() {
        lock.lock()
        defer { lock.unlock() }
        defaults.set(true, forKey: Keys.firstOpenRecorded)
    }

    /// Sign-out: a new anonymous id, no user, and the same device id — it names the install, not
    /// the person. `firstOpenRecorded` stays too: the install has been opened before.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: Keys.userId)
        defaults.set(UUID().uuidString, forKey: Keys.anonymousId)
    }

    private func existingOrNew(_ key: String) -> String {
        if let existing = defaults.string(forKey: key), !existing.isEmpty { return existing }
        let minted = UUID().uuidString
        defaults.set(minted, forKey: key)
        return minted
    }

    private typealias Keys = IdentityKeys
}

/// The keys identity is stored under, shared with `Storage.mirrorIdentity` so the copy the
/// extension reads cannot drift from the original.
public enum IdentityKeys {
    public static let deviceId = "com.analytics.sdk.device_id"
    public static let anonymousId = "com.analytics.sdk.anonymous_id"
    public static let userId = "com.analytics.sdk.user_id"
    public static let firstOpenRecorded = "com.analytics.sdk.first_open_recorded"
}
