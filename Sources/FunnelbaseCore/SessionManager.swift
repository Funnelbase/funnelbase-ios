import Foundation

/// Client-side sessions: an id, and an inactivity timeout that ends one.
///
/// The same rule as Android's, because the backend derives a session's bounds from the events
/// carrying its id and cannot tell the two clients apart. There is no session-end event: the last
/// event of a session is its end.
public final class SessionManager {

    public struct Session: Equatable {
        public let id: String
        /// True when this call started the session, so `$session_start` goes in front of the event.
        public let isNew: Bool
    }

    private let defaults: UserDefaults
    private let timeout: TimeInterval
    private let lock = NSLock()

    public init(defaults: UserDefaults, timeoutMinutes: Double) {
        self.defaults = defaults
        self.timeout = timeoutMinutes * 60
    }

    /// The session an event at `now` belongs to.
    ///
    /// Judged at the event's own time rather than the clock's, so a slow upload ahead of it cannot
    /// push it across the timeout and split a visit in two.
    public func current(at now: Date) -> Session {
        lock.lock()
        defer { lock.unlock() }

        let existing = defaults.string(forKey: Keys.id)
        let lastActivity = defaults.double(forKey: Keys.lastActivity)
        let expired = existing == nil || now.timeIntervalSince1970 - lastActivity > timeout

        let id = expired ? UUID().uuidString : existing!
        defaults.set(id, forKey: Keys.id)
        defaults.set(now.timeIntervalSince1970, forKey: Keys.lastActivity)
        return Session(id: id, isNew: expired)
    }

    /// A reset: the next event starts a session of its own, so one visit never spans two people.
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: Keys.id)
        defaults.removeObject(forKey: Keys.lastActivity)
    }

    private enum Keys {
        static let id = "com.analytics.sdk.session_id"
        static let lastActivity = "com.analytics.sdk.session_last_activity"
    }
}
