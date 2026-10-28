import Foundation
import FunnelbaseCore

/// Notification topics: the short list of kinds of message an app sends (`promotions`,
/// `price_alerts`), each of which a person may switch off. A campaign filed under a topic skips
/// everyone who has. Reached as `Analytics.topics`; the Android SDK's `Analytics.topics` has the
/// same two methods.
///
/// The list is the app's, managed in the dashboard, so an app never hard-codes it: it asks with
/// `fetch` and renders what comes back. A choice is the person's, not the device's — the server
/// applies the person rule, so a choice made signed out follows the account once they sign in.
///
/// iOS has no per-kind notification switch of its own to consult, so nothing here reads the
/// system settings: whether push is allowed at all is still `Analytics.push.notificationsEnabled`.
public final class AnalyticsTopics {

    public static let shared = AnalyticsTopics()

    private let lock = NSLock()
    private var client: AnalyticsClient?

    private init() {}

    internal func attach(client: AnalyticsClient) {
        lock.lock()
        defer { lock.unlock() }
        self.client = client
    }

    /// Switches one topic on or off for whoever is using the app now. Queued, and kept offline
    /// like every event; `fetch` shows it straight away, before the server has it.
    public func set(_ key: String, subscribed: Bool) {
        guard let client = current() else {
            print("[Analytics] topics.set called before initialize() — ignoring")
            return
        }
        client.setTopic(key, subscribed: subscribed)
    }

    /// The app's active topics and this person's choice on each. The completion runs on the main
    /// queue; a failure (offline, a 503) is the caller's to show with a retry.
    public func fetch(completion: @escaping (Result<[TopicChoice], Error>) -> Void) {
        guard let client = current() else {
            DispatchQueue.main.async { completion(.failure(TopicsError.notInitialized)) }
            return
        }
        client.fetchTopics { result in completion(result.mapError { $0 as Error }) }
    }

    /// The same, for a caller in `async` code.
    public func fetch() async throws -> [TopicChoice] {
        try await withCheckedThrowingContinuation { continuation in
            fetch { continuation.resume(with: $0) }
        }
    }

    private func current() -> AnalyticsClient? {
        lock.lock()
        defer { lock.unlock() }
        return client
    }
}
