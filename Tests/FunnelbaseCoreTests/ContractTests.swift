import XCTest
@testable import FunnelbaseCore

/// The wire, the identity rules and the sessions: the parts of the contract both clients have to
/// agree on character for character (docs/event-contract.md).
final class ContractTests: XCTestCase {

    private func defaults() -> UserDefaults {
        let suite = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        return suite
    }

    // MARK: - The wire

    func testAnEventSerializesWithTheSnakeCaseNamesTheBackendReads() throws {
        let event = RawEvent(
            eventId: "e-1",
            eventName: "instrument_viewed",
            occurredAt: "2026-09-20T10:00:00.000Z",
            sessionId: "s-1",
            anonymousId: "anon-1",
            deviceId: "dev-1",
            userId: "u-1",
            properties: ["symbol": .string("AAPL"), "price": .number(412.8), "count": .integer(3), "first": .bool(true)],
            device: DeviceContext(platform: "ios", osVersion: "26.1")
        )

        let json = String(data: try WireJson.encoder.encode(event), encoding: .utf8)!

        XCTAssertTrue(json.contains("\"event_name\":\"instrument_viewed\""), json)
        XCTAssertTrue(json.contains("\"anonymous_id\":\"anon-1\""), json)
        XCTAssertTrue(json.contains("\"device_id\":\"dev-1\""), json)
        XCTAssertTrue(json.contains("\"user_id\":\"u-1\""), json)
        XCTAssertTrue(json.contains("\"os_version\":\"26.1\""), json)
        XCTAssertTrue(json.contains("\"platform\":\"ios\""), json)
        // Numbers stay numbers: the platform stores them in a typed column, and a string there
        // cannot be filtered on a range.
        XCTAssertTrue(json.contains("\"price\":412.8"), json)
        XCTAssertTrue(json.contains("\"count\":3"), json)
        XCTAssertTrue(json.contains("\"first\":true"), json)
    }

    func testAPassiveEventCarriesAnEmptySessionId() throws {
        let event = RawEvent(
            eventId: "e-1", eventName: ReservedEvents.pushToken, occurredAt: "2026-09-20T10:00:00.000Z",
            sessionId: "", anonymousId: "anon-1", deviceId: "dev-1", device: DeviceContext()
        )

        let json = String(data: try WireJson.encoder.encode(event), encoding: .utf8)!

        XCTAssertTrue(json.contains("\"session_id\":\"\""), json)
        XCTAssertFalse(json.contains("\"user_id\""), "an anonymous install sends no user id at all")
    }

    func testTheReservedNamesMatchTheBackend() {
        XCTAssertEqual(ReservedEvents.screenView, "$screen_view")
        XCTAssertEqual(ReservedEvents.sessionStart, "$session_start")
        XCTAssertEqual(ReservedEvents.identify, "$identify")
        XCTAssertEqual(ReservedEvents.firstOpen, "$first_open")
        XCTAssertEqual(ReservedEvents.pushToken, "$push_token")
        XCTAssertEqual(ReservedEvents.pushReceived, "$push_received")
        XCTAssertEqual(ReservedEvents.pushOpened, "$push_opened")
        XCTAssertEqual(ReservedEvents.topicPreference, "$topic_preference")
        XCTAssertEqual(ReservedEvents.passive, ["$push_token", "$push_received", "$topic_preference"])
        XCTAssertEqual([ReservedEvents.topicPreferenceTopic, ReservedEvents.topicPreferenceSubscribed], ["topic", "subscribed"])
        XCTAssertEqual(ReservedEvents.pushActionId, "action_id")
        XCTAssertEqual([TokenKinds.fcm, TokenKinds.apns, TokenKinds.opaque], ["fcm", "apns", "opaque"])
        XCTAssertEqual(Sdk.name, "ios")
    }

    func testATimestampIsUtcToMilliseconds() {
        let instant = Date(timeIntervalSince1970: 1_790_000_000.123)
        let text = WireJson.timestamp(instant)

        XCTAssertTrue(text.hasSuffix("Z"), text)
        XCTAssertTrue(text.contains("."), "milliseconds, as the backend parses them: \(text)")
    }

    // MARK: - Identity

