import XCTest
@testable import FunnelbaseCore

/// Notification topics: the passive `$topic_preference`, reading `GET /v1/topics`, and the rule that
/// a choice made here wins over a server that has not heard of it yet.
final class TopicsTests: XCTestCase {

    private var file: URL!

    override func setUp() {
        super.setUp()
        file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jsonl")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: file)
        StubProtocol.handler = nil
        super.tearDown()
    }

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "test-\(UUID().uuidString)")!
    }

    private let config = AnalyticsConfig(apiKey: "k", endpoint: "https://ingest.example.com", flushIntervalSeconds: 0, flushBatchSize: 500)

    private func client(
        queue: EventQueue,
        store: UserDefaults? = nil,
        topics: TopicsFetcher = CannedFetcher(.success([])),
        uploader: EventUploader = HeldUploader()
    ) -> AnalyticsClient {
        AnalyticsClient(
            config: config,
            defaults: store ?? defaults(),
            sharedDefaults: defaults(),
            queue: queue,
            uploader: uploader,
            topics: topics,
            device: DeviceContext(platform: "ios")
        )
    }

    private func fetch(_ client: AnalyticsClient) -> Result<[TopicChoice], TopicsError> {
        let done = expectation(description: "topics")
        var outcome: Result<[TopicChoice], TopicsError>!
        client.fetchTopics { result in
            XCTAssertTrue(Thread.isMainThread, "a settings screen renders the answer straight away")
            outcome = result
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
        return outcome
    }

    private func waitForLines(_ queue: EventQueue, count: Int) -> [String] {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            let lines = queue.peek(100)
            if lines.count >= count { return lines }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return queue.peek(100)
    }

    // MARK: - The event

    func testAChoiceIsAPassiveEventWithTheTopicAndABoolean() throws {
        let queue = EventQueue(url: file, maxEvents: 100)
        let client = client(queue: queue)
        client.identify("u-1")
        client.setTopic("promotions", subscribed: false)

        // $session_start, $first_open and $identify from the sign-in, then the choice.
        let lines = waitForLines(queue, count: 4)
        let events = try lines.map { try WireJson.decoder.decode(RawEvent.self, from: Data($0.utf8)) }
        let identify = try XCTUnwrap(events.first { $0.eventName == "$identify" })
        let choice = try XCTUnwrap(events.last)

        XCTAssertEqual(choice.eventName, "$topic_preference")
        XCTAssertEqual(choice.sessionId, "", "a choice in a settings screen is not a visit")
        XCTAssertEqual(choice.properties, ["topic": .string("promotions"), "subscribed": .bool(false)])
        XCTAssertTrue(lines.last!.contains("\"subscribed\":false"), "a JSON boolean, not a string: \(lines.last!)")
        XCTAssertEqual(choice.userId, "u-1", "the server applies the person rule to it")
        XCTAssertEqual(choice.anonymousId, identify.anonymousId)
        XCTAssertEqual(choice.deviceId, identify.deviceId)
        XCTAssertEqual(events.count, 4, "it opens no session of its own")
    }

    func testAChoiceAloneStartsNoSession() throws {
        let queue = EventQueue(url: file, maxEvents: 100)
        let client = client(queue: queue)
        client.setTopic("promotions", subscribed: true)

        let lines = waitForLines(queue, count: 1)
        withExtendedLifetime(client) {}
        XCTAssertEqual(lines.count, 1, "no $session_start, no $first_open: nobody opened the app for it")
        let event = try WireJson.decoder.decode(RawEvent.self, from: Data(lines[0].utf8))
        XCTAssertEqual(event.eventName, "$topic_preference")
        XCTAssertNil(event.userId, "signed out, no user id at all")
    }

    // MARK: - Reading the list

    func testTheAnswerDecodesWithAnOptionalDescription() throws {
        let body = """
        {"topics":[
          {"key":"promotions","name":"Promotions","description":"Offers and news","subscribed":true,"chosen":false},
          {"key":"price_alerts","name":"Price alerts","description":null,"subscribed":false,"chosen":true}
        ]}
        """
        let topics = try TopicsFetcher.read(status: 200, body: Data(body.utf8)).get()

        XCTAssertEqual(topics, [
            TopicChoice(key: "promotions", name: "Promotions", description: "Offers and news", subscribed: true, chosen: false),
            TopicChoice(key: "price_alerts", name: "Price alerts", description: nil, subscribed: false, chosen: true),
        ])
    }

    func testA503OrAnUnreadableBodyIsAFailure() {
        XCTAssertEqual(TopicsFetcher.read(status: 503, body: Data("{}".utf8)), .failure(.http(status: 503)))
        XCTAssertEqual(TopicsFetcher.read(status: 200, body: Data("not json".utf8)), .failure(.malformed))
        XCTAssertEqual(TopicsFetcher.read(status: 200, body: nil), .failure(.malformed))
    }

    func testTheRequestNamesThePersonAndCarriesTheKey() {
        let fetcher = TopicsFetcher(url: config.topicsUrl, apiKey: "key-1")

        let signedIn = fetcher.request(anonymousId: "anon 1", userId: "u-1")
        XCTAssertEqual(signedIn.url?.absoluteString, "https://ingest.example.com/v1/topics?anonymous_id=anon%201&user_id=u-1")
        XCTAssertEqual(signedIn.httpMethod, "GET")
        XCTAssertEqual(signedIn.value(forHTTPHeaderField: "X-Api-Key"), "key-1")

        let signedOut = fetcher.request(anonymousId: "anon-1", userId: nil)
        XCTAssertEqual(signedOut.url?.absoluteString, "https://ingest.example.com/v1/topics?anonymous_id=anon-1",
                       "no user_id at all while signed out")
    }

    func testOverTheNetworkA503ReachesTheCallerAsAFailure() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        var asked: URLRequest?
        StubProtocol.handler = { request in
            asked = request
            return (503, Data("{\"error\":\"unavailable\"}".utf8))
        }
        let fetcher = TopicsFetcher(url: config.topicsUrl, apiKey: "k", session: URLSession(configuration: configuration))

        let result = fetch(client(queue: EventQueue(url: file, maxEvents: 100), topics: fetcher))

        XCTAssertEqual(result, .failure(.http(status: 503)))
        XCTAssertEqual(asked?.url?.path, "/v1/topics")
        XCTAssertEqual(asked?.value(forHTTPHeaderField: "X-Api-Key"), "k")
    }

    func testOverTheNetworkA200IsTheList() throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        StubProtocol.handler = { _ in
            (200, Data("{\"topics\":[{\"key\":\"promotions\",\"name\":\"Promotions\",\"subscribed\":true,\"chosen\":false}]}".utf8))
        }
        let fetcher = TopicsFetcher(url: config.topicsUrl, apiKey: "k", session: URLSession(configuration: configuration))

        let topics = try fetch(client(queue: EventQueue(url: file, maxEvents: 100), topics: fetcher)).get()

        XCTAssertEqual(topics.map(\.key), ["promotions"])
        XCTAssertNil(topics[0].description)
    }

    // MARK: - The overlay

    private let server = [
        TopicChoice(key: "promotions", name: "Promotions", subscribed: true, chosen: false),
        TopicChoice(key: "price_alerts", name: "Price alerts", subscribed: true, chosen: false),
    ]

    func testAChoiceTheServerHasNotHeardOfWinsOverItsAnswer() throws {
        let queue = EventQueue(url: file, maxEvents: 100)
        let client = client(queue: queue, topics: CannedFetcher(.success(server)))

        client.setTopic("promotions", subscribed: false)
        let topics = try fetch(client).get()

        XCTAssertEqual(topics[0], TopicChoice(key: "promotions", name: "Promotions", subscribed: false, chosen: true),
                       "the toggle the person just flipped must not flip back")
        XCTAssertEqual(topics[1], server[1], "an untouched topic is the server's")
    }

    func testOnceTheServerHoldsTheSameChoiceItIsTheTruthAgain() throws {
        let store = TopicPreferenceStore(defaults: defaults())
        store.remember(topic: "promotions", subscribed: false, eventId: "e-1")

        let caughtUp = [TopicChoice(key: "promotions", name: "Promotions", subscribed: false, chosen: true)]
        XCTAssertEqual(store.overlay(caughtUp), caughtUp)
        XCTAssertTrue(store.pending.isEmpty, "released: a later change on another device must show here")

        let changedElsewhere = [TopicChoice(key: "promotions", name: "Promotions", subscribed: true, chosen: true)]
        XCTAssertEqual(store.overlay(changedElsewhere), changedElsewhere)
    }

    func testADefaultThatHappensToMatchDoesNotReleaseTheChoice() {
        let store = TopicPreferenceStore(defaults: defaults())
        store.remember(topic: "promotions", subscribed: true, eventId: "e-1")

        let shown = store.overlay([TopicChoice(key: "promotions", name: "Promotions", subscribed: true, chosen: false)])

        XCTAssertEqual(shown[0].chosen, true, "the person did choose, even if the default says the same")
        XCTAssertEqual(store.pending.count, 1, "the server has not stored it yet")
    }

    func testARejectedUploadReleasesTheChoiceItCarried() throws {
        let store = TopicPreferenceStore(defaults: defaults())
        store.remember(topic: "promotions", subscribed: false, eventId: "e-1")
        store.remember(topic: "price_alerts", subscribed: false, eventId: "e-2")

        store.release(droppedLines: ["{\"event_id\":\"e-1\",\"event_name\":\"$topic_preference\"}"])

        XCTAssertEqual(Array(store.pending.keys), ["price_alerts"])
    }

    func testATopicTheServerNoLongerListsIsForgotten() {
        let store = TopicPreferenceStore(defaults: defaults())
        store.remember(topic: "retired", subscribed: false, eventId: "e-1")

        XCTAssertEqual(store.overlay(server), server)
        XCTAssertTrue(store.pending.isEmpty)
    }

    func testASignOutForgetsTheLastPersonsChoices() throws {
        let queue = EventQueue(url: file, maxEvents: 100)
        let client = client(queue: queue, topics: CannedFetcher(.success(server)))
        client.identify("u-1")
        client.setTopic("promotions", subscribed: false)

        client.reset()
        let topics = try fetch(client).get()

        XCTAssertEqual(topics, server, "the next person on this phone sees their own choices, not the last one's")
    }

    func testAFailedFetchIsPassedOnUntouched() {
        let client = client(queue: EventQueue(url: file, maxEvents: 100), topics: CannedFetcher(.failure(.network("offline"))))
        XCTAssertEqual(fetch(client), .failure(.network("offline")))
    }

    // MARK: - Doubles

    /// An answer decided by the test.
    private final class CannedFetcher: TopicsFetcher {
        private let result: Result<[TopicChoice], TopicsError>

        init(_ result: Result<[TopicChoice], TopicsError>) {
            self.result = result
            super.init(url: URL(string: "https://example.invalid/v1/topics")!, apiKey: "k")
        }

        override func fetch(anonymousId: String, userId: String?, completion: @escaping (Result<[TopicChoice], TopicsError>) -> Void) {
            DispatchQueue.global().async { completion(self.result) }
        }
    }

    /// Keeps everything queued, so a test reads what was sent.
    private final class HeldUploader: EventUploader {
        init() { super.init(url: URL(string: "https://example.invalid/v1/events")!, apiKey: "k") }
        override func upload(_ body: String) -> UploadResult { .retryable(reason: "not sending in a test") }
    }
}

/// Answers `URLSession` requests without a network.
final class StubProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = StubProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let (status, body) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
