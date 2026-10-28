import Foundation

/// Everything the SDK actually does. `Analytics` is a thin facade over one instance.
///
/// All work happens on one serial queue. A caller's thread does nothing but capture when the event
/// happened and hand it over, so an app never pays for serialization, disk or network on a frame.
///
/// Identity and session are read on that queue too, in queue order: an event tracked right after a
/// sign-out must see the cleared identity, not the one the calling thread still had.
public final class AnalyticsClient {

    private let config: AnalyticsConfig
    private let identity: IdentityStore
    private let sessions: SessionManager
    private let queue: EventQueue
    private let uploader: EventUploader
    private let topics: TopicsFetcher
    private let topicChoices: TopicPreferenceStore
    private let device: DeviceContext
    /// Read per event over [device]'s locale and time zone; nil where a test fixed the device.
    private let region: (() -> DeviceRegion)?
    private let installedAtMillis: Int?
    private let work = DispatchQueue(label: "com.analytics.sdk", qos: .utility)
    private var timer: DispatchSourceTimer?
    private let now: () -> Date

    /// The shared store, kept so identity can be mirrored again whenever it changes.
    private let shared: UserDefaults

    public init(
        config: AnalyticsConfig,
        defaults: UserDefaults? = nil,
        sharedDefaults: UserDefaults? = nil,
        queue: EventQueue? = nil,
        uploader: EventUploader? = nil,
        topics: TopicsFetcher? = nil,
        device: DeviceContext? = nil,
        region: (() -> DeviceRegion)? = nil,
        installedAtMillis: Int? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        // Identity and sessions in the app's own store, which a reinstall clears; the queue and
        // the credentials in the shared one, which the extension can read.
        let store = defaults ?? Storage.appDefaults()
        let shared = sharedDefaults ?? Storage.defaults(appGroup: config.appGroup)
        self.config = config
        self.shared = shared
        self.identity = IdentityStore(defaults: store)
        self.sessions = SessionManager(defaults: store, timeoutMinutes: config.sessionTimeoutMinutes)
        self.queue = queue ?? EventQueue(url: Storage.queueUrl(appGroup: config.appGroup), maxEvents: config.maxQueuedEvents)
        self.uploader = uploader ?? EventUploader(url: config.eventsUrl, apiKey: config.apiKey, debugLogging: config.debugLogging)
        self.topics = topics ?? TopicsFetcher(url: config.topicsUrl, apiKey: config.apiKey)
        self.topicChoices = TopicPreferenceStore(defaults: store)
        self.device = device ?? DeviceInfo.collect()
        self.region = region ?? (device == nil ? DeviceInfo.region : nil)
        self.installedAtMillis = installedAtMillis ?? DeviceInfo.installedAtMillis()
        self.now = now

        // What the extension needs: the credentials to upload a receipt itself, and who this
        // install is so the receipt is recorded under the right person.
        Storage.writeCredentials(apiKey: config.apiKey, endpoint: config.endpoint, into: shared)
        Storage.mirrorIdentity(from: identity, into: shared)
        startTimer()
    }

    // MARK: - Recording

    public func track(_ eventName: String, properties: [String: Any?] = [:]) {
        let occurredAt = now()
        work.async { [weak self] in
            self?.record(eventName, occurredAt: occurredAt, properties: properties, traits: [:], userId: self?.identity.userId)
        }
    }

    /// Sign-in, sign-up, or the re-identify of a launch while signed in. The `$identify` carries
    /// the anonymous id and the user id together, and that is the link between them: there is no
    /// alias, and nothing else to call.
    public func identify(_ userId: String, traits: [String: Any?] = [:]) {
        let occurredAt = now()
        work.async { [weak self] in
            guard let self else { return }
            let current = self.identity.userId
            // A different account is a reset: the new one gets an anonymous id that links to it
            // alone, and the old one keeps everything it did.
            if let current, current != userId { self.startFresh() }
            self.identity.userId = userId
            Storage.mirrorIdentity(from: self.identity, into: self.shared)
            self.record(ReservedEvents.identify, occurredAt: occurredAt, properties: [:], traits: traits, userId: userId)
        }
    }

