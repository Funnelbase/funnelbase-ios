import Foundation

/// What became of an upload, and therefore what to do with the events.
public enum UploadResult: Equatable, Sendable {
    /// The server has them; drop them from the queue.
    case success
    /// Worth trying again: no network, a 429, or a 5xx. The events stay queued.
    case retryable(reason: String)
    /// Never going to be accepted: a bad key, a malformed batch. Dropped, or they block the queue
    /// behind them forever.
    case permanent(reason: String)

    /// The rule both clients apply, in one place so a status code cannot be read two ways.
    public static func forStatus(_ status: Int) -> UploadResult {
        switch status {
        case 200...299: return .success
        case 429, 500...599: return .retryable(reason: "HTTP \(status)")
        default: return .permanent(reason: "HTTP \(status)")
        }
    }
}

/// One POST of one batch.
///
/// `URLSession` rather than anything larger: this sends one request shape to one endpoint. The
/// body is the batch envelope, already assembled as text by the client.
///
/// Deliberately synchronous. It is only ever called from the SDK's own serial queue, where one
/// upload at a time is the guarantee the queue's ordering rests on, and `async` there would let
/// two drains interleave.
open class EventUploader {

    private let url: URL
    private let apiKey: String
    private let debugLogging: Bool
    private let session: URLSession

    public init(url: URL, apiKey: String, debugLogging: Bool = false, session: URLSession? = nil) {
        self.url = url
        self.apiKey = apiKey
        self.debugLogging = debugLogging
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 20
            configuration.waitsForConnectivity = false
            self.session = URLSession(configuration: configuration)
        }
    }

    open func upload(_ body: String) -> UploadResult {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        request.httpBody = body.data(using: .utf8)

        let outcome = Outcome()
        let waiting = DispatchSemaphore(value: 0)
        let task = session.dataTask(with: request) { data, response, error in
            if let error {
                outcome.value = .retryable(reason: error.localizedDescription)
            } else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                outcome.value = UploadResult.forStatus(status)
                if self.debugLogging, let data, let text = String(data: data, encoding: .utf8), text.contains("rejected") {
                    // Accepted and rejected events arrive together: a batch is not all or nothing.
                    print("[Analytics] the server rejected part of a batch: \(text)")
                }
            }
            waiting.signal()
        }
        task.resume()
        waiting.wait()
        return outcome.value
    }

    /// A result written on the session's thread and read on the caller's.
    private final class Outcome: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: UploadResult = .retryable(reason: "no answer")

        var value: UploadResult {
            get {
                lock.lock()
                defer { lock.unlock() }
                return stored
            }
            set {
                lock.lock()
                defer { lock.unlock() }
                stored = newValue
            }
        }
    }
}
