import Foundation

/// Records a passive event from outside the app: the notification service extension, recording
/// that a push arrived.
///
/// The extension is a separate process, and the app may never be opened again, so the receipt has
/// to be both durable and sent: it is appended to the shared queue *and* one upload is attempted
/// straight away. Whichever succeeds, the delivery is recorded once — the event id is minted here
/// and the backend recognises a duplicate by it.
///
/// It writes rather than reuses `AnalyticsClient` because the extension must touch no session: it
/// has no business opening one, and `AnalyticsClient` exists to manage exactly that.
public struct PassiveEventWriter {

    private let defaults: UserDefaults
    private let queue: EventQueue
    private let device: DeviceContext
    private let now: () -> Date

    public init(appGroup: String?, device: DeviceContext? = nil, now: @escaping () -> Date = Date.init) {
        self.defaults = Storage.defaults(appGroup: appGroup)
        self.queue = EventQueue(url: Storage.queueUrl(appGroup: appGroup), maxEvents: 1_000)
        self.device = device ?? DeviceInfo.collect()
        self.now = now
    }

    /// For tests, and for a host that has already resolved its own storage.
    public init(defaults: UserDefaults, queue: EventQueue, device: DeviceContext, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.queue = queue
        self.device = device
        self.now = now
    }

    /// The event, queued. Returns the line written, so a caller can upload exactly it.
    @discardableResult
    public func write(_ eventName: String, properties: [String: Any?]) -> String? {
        let identity = IdentityStore(defaults: defaults)
        let event = RawEvent(
            eventId: UUID().uuidString,
            eventName: eventName,
            occurredAt: WireJson.timestamp(now()),
            // Passive: no session, so none is opened and none extended.
            sessionId: "",
            anonymousId: identity.anonymousId,
            deviceId: identity.deviceId,
            userId: identity.userId,
            properties: properties.compactMapValues(WireValue.of),
            traits: [:],
            device: device
        )
        guard let data = try? WireJson.encoder.encode(event), let line = String(data: data, encoding: .utf8) else { return nil }
        queue.enqueue(line)
        return line
    }

    /// Records a receipt and tries to send it before the extension's time runs out.
    ///
    /// A failure costs nothing: the line is already queued, and the app uploads it the next time it
    /// is opened. An upload that succeeds is removed from the queue, so the app does not send it
    /// again.
    public func recordReceipt(for payload: PushPayload, uploader: EventUploader? = nil) {
        let line = write(
            ReservedEvents.pushReceived,
            properties: [
                ReservedEvents.pushDeliveryId: payload.deliveryId,
                ReservedEvents.pushRunId: payload.runId,
            ]
        )
        guard let line else { return }

        let sender = uploader ?? credentialedUploader()
        guard let sender else { return }
        let envelope = "{\"sdk_name\":\"\(Sdk.name)\",\"sdk_version\":\"\(Sdk.version)\",\"sent_at\":\"\(WireJson.timestamp(now()))\",\"events\":[\(line)]}"
        if case .success = sender.upload(envelope) {
            // Only this line: the app's own queue may hold events the extension has no business
            // sending, and it is the app that knows whether they were accepted.
            queue.removeMatching(line)
        }
    }

    /// The uploader built from what the app left in shared storage at `initialize`.
    private func credentialedUploader() -> EventUploader? {
        guard let credentials = Storage.credentials(from: defaults),
              let config = try? AnalyticsConfig(apiKey: credentials.apiKey, endpoint: credentials.endpoint)
        else { return nil }
        return EventUploader(url: config.eventsUrl, apiKey: config.apiKey)
    }
}

private extension AnalyticsConfig {
    /// A throwing spelling of the initialiser, so bad shared credentials cannot crash an extension.
    init(apiKey: String, endpoint: String) throws {
        guard !apiKey.isEmpty, endpoint.hasPrefix("http") else {
            throw NSError(domain: "com.analytics.sdk", code: 1, userInfo: [NSLocalizedDescriptionKey: "no usable credentials in shared storage"])
        }
        self.init(apiKey: apiKey, endpoint: endpoint, flushIntervalSeconds: 0, trackApplicationLifecycle: false)
    }
}