    /// An event nobody acted on — a refreshed push token, a push arriving in the background.
    ///
    /// It carries no session, so it opens none and extends none: a push at three in the morning
    /// must not make that a visit. `$first_open` is skipped for the same reason.
    public func trackPassive(_ eventName: String, properties: [String: Any?] = [:]) {
        let occurredAt = now()
        work.async { [weak self] in
            guard let self else { return }
            self.enqueue(
                self.buildEvent(eventName, occurredAt: occurredAt, sessionId: "", properties: properties, traits: [:], userId: self.identity.userId)
            )
            self.drainIfFull()
        }
    }

    // MARK: - Notification topics

    /// Switches one notification topic on or off for whoever this install is now.
    ///
    /// A passive `$topic_preference`, queued and retried like every event, and kept as a pending
    /// choice so the next `fetchTopics` shows it before the server has it (`TopicPreferenceStore`).
    public func setTopic(_ key: String, subscribed: Bool) {
        let topic = key.trimmed
        guard !topic.isEmpty else {
            print("[Analytics] a topic needs a key — ignoring")
            return
        }
        let occurredAt = now()
        work.async { [weak self] in
            guard let self else { return }
            let event = self.buildEvent(
                ReservedEvents.topicPreference,
                occurredAt: occurredAt,
                sessionId: "",
                properties: [
                    ReservedEvents.topicPreferenceTopic: topic,
                    ReservedEvents.topicPreferenceSubscribed: subscribed,
                ],
                traits: [:],
                userId: self.identity.userId
            )
            self.topicChoices.remember(topic: topic, subscribed: subscribed, eventId: event.eventId)
            self.enqueue(event)
            // Sent now rather than at the next interval: the server has to know before the next
            // campaign is sent, and a settings screen is a moment the person is waiting anyway.
            self.drain()
        }
    }

    /// The app's active topics and this person's choice on each, with this install's pending
    /// choices laid over the server's answer. The completion runs on the main queue.
    ///
    /// Identity is read on the worker, in queue order, so a fetch right after a sign-out asks
    /// about the new person and not the one who left.
    public func fetchTopics(completion: @escaping (Result<[TopicChoice], TopicsError>) -> Void) {
        work.async { [weak self] in
            guard let self else { return }
            let anonymousId = self.identity.anonymousId
            let userId = self.identity.userId
            self.topics.fetch(anonymousId: anonymousId, userId: userId) { [weak self] result in
                guard let self else { return }
                // Back through the worker, so a choice set while the request was in flight is
                // already in the store when the answer is overlaid.
                self.work.async {
                    let delivered = result.map { self.topicChoices.overlay($0) }
                    DispatchQueue.main.async { completion(delivered) }
                }
            }
        }
    }

    public func flush() {
        work.async { [weak self] in self?.drain() }
    }

    /// Logout. Uploads what is already queued before clearing identity — those events belong to the
    /// person who is leaving, and dropping them would lose the end of their session.
    public func reset() {
        work.async { [weak self] in self?.startFresh() }
    }

    // MARK: - The worker's own

    /// Worker queue only.
    private func record(
        _ eventName: String,
        occurredAt: Date,
        properties: [String: Any?],
        traits: [String: Any?],
        userId: String?
    ) {
        let session = sessions.current(at: occurredAt)

        // A new session's start has to be enqueued before the event that opened it, or the
        // session's first event precedes its own start.
        if session.isNew {
            enqueue(buildEvent(ReservedEvents.sessionStart, occurredAt: occurredAt, sessionId: session.id, properties: [:], traits: [:], userId: userId))
        }
        // Once per install, in front of its first event and after that session's start. Checked on
        // its own rather than under `isNew`: an install that updated into this SDK may still be
        // inside a session the old version persisted.
        if identity.isFirstOpenPending {
            let properties: [String: Any?] = installedAtMillis.map { [ReservedEvents.firstOpenInstalledAtMs: $0] } ?? [:]
            enqueue(buildEvent(ReservedEvents.firstOpen, occurredAt: occurredAt, sessionId: session.id, properties: properties, traits: [:], userId: userId))
            // Marked after the enqueue: a crash between the two costs a duplicate, the other order
            // costs the install its only one.
            identity.markFirstOpenRecorded()
        }
        enqueue(buildEvent(eventName, occurredAt: occurredAt, sessionId: session.id, properties: properties, traits: traits, userId: userId))
        drainIfFull()
    }

