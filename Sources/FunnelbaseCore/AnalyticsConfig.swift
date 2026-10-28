import Foundation

/// How the SDK behaves. Only the key and the endpoint have no default.
///
/// Mirrors the Android SDK's `AnalyticsConfig` field for field, so one document describes both
/// clients and a team switching platforms finds the same knobs.
public struct AnalyticsConfig: Equatable, Sendable {
    public let apiKey: String
    public let endpoint: String
    public let flushIntervalSeconds: TimeInterval
    public let flushBatchSize: Int
    public let maxQueuedEvents: Int
    public let sessionTimeoutMinutes: Double
    public let trackApplicationLifecycle: Bool
    public let debugLogging: Bool

    /// The app group both the app and its notification service extension can write to.
    ///
    /// Push needs it: the extension is a separate process, so a receipt it records can only reach
    /// the app's queue through shared storage. Without one, push still works and the receipt is
    /// sent by the extension itself or lost if that upload fails — see docs/sdk-ios.md.
    public let appGroup: String?

    public init(
        apiKey: String,
        endpoint: String,
        flushIntervalSeconds: TimeInterval = 30,
        flushBatchSize: Int = 20,
        maxQueuedEvents: Int = 1_000,
        sessionTimeoutMinutes: Double = 30,
        trackApplicationLifecycle: Bool = true,
        debugLogging: Bool = false,
        appGroup: String? = nil
    ) {
        precondition(!apiKey.isEmpty, "AnalyticsConfig needs an api key")
        precondition(endpoint.hasPrefix("http"), "AnalyticsConfig needs an http endpoint")
        precondition((1...AnalyticsConfig.maxBatchSize).contains(flushBatchSize), "flushBatchSize is 1...\(AnalyticsConfig.maxBatchSize)")
        precondition(maxQueuedEvents >= flushBatchSize, "maxQueuedEvents cannot be smaller than one batch")
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.flushIntervalSeconds = flushIntervalSeconds
        self.flushBatchSize = flushBatchSize
        self.maxQueuedEvents = maxQueuedEvents
        self.sessionTimeoutMinutes = sessionTimeoutMinutes
        self.trackApplicationLifecycle = trackApplicationLifecycle
        self.debugLogging = debugLogging
        self.appGroup = appGroup
    }

    public var eventsUrl: URL { url("v1/events") }

    /// The notification topics this app offers, and this person's choice on each.
    public var topicsUrl: URL { url("v1/topics") }

    private func url(_ path: String) -> URL {
        URL(string: endpoint.hasSuffix("/") ? "\(endpoint)\(path)" : "\(endpoint)/\(path)")!
    }

    /// The ingestion API's own per-batch limit.
    public static let maxBatchSize = 500
}
