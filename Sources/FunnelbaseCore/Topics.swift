import Foundation

/// One notification topic the app offers, and this person's choice on it, as `GET /v1/topics`
/// returns it.
///
/// `subscribed` is always an answer: the stored choice when there is one, else the topic's
/// default. `chosen` says which — false means the person never touched it.
public struct TopicChoice: Codable, Equatable, Sendable, Identifiable {
    public let key: String
    public let name: String
    public let description: String?
    public var subscribed: Bool
    public var chosen: Bool

    public var id: String { key }

    public init(key: String, name: String, description: String? = nil, subscribed: Bool, chosen: Bool) {
        self.key = key
        self.name = name
        self.description = description
        self.subscribed = subscribed
        self.chosen = chosen
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? key
        description = try container.decodeIfPresent(String.self, forKey: .description)
        subscribed = try container.decode(Bool.self, forKey: .subscribed)
        chosen = try container.decodeIfPresent(Bool.self, forKey: .chosen) ?? false
    }

    enum CodingKeys: String, CodingKey {
        case key, name, description, subscribed, chosen
    }
}

/// Why the topics could not be read. The caller shows an error and a retry; nothing is cached.
public enum TopicsError: Error, Equatable, Sendable {
    /// `Analytics.initialize` has not run, so there is no key and no endpoint to ask.
    case notInitialized
    /// The server answered, but not with a list: a 503 while the metadata store is down, a 401
    /// for a revoked key.
    case http(status: Int)
    /// No answer at all: offline, a timeout, a refused connection.
    case network(String)
    /// An answer that was not the documented shape.
    case malformed
}

/// The body of `GET /v1/topics`.
struct TopicsResponse: Decodable {
    let topics: [TopicChoice]
}

/// `GET /v1/topics`, with the same key header the events upload sends.
///
/// Asynchronous, unlike `EventUploader`: a read has no queue order to protect, and a settings
/// screen waiting on it must not wait behind a drain. `open` so a test can answer for the network.
open class TopicsFetcher {

    private let url: URL
    private let apiKey: String
    private let session: URLSession

    public init(url: URL, apiKey: String, session: URLSession? = nil) {
        self.url = url
        self.apiKey = apiKey
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 20
            configuration.waitsForConnectivity = false
            self.session = URLSession(configuration: configuration)
        }
    }

    /// The request for one person: the anonymous id always, the user id only while signed in, so
    /// the server can apply the person rule to whichever it has.
    public func request(anonymousId: String, userId: String?) -> URLRequest {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "anonymous_id", value: anonymousId)]
        if let userId, !userId.isEmpty { items.append(URLQueryItem(name: "user_id", value: userId)) }
        components.queryItems = items
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        return request
    }

    open func fetch(anonymousId: String, userId: String?, completion: @escaping (Result<[TopicChoice], TopicsError>) -> Void) {
        let task = session.dataTask(with: request(anonymousId: anonymousId, userId: userId)) { data, response, error in
            if let error {
                completion(.failure(.network(error.localizedDescription)))
                return
            }
            completion(TopicsFetcher.read(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: data))
        }
        task.resume()
    }

    /// What an answer means, apart from the network so it can be tested on its own.
    public static func read(status: Int, body: Data?) -> Result<[TopicChoice], TopicsError> {
        guard (200...299).contains(status) else { return .failure(.http(status: status)) }
        guard let body, let decoded = try? WireJson.decoder.decode(TopicsResponse.self, from: body) else {
            return .failure(.malformed)
        }
        return .success(decoded.topics)
    }
}

/// The choices made on this install that the server may not have yet.
///
/// A `$topic_preference` is queued like any event, so for a while — seconds online, days in a lift
/// — the server still answers with the old value. Shown as is, a toggle the person just flipped
/// would flip back on the next fetch. So every choice is kept here too, and **a choice kept here
/// wins over the server's value** until one of three things:
///
/// - a fetch shows the server holding the same choice (`chosen`, and the same `subscribed`): it
///   has caught up, and from then on it is the truth;
/// - the upload carrying it was rejected for good, so the server will never have it;
/// - a reset (sign-out, or a different account signing in): the choice belonged to the person who
///   left, and must not be shown to the next one.
///
/// A topic the server no longer lists is forgotten here too; the queued event still goes.
///
/// Kept in the app's own store, like identity: it describes this install's person.
public final class TopicPreferenceStore {

    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public struct Pending: Codable, Equatable, Sendable {
        public let subscribed: Bool
        /// The `$topic_preference` that carries it, so a rejected upload can release it.
        public let eventId: String
    }

    public var pending: [String: Pending] {
        lock.lock()
        defer { lock.unlock() }
        return read()
    }

    public func remember(topic: String, subscribed: Bool, eventId: String) {
        lock.lock()
        defer { lock.unlock() }
        var all = read()
        all[topic] = Pending(subscribed: subscribed, eventId: eventId)
        write(all)
    }

    /// The server's list with this install's pending choices laid over it, releasing the ones the
    /// server has caught up with or no longer lists.
    public func overlay(_ server: [TopicChoice]) -> [TopicChoice] {
        lock.lock()
        defer { lock.unlock() }
        var all = read()
        let listed = Set(server.map(\.key))
        all = all.filter { listed.contains($0.key) }
        let result: [TopicChoice] = server.map { topic in
            guard let mine = all[topic.key] else { return topic }
            if topic.chosen && topic.subscribed == mine.subscribed {
                all[topic.key] = nil
                return topic
            }
            var shown = topic
            shown.subscribed = mine.subscribed
            shown.chosen = true
            return shown
        }
        write(all)
        return result
    }

    /// An upload was rejected for good: whatever it carried will never reach the server.
    public func release(droppedLines lines: [String]) {
        lock.lock()
        defer { lock.unlock() }
        var all = read()
        guard !all.isEmpty else { return }
        let dropped = all.filter { entry in lines.contains { $0.contains("\"event_id\":\"\(entry.value.eventId)\"") } }
        guard !dropped.isEmpty else { return }
        dropped.keys.forEach { all[$0] = nil }
        write(all)
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: Self.key)
    }

    private func read() -> [String: Pending] {
        guard let data = defaults.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([String: Pending].self, from: data)
        else { return [:] }
        return decoded
    }

    private func write(_ all: [String: Pending]) {
        if all.isEmpty {
            defaults.removeObject(forKey: Self.key)
        } else if let data = try? JSONEncoder().encode(all) {
            defaults.set(data, forKey: Self.key)
        }
    }

    private static let key = "com.analytics.sdk.topic_preferences_pending"
}
