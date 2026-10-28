import Funnelbase
import XCTest
@testable import TradeDemo

/// The app's half of a tap: the SDK reports the open and hands the push over, and this decides
/// where to go. A campaign is written long after a build ships, so an unknown link has to be
/// harmless rather than a crash or a blank screen.
final class PushRoutingTests: XCTestCase {

    private func payload(deepLink: String? = nil, buttons: [PushButton] = []) -> PushPayload {
        PushPayload(
            deliveryId: "del-1",
            runId: "run-1",
            title: "Your order filled",
            body: "AAPL, 12 shares",
            deepLink: deepLink,
            buttons: buttons
        )
    }

    func testAnInstrumentLinkOpensThatInstrumentWhateverCaseItWasWrittenIn() {
        XCTAssertEqual(PushRouting.routeFor("trade://instrument/AAPL"), "instrument/AAPL")
        XCTAssertEqual(PushRouting.routeFor("trade://instrument/aapl"), "instrument/AAPL")
        XCTAssertEqual(PushRouting.routeFor("trade://instrument/AAPL/"), "instrument/AAPL")
    }

    func testATabLinkOpensThatTab() {
        XCTAssertEqual(PushRouting.routeFor("trade://markets"), "markets")
        XCTAssertEqual(PushRouting.routeFor("trade://news"), "news")
    }

    func testALinkThisBuildDoesNotKnowLeavesTheAppWhereItIs() {
        XCTAssertNil(PushRouting.routeFor(nil))
        XCTAssertNil(PushRouting.routeFor(""))
        XCTAssertNil(PushRouting.routeFor("trade://portfolio/rebalance"), "a route a later version may add")
        XCTAssertNil(PushRouting.routeFor("https://example.com/promo"), "someone else's link")
        XCTAssertNil(PushRouting.routeFor("trade://instrument"), "an instrument link with no instrument")
    }

    /// A button carries its own link, and that is the point of a button: "View order" and
    /// "Later" on one push lead to different places.
    func testAButtonsLinkWinsOverTheMessagesAndTheMessagesIsTheFallback() {
        let buttons = [
            PushButton(id: "view", title: "View", deepLink: "trade://instrument/MSFT"),
            PushButton(id: "later", title: "Later"),
        ]
        let push = payload(deepLink: "trade://orders", buttons: buttons)

        XCTAssertEqual(PushRouting.linkFor(push, actionId: "view"), "trade://instrument/MSFT")
        XCTAssertEqual(
            PushRouting.linkFor(push, actionId: "later"),
            "trade://orders",
            "a button with no link of its own"
        )
        XCTAssertEqual(
            PushRouting.linkFor(push, actionId: nil),
            "trade://orders",
            "the notification itself"
        )
        XCTAssertNil(PushRouting.linkFor(payload(), actionId: nil))
    }

    /// The pair, as the app delegate uses it: a link resolved from the tap, then a route.
    func testARichCampaignsButtonRoutesToItsOwnInstrument() {
        let push = payload(
            deepLink: "trade://orders",
            buttons: [PushButton(id: "view_order", title: "View order", deepLink: "trade://instrument/MSFT")]
        )
        XCTAssertEqual(
            PushRouting.routeFor(PushRouting.linkFor(push, actionId: "view_order")),
            "instrument/MSFT"
        )
        XCTAssertEqual(PushRouting.routeFor(PushRouting.linkFor(push, actionId: nil)), "orders")
    }
}
