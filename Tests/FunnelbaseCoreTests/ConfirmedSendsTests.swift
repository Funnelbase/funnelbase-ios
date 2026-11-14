import XCTest
@testable import FunnelbaseCore

/// A push registration and a topic choice count as sent only once an upload carrying them is
/// answered with a 2xx. An upload refused for good — a `403 plan_limit` while a workspace is capped —
/// leaves them to be sent again at the next recheck, and never twice while one is still queued.
final class ConfirmedSendsTests: XCTestCase {

    private var file: URL!

    override func setUp() {
        super.setUp()
        file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jsonl")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: file)
        super.tearDown()
    }

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "test-\(UUID().uuidString)")!
    }

    private let config = AnalyticsConfig(apiKey: "k", endpoint: "https://ingest.example.com", flushIntervalSeconds: 0, flushBatchSize: 500)
    private let region = DeviceRegion(locale: "en-US", timezone: "Europe/Istanbul")

    private func client(_ uploader: EventUploader, store: UserDefaults? = nil, queue: EventQueue? = nil) -> AnalyticsClient {
        AnalyticsClient(
            config: config,
            defaults: store ?? defaults(),
            sharedDefaults: defaults(),
            queue: queue ?? EventQueue(url: file, maxEvents: 100),
            uploader: uploader,
            topics: TopicsFetcher(url: URL(string: "https://example.invalid/v1/topics")!, apiKey: "k"),
            device: DeviceContext(platform: "ios")
        )
    }

    private func register(_ client: AnalyticsClient, token: String = "tok-1") {
        client.registerPushToken(token, kind: TokenKinds.apns, status: TokenStatuses.active, region: region)
    }

    /// Hands everything over and waits for the worker to finish it, the drain included.
    private func flush(_ client: AnalyticsClient) {
        client.flush()
        client.waitForWorker()
    }

    private func events(in body: String, named name: String) -> Int {
        body.components(separatedBy: "\"event_name\":\"\(name)\"").count - 1
    }

    // MARK: - The push registration

    func testARegistrationIsConfirmedByA2xxAndNotSentAgain() {
        let uploader = ScriptedUploader(.success)
        let client = client(uploader)

        register(client)
        flush(client)
        XCTAssertEqual(uploader.bodies.count, 1)
        XCTAssertEqual(events(in: uploader.bodies[0], named: ReservedEvents.pushToken), 1)
        XCTAssertTrue(client.pushTokens.isConfirmed)

        register(client)
        flush(client)
        XCTAssertEqual(uploader.bodies.count, 1, "the server has it; the same registration is not an event per launch")
    }

    func testARegistrationRefusedForGoodIsSentAgainAtTheNextRecheck() throws {
        let uploader = ScriptedUploader(.permanent(reason: "HTTP 403"), then: .success)
        let client = client(uploader)

        register(client)
        flush(client)
        XCTAssertFalse(client.pushTokens.isConfirmed)
        XCTAssertNil(client.pushTokens.eventId, "nothing is on its way any more")

        register(client)
        flush(client)
        XCTAssertEqual(uploader.bodies.count, 2)
        XCTAssertEqual(events(in: uploader.bodies[1], named: ReservedEvents.pushToken), 1, "a new $push_token, same token")
        XCTAssertTrue(uploader.bodies[1].contains("\"token\":\"tok-1\""))
        XCTAssertTrue(client.pushTokens.isConfirmed)
    }

    func testARegistrationStillQueuedIsNotSentTwice() {
        let queue = EventQueue(url: file, maxEvents: 100)
        let client = client(ScriptedUploader(.retryable(reason: "offline")), queue: queue)

        register(client)
        flush(client)
        register(client)
        client.waitForWorker()

        XCTAssertEqual(queue.size(), 1, "the first is still waiting to go")
        XCTAssertFalse(client.pushTokens.isConfirmed)
    }

    /// An install updating from an SDK that kept no confirmation: sent once more, which heals a
    /// registration an older version may have lost.
    func testARegistrationRememberedByAnOlderSdkIsSentOnceAfterTheUpdate() {
        let store = defaults()
        store.set("tok-1", forKey: "com.analytics.sdk.push_token")
        store.set(TokenKinds.apns, forKey: "com.analytics.sdk.push_token_kind")
        store.set(TokenStatuses.active, forKey: "com.analytics.sdk.push_token_status")
        store.set(region.locale, forKey: "com.analytics.sdk.push_token_locale")
        store.set(region.timezone, forKey: "com.analytics.sdk.push_token_timezone")
        let uploader = ScriptedUploader(.success)
        let client = client(uploader, store: store)
        XCTAssertFalse(client.pushTokens.shouldSend(token: "tok-1", kind: TokenKinds.apns, status: TokenStatuses.active, region: region),
                       "nothing about it changed")

        register(client)
        flush(client)
        register(client)
        flush(client)

        XCTAssertEqual(uploader.bodies.count, 1)
        XCTAssertEqual(events(in: uploader.bodies[0], named: ReservedEvents.pushToken), 1)
        XCTAssertTrue(client.pushTokens.isConfirmed)
    }

    func testAnIdentityChangeForgetsTheRegistrationAndItsConfirmation() {
        let uploader = ScriptedUploader(.success)
        let client = client(uploader)
        register(client)
        flush(client)
        XCTAssertTrue(client.pushTokens.isConfirmed)

        client.forgetPushRegistration()
        client.waitForWorker()
        XCTAssertNil(client.pushTokens.token)
        XCTAssertFalse(client.pushTokens.isConfirmed)
        XCTAssertNil(client.pushTokens.eventId)

        register(client)
        flush(client)
        XCTAssertEqual(uploader.bodies.count, 2, "registered again, under whoever this device is now")
    }

    func testTheStoreMatchesOnlyTheEventCarryingItsRegistration() {
        let store = PushTokenStore(defaults: defaults())
        store.remember(token: "tok-1", kind: TokenKinds.apns, status: TokenStatuses.active, eventId: "e-1")

        store.confirm(acceptedLines: ["{\"event_id\":\"e-2\"}"])
        XCTAssertFalse(store.isConfirmed, "another event's success says nothing about this one")
        store.unconfirm(droppedLines: ["{\"event_id\":\"e-2\"}"])
        XCTAssertEqual(store.eventId, "e-1")
        XCTAssertFalse(store.needsResend(isQueued: { $0 == "e-1" }))
        XCTAssertTrue(store.needsResend(isQueued: { _ in false }), "lost some other way: a full queue trimmed it")

        store.confirm(acceptedLines: ["{\"event_id\":\"e-1\",\"event_name\":\"$push_token\"}"])
        XCTAssertTrue(store.isConfirmed)
        XCTAssertFalse(store.needsResend(isQueued: { _ in false }))
    }

    // MARK: - Topic choices

    func testAChoiceIsAcceptedByA2xxAndStaysPendingButIsNotSentAgain() throws {
        let store = defaults()
        let uploader = ScriptedUploader(.success)
        let client = client(uploader, store: store)

        client.setTopic("promotions", subscribed: false)
        client.waitForWorker()
        let pending = try XCTUnwrap(TopicPreferenceStore(defaults: store).pending["promotions"])
        XCTAssertTrue(pending.accepted)
        XCTAssertFalse(pending.subscribed, "still pending, for the overlay, until a fetch settles it")

        client.resendPendingTopicChoices()
        client.waitForWorker()
        XCTAssertEqual(uploader.bodies.count, 1)
    }

    func testAChoiceRefusedForGoodIsSentAgainAtTheNextRecheck() throws {
        let store = defaults()
        let uploader = ScriptedUploader(.permanent(reason: "HTTP 403"), then: .success)
        let client = client(uploader, store: store)

        client.setTopic("promotions", subscribed: false)
        client.waitForWorker()
        let refused = try XCTUnwrap(TopicPreferenceStore(defaults: store).pending["promotions"], "no longer released")
        XCTAssertFalse(refused.accepted)
        XCTAssertEqual(refused.eventId, "")

        client.resendPendingTopicChoices()
        client.waitForWorker()
        XCTAssertEqual(uploader.bodies.count, 2)
        XCTAssertEqual(events(in: uploader.bodies[1], named: ReservedEvents.topicPreference), 1)
        XCTAssertTrue(uploader.bodies[1].contains("\"topic\":\"promotions\""))
        XCTAssertTrue(uploader.bodies[1].contains("\"subscribed\":false"))
        let resent = try XCTUnwrap(TopicPreferenceStore(defaults: store).pending["promotions"])
        XCTAssertTrue(resent.accepted)
        XCTAssertFalse(resent.eventId.isEmpty)
    }

    func testAChoiceStillQueuedIsNotSentTwice() {
        let queue = EventQueue(url: file, maxEvents: 100)
        let client = client(ScriptedUploader(.retryable(reason: "offline")), queue: queue)

        client.setTopic("promotions", subscribed: false)
        client.resendPendingTopicChoices()
        client.waitForWorker()

        XCTAssertEqual(queue.size(), 1)
    }

    /// A choice stored by an older SDK has no `accepted`; it decodes as unaccepted and, with no
    /// event carrying it, goes again when the client starts.
    func testAnUnacceptedChoiceFromAnEarlierLaunchIsSentAtStartup() throws {
        let store = defaults()
        store.set(Data("{\"promotions\":{\"subscribed\":false,\"eventId\":\"e-old\"}}".utf8),
                  forKey: "com.analytics.sdk.topic_preferences_pending")
        XCTAssertEqual(TopicPreferenceStore(defaults: store).pending["promotions"],
                       .init(subscribed: false, eventId: "e-old", accepted: false))
        let queue = EventQueue(url: file, maxEvents: 100)

        let client = client(ScriptedUploader(.retryable(reason: "offline")), store: store, queue: queue)
        client.waitForWorker()

        let lines = queue.peek(10)
        XCTAssertEqual(lines.count, 1)
        let event = try WireJson.decoder.decode(RawEvent.self, from: Data(lines[0].utf8))
        XCTAssertEqual(event.eventName, ReservedEvents.topicPreference)
        XCTAssertEqual(event.properties, ["topic": .string("promotions"), "subscribed": .bool(false)])
        XCTAssertEqual(TopicPreferenceStore(defaults: store).pending["promotions"]?.eventId, event.eventId)
    }

    func testASignOutForgetsAChoiceWaitingToBeSentAgain() {
        let store = defaults()
        let uploader = ScriptedUploader(.permanent(reason: "HTTP 403"), then: .success)
        let client = client(uploader, store: store)
        client.setTopic("promotions", subscribed: false)

        client.reset()
        client.resendPendingTopicChoices()
        client.waitForWorker()

        XCTAssertTrue(TopicPreferenceStore(defaults: store).pending.isEmpty)
        XCTAssertEqual(uploader.bodies.count, 1, "the last person's choice is not sent for the next one")
    }

    // MARK: - The queue

    func testTheQueueFindsAnEventByItsId() {
        let queue = EventQueue(url: file, maxEvents: 100)
        queue.enqueue("{\"event_id\":\"e-1\",\"event_name\":\"$push_token\"}")

        XCTAssertTrue(queue.contains(eventId: "e-1"))
        XCTAssertFalse(queue.contains(eventId: "e-2"))
        queue.removeFirst(1)
        XCTAssertFalse(queue.contains(eventId: "e-1"))
    }

    // MARK: - Doubles

    /// Answers each upload with the next scripted result, the last one from then on, and keeps
    /// every body. Only ever called on the client's worker.
    private final class ScriptedUploader: EventUploader {
        private let lock = NSLock()
        private var results: [UploadResult]
        private var sent: [String] = []

        init(_ first: UploadResult, then rest: UploadResult...) {
            results = [first] + rest
            super.init(url: URL(string: "https://example.invalid/v1/events")!, apiKey: "k")
        }

        var bodies: [String] {
            lock.lock()
            defer { lock.unlock() }
            return sent
        }

        override func upload(_ body: String) -> UploadResult {
            lock.lock()
            defer { lock.unlock() }
            sent.append(body)
            return results.count > 1 ? results.removeFirst() : results[0]
        }
    }
}