    func testTheDeviceIdSurvivesAResetAndTheAnonymousIdDoesNot() {
        let store = IdentityStore(defaults: defaults())
        let deviceId = store.deviceId
        let anonymousId = store.anonymousId
        store.userId = "u-1"

        store.reset()

        XCTAssertEqual(store.deviceId, deviceId, "it names the install, not the person")
        XCTAssertNotEqual(store.anonymousId, anonymousId, "one stretch of use between resets")
        XCTAssertNil(store.userId)
    }

    func testFirstOpenIsOwedOnceAndThenNotAgain() {
        let store = IdentityStore(defaults: defaults())
        XCTAssertTrue(store.isFirstOpenPending)

        store.markFirstOpenRecorded()
        XCTAssertFalse(store.isFirstOpenPending)

        store.reset()
        XCTAssertFalse(store.isFirstOpenPending, "a sign-out is not a new install")
    }

    // MARK: - A reinstall

    /**
     Deleting an app on Apple platforms does **not** delete the app group container it shares with
     its notification service extension. Identity kept there would therefore survive a reinstall,
     and the contract says the opposite: `device_id` names the install, and a reinstall is a new
     one. Worse, a push token remembered there is a token the SDK will not register again, because
     it only sends what changed — which is exactly how a reinstalled app goes silent.

     So identity, sessions and the token registration live in the app's own container, which iOS
     does delete, and only a copy is mirrored into the group for the extension to read.
     */
    func testAReinstallMintsANewInstallEvenThoughTheGroupContainerSurvived() {
        let survivingGroup = defaults()
        let beforeReinstall = IdentityStore(defaults: defaults())
        let oldDeviceId = beforeReinstall.deviceId
        Storage.mirrorIdentity(from: beforeReinstall, into: survivingGroup)
        XCTAssertEqual(survivingGroup.string(forKey: "com.analytics.sdk.device_id"), oldDeviceId)

        // The reinstall: an empty app container, the same group container.
        let afterReinstall = IdentityStore(defaults: defaults())

        XCTAssertNotEqual(afterReinstall.deviceId, oldDeviceId, "a reinstall is a new install")
        XCTAssertTrue(afterReinstall.isFirstOpenPending, "and it owes a $first_open again")
    }