    /// Worker queue only. A new anonymous id and a new session, so one visit never spans two people.
    private func startFresh() {
        drain()
        identity.reset()
        sessions.clear()
        // Choices still on their way belong to the person who left; the next one sees their own.
        topicChoices.clear()
        // The extension must not keep recording under the person who just left.
        Storage.mirrorIdentity(from: identity, into: shared)
    }

    private func buildEvent(
        _ eventName: String,
        occurredAt: Date,
        sessionId: String,
        properties: [String: Any?],
        traits: [String: Any?],
        userId: String?
    ) -> RawEvent {
        RawEvent(
            // Made here so a retried upload carries the same id and the backend recognises the
            // duplicate.
            eventId: UUID().uuidString,
            eventName: eventName,
            occurredAt: WireJson.timestamp(occurredAt),
            sessionId: sessionId,
            anonymousId: identity.anonymousId,
            deviceId: identity.deviceId,
            userId: userId,
            properties: properties.compactMapValues(WireValue.of),
            traits: traits.compactMapValues(WireValue.of),
            device: currentDevice()
        )
    }

    /// The device as it is now: the startup context, with the language and time zone read again.
    private func currentDevice() -> DeviceContext {
        guard let region = region?() else { return device }
        var now = device
        now.locale = region.locale
        now.timezone = region.timezone
        return now
    }

    private func enqueue(_ event: RawEvent) {
        guard let data = try? WireJson.encoder.encode(event), let line = String(data: data, encoding: .utf8) else { return }
        queue.enqueue(line)
    }

    private func drainIfFull() {
        if queue.size() >= config.flushBatchSize { drain() }
    }

    /// Uploads batch after batch until the queue drains or an upload fails.
    ///
    /// Events are removed only once the server has them, so a dropped connection costs a retry
    /// rather than data. Synchronous on the worker queue on purpose: two drains must never overlap.
    private func drain() {
        while true {
            let lines = queue.peek(config.flushBatchSize)
            if lines.isEmpty { return }

            switch uploader.upload(batchEnvelope(lines)) {
            case .success:
                queue.removeFirst(lines.count)
                log("Uploaded \(lines.count) events, \(queue.size()) still queued")
            case .retryable(let reason):
                log("Upload deferred (\(reason)); \(queue.size()) events still queued")
                return
            case .permanent(let reason):
                // Dropped deliberately: these will never be accepted, and keeping them blocks
                // every event behind them forever.
                print("[Analytics] dropping \(lines.count) events the server rejected: \(reason)")
                queue.removeFirst(lines.count)
                // A topic choice among them will never reach the server, so it stops overriding it.
                topicChoices.release(droppedLines: lines)
            }
        }
    }

    /// The batch envelope, with the already-serialized lines spliced in as raw JSON: they came off
    /// disk in exactly the shape the server expects, and a round trip would spend a phone's CPU
    /// producing identical bytes.
    private func batchEnvelope(_ lines: [String]) -> String {
        "{\"sdk_name\":\"\(Sdk.name)\",\"sdk_version\":\"\(Sdk.version)\",\"sent_at\":\"\(WireJson.timestamp(now()))\",\"events\":[\(lines.joined(separator: ","))]}"
    }

    private func startTimer() {
        guard config.flushIntervalSeconds > 0 else { return }
        let timer = DispatchSource.makeTimerSource(queue: work)
        timer.schedule(deadline: .now() + config.flushIntervalSeconds, repeating: config.flushIntervalSeconds)
        timer.setEventHandler { [weak self] in self?.drain() }
        timer.resume()
        self.timer = timer
    }

    private func log(_ message: String) {
        if config.debugLogging { print("[Analytics] \(message)") }
    }
}
