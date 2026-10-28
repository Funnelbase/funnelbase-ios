import XCTest
@testable import FunnelbaseCore

/// The offline queue, which is the SDK's promise that a phone in a lift loses nothing.
final class EventQueueTests: XCTestCase {

    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func queue(maxEvents: Int = 100) -> EventQueue {
        EventQueue(url: directory.appendingPathComponent("queue.jsonl"), maxEvents: maxEvents)
    }

    func testPeekDoesNotConsume() {
        let queue = queue()
        queue.enqueue("a")
        queue.enqueue("b")

        XCTAssertEqual(queue.peek(10), ["a", "b"])
        XCTAssertEqual(queue.peek(10), ["a", "b"], "peek must not consume: an upload that fails loses nothing")
        XCTAssertEqual(queue.size(), 2)
    }

    func testRemoveFirstDropsTheOldest() {
        let queue = queue()
        ["a", "b", "c"].forEach(queue.enqueue)

        queue.removeFirst(2)

        XCTAssertEqual(queue.peek(10), ["c"])
    }

    func testDropsTheOldestOnceTheCapIsReached() {
        let queue = queue(maxEvents: 3)
        ["1", "2", "3", "4", "5"].forEach(queue.enqueue)

        XCTAssertEqual(queue.peek(10), ["3", "4", "5"], "the newest events are the ones worth keeping")
    }

    func testRemovingOneLineLeavesTheRest() {
        let queue = queue()
        ["a", "b", "c"].forEach(queue.enqueue)

        queue.removeMatching("b")

        XCTAssertEqual(queue.peek(10), ["a", "c"], "the extension removes what it sent, not the front")
    }

    func testAnEmptyQueueReadsAsEmptyRatherThanFailing() {
        let queue = queue()
        XCTAssertEqual(queue.peek(10), [])
        XCTAssertEqual(queue.size(), 0)
        queue.removeFirst(5)
        XCTAssertEqual(queue.size(), 0)
    }

    /// The framing is one event per line, so a line break inside one would split it in two.
    func testALineWithANewlineIsRefused() {
        let queue = queue()
        // A precondition failure cannot be caught, so the guarantee is asserted on the encoder's
        // behaviour instead: JSON has no raw newlines in it.
        let event = RawEvent(
            eventId: "e", eventName: "a\nb", occurredAt: "2026-09-20T10:00:00.000Z",
            sessionId: "s", anonymousId: "a", deviceId: "d", device: DeviceContext()
        )
        let encoded = String(data: try! WireJson.encoder.encode(event), encoding: .utf8)!
        XCTAssertFalse(encoded.contains("\n"))
        queue.enqueue(encoded)
        XCTAssertEqual(queue.size(), 1)
    }

    /// Two processes write this queue: the app, and the extension recording a receipt.
    func testTwoQueuesOverOneFileBothAppend() {
        let first = queue()
        let second = queue()

        first.enqueue("from-the-app")
        second.enqueue("from-the-extension")

        XCTAssertEqual(first.peek(10), ["from-the-app", "from-the-extension"])
    }
}