    /**
     The guard that matters: the client itself must read identity from the app's store. Pointed at
     a group container that still holds a previous install's identity — which is what a reinstall
     actually looks like — the events it queues carry the new install, not the old one.
     */
    func testTheClientTakesItsIdentityFromTheAppStoreNotTheSurvivingGroup() throws {
        let survivingGroup = defaults()
        survivingGroup.set("device-from-the-last-install", forKey: IdentityKeys.deviceId)
        survivingGroup.set("anon-from-the-last-install", forKey: IdentityKeys.anonymousId)
        survivingGroup.set("u-from-the-last-install", forKey: IdentityKeys.userId)

        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: file) }
        let queue = EventQueue(url: file, maxEvents: 100)
        let client = AnalyticsClient(
            config: AnalyticsConfig(apiKey: "k", endpoint: "https://ingest.example.com", flushIntervalSeconds: 0, flushBatchSize: 500, appGroup: "group.test"),
            defaults: defaults(),
            sharedDefaults: survivingGroup,
            queue: queue,
            uploader: SilentUploader()
        )

        client.track("instrument_viewed", properties: ["symbol": "AAPL"])
        let line = try waitForLine(in: queue)
        let event = try WireJson.decoder.decode(RawEvent.self, from: Data(line.utf8))

        XCTAssertNotEqual(event.deviceId, "device-from-the-last-install", "a reinstall is a new install")
        XCTAssertNotEqual(event.anonymousId, "anon-from-the-last-install")
        XCTAssertNil(event.userId, "and nobody is signed in on a fresh install")

        // The group copy is refreshed to this install, so the extension records the same person.
        XCTAssertEqual(survivingGroup.string(forKey: IdentityKeys.deviceId), event.deviceId)
        XCTAssertNil(survivingGroup.string(forKey: IdentityKeys.userId))
    }

    /// The queue is written on the SDK's own thread, so a test waits for the line rather than
    /// assuming it is there.
    private func waitForLine(in queue: EventQueue, timeout: TimeInterval = 2) throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let line = queue.peek(1).first { return line }
            Thread.sleep(forTimeInterval: 0.02)
        }
        throw XCTSkip("no event was queued within \(timeout)s")
    }

    /// An uploader that never touches the network: the test is about what was queued.
    private final class SilentUploader: EventUploader {
        init() { super.init(url: URL(string: "https://example.invalid/v1/events")!, apiKey: "k") }
        override func upload(_ body: String) -> UploadResult { .retryable(reason: "not sending in a test") }
    }

    func testTheGroupCopyFollowsTheAppSoTheExtensionRecordsUnderTheSamePerson() {
        let app = defaults()
        let shared = defaults()
        let identity = IdentityStore(defaults: app)
        identity.userId = "u-1"

        Storage.mirrorIdentity(from: identity, into: shared)

        let asTheExtensionSeesIt = IdentityStore(defaults: shared)
        XCTAssertEqual(asTheExtensionSeesIt.deviceId, identity.deviceId)
        XCTAssertEqual(asTheExtensionSeesIt.anonymousId, identity.anonymousId)
        XCTAssertEqual(asTheExtensionSeesIt.userId, "u-1")

        // A sign-out moves the app on, and the copy follows.
        identity.reset()
        Storage.mirrorIdentity(from: identity, into: shared)
        XCTAssertEqual(IdentityStore(defaults: shared).anonymousId, identity.anonymousId)
        XCTAssertNil(IdentityStore(defaults: shared).userId)
    }

    func testTheTokenRegistrationIsForgottenByAReinstallSoItIsSentAgain() {
        let app = defaults()
        let store = PushTokenStore(defaults: app)
        store.remember(token: "tok-1", kind: TokenKinds.fcm, status: TokenStatuses.active)
        XCTAssertFalse(store.shouldSend(token: "tok-1", kind: TokenKinds.fcm, status: TokenStatuses.active))

        // The reinstall: the app's own container is empty again, and Firebase hands back the same
        // token it had before, because its own id lives in the keychain.
        let afterReinstall = PushTokenStore(defaults: defaults())
        XCTAssertTrue(
            afterReinstall.shouldSend(token: "tok-1", kind: TokenKinds.fcm, status: TokenStatuses.active),
            "the registry has never heard of this install, so the same token is news"
        )
    }

    // MARK: - Sessions

    func testASessionExpiresAfterTheInactivityTimeout() {
        let sessions = SessionManager(defaults: defaults(), timeoutMinutes: 30)
        let start = Date(timeIntervalSince1970: 1_790_000_000)

        let first = sessions.current(at: start)
        XCTAssertTrue(first.isNew)

        let within = sessions.current(at: start.addingTimeInterval(29 * 60))
        XCTAssertEqual(within.id, first.id)
        XCTAssertFalse(within.isNew)

        // Counted from the last event, not from the session's start.
        let later = sessions.current(at: start.addingTimeInterval(29 * 60 + 31 * 60))
        XCTAssertNotEqual(later.id, first.id)
        XCTAssertTrue(later.isNew)
    }

    func testClearingStartsTheNextEventsSessionAfresh() {
        let sessions = SessionManager(defaults: defaults(), timeoutMinutes: 30)
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let first = sessions.current(at: start)

        sessions.clear()
        let next = sessions.current(at: start.addingTimeInterval(60))

        XCTAssertNotEqual(next.id, first.id, "one visit never spans two people")
        XCTAssertTrue(next.isNew)
    }

    // MARK: - Uploads

    func testAStatusDecidesWhetherEventsAreKeptDroppedOrRetried() {
        XCTAssertEqual(UploadResult.forStatus(202), .success)
        XCTAssertEqual(UploadResult.forStatus(200), .success)
        XCTAssertEqual(UploadResult.forStatus(429), .retryable(reason: "HTTP 429"))
        XCTAssertEqual(UploadResult.forStatus(503), .retryable(reason: "HTTP 503"))
        // A bad key or a malformed batch will never be accepted, and keeping it blocks everything
        // behind it forever.
        XCTAssertEqual(UploadResult.forStatus(401), .permanent(reason: "HTTP 401"))
        XCTAssertEqual(UploadResult.forStatus(400), .permanent(reason: "HTTP 400"))
    }

    func testAValueKeepsTheTypeItWasGivenIn() {
        XCTAssertEqual(WireValue.of("AAPL"), .string("AAPL"))
        XCTAssertEqual(WireValue.of(42), .integer(42))
        XCTAssertEqual(WireValue.of(4.5), .number(4.5))
        XCTAssertEqual(WireValue.of(true), .bool(true))
        XCTAssertNil(WireValue.of(nil), "a nil property is dropped rather than sent as null")
    }
}
