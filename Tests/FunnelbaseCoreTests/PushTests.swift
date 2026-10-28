import XCTest
@testable import FunnelbaseCore

/// Push, as an Apple device sees it: reading the payload Firebase delivers, deciding what the
/// notification service extension should do with it, and recording the receipt from a process that
/// is not the app.
final class PushTests: XCTestCase {

    private func userInfo(_ extra: [String: Any] = [:]) -> [AnyHashable: Any] {
        var payload: [String: Any] = [
            "delivery_id": "del-1",
            "run_id": "run-1",
            "aps": [
                "alert": ["title": "Your order filled", "body": "12 shares of MSFT"],
                "mutable-content": 1,
            ],
        ]
        payload.merge(extra) { _, new in new }
        return payload
    }

    // MARK: - Parsing

    func testTheTextComesFromTheAlertAndTheIdsFromTheDataKeys() {
        let payload = PushParser.parse(userInfo())!

        XCTAssertEqual(payload.deliveryId, "del-1")
        XCTAssertEqual(payload.runId, "run-1")
        XCTAssertEqual(payload.title, "Your order filled", "Apple draws the banner from aps.alert")
        XCTAssertEqual(payload.body, "12 shares of MSFT")
        XCTAssertTrue(payload.buttons.isEmpty)
        XCTAssertTrue(payload.data.isEmpty)
    }

    func testANotificationWithoutOurIdsIsNotOurs() {
        XCTAssertNil(PushParser.parse(["aps": ["alert": "Someone else's push"]]))
        XCTAssertNil(PushParser.parse(["delivery_id": "del-1"]))
        XCTAssertNil(PushParser.parse([:]))
    }

    func testTheCampaignsOwnKeysArriveSeparatelyFromFirebasesAndOurs() {
        let payload = PushParser.parse(userInfo([
            "order_id": "42",
            "image_url": "https://example.com/a.png",
            "deep_link": "trade://orders/42",
            "gcm.message_id": "0:169",
            "google.c.fid": "abc",
        ]))!

        XCTAssertEqual(payload.data, ["order_id": "42"])
        XCTAssertEqual(payload.imageUrl, "https://example.com/a.png")
        XCTAssertEqual(payload.deepLink, "trade://orders/42")
    }

    func testButtonsArriveAsOneJsonStringAndKeepTheirOrder() {
        let buttons = """
        [{"id":"view","title":"View order","deep_link":"trade://orders/42"},{"id":"later","title":"Later"}]
        """
        let payload = PushParser.parse(userInfo(["buttons": buttons]))!

        XCTAssertEqual(payload.buttons.map(\.id), ["view", "later"])
        XCTAssertEqual(payload.buttons[0].deepLink, "trade://orders/42")
        XCTAssertNil(payload.buttons[1].deepLink)
    }

    func testAMalformedOrNamelessButtonListCostsTheButtonsNotTheMessage() {
        XCTAssertTrue(PushParser.parse(userInfo(["buttons": "not json"]))!.buttons.isEmpty)
        XCTAssertTrue(PushParser.parse(userInfo(["buttons": "[{\"id\":\"x\"}]"]))!.buttons.isEmpty)
        XCTAssertTrue(PushParser.parse(userInfo(["buttons": "[{\"id\":\" \",\"title\":\"Blank\"}]"]))!.buttons.isEmpty)
    }

    func testTheLinkATapFollowsIsTheButtonsThenTheMessages() {
        let payload = PushPayload(
            deliveryId: "d", runId: "r",
            deepLink: "trade://orders",
            buttons: [PushButton(id: "view", title: "View", deepLink: "trade://instrument/MSFT"), PushButton(id: "later", title: "Later")]
        )

        XCTAssertEqual(payload.link(forActionId: "view"), "trade://instrument/MSFT")
        XCTAssertEqual(payload.link(forActionId: "later"), "trade://orders")
        XCTAssertEqual(payload.link(forActionId: nil), "trade://orders")
    }

    // MARK: - What the extension should do

    func testTheCategoryComesFromThePayloadAndIsDerivedOnlyIfItHasTo() {
        let buttons = [PushButton(id: "view", title: "View")]
        let named = NotificationPlan.of(PushPayload(deliveryId: "d", runId: "r", category: "an_abc123", buttons: buttons))
        XCTAssertEqual(named.categoryIdentifier, "an_abc123", "the sender already named one")

        let unnamed = NotificationPlan.of(PushPayload(deliveryId: "d", runId: "r", buttons: buttons))
        XCTAssertEqual(unnamed.categoryIdentifier, NotificationPlan.derivedCategory(for: buttons))
        XCTAssertTrue(unnamed.categoryIdentifier!.hasPrefix("an_"))

        // Same buttons, same category: registering one per push would be thousands of them.
        XCTAssertEqual(NotificationPlan.derivedCategory(for: buttons), NotificationPlan.derivedCategory(for: buttons))
        XCTAssertNotEqual(
            NotificationPlan.derivedCategory(for: buttons),
            NotificationPlan.derivedCategory(for: [PushButton(id: "view", title: "View order")])
        )
    }

    /// The Funnelbase backend derives this identifier and puts it in the payload; this extension
    /// derives it again to register the category. Neither asks the other, so the string is pinned
    /// on both sides — the backend's own test pins the same one. A drift here shows no buttons.
    func testTheDerivedCategoryMatchesTheOneTheDispatcherWrites() {
        let buttons = [
            PushButton(id: "view", title: "View order", deepLink: "trade://orders/42"),
            PushButton(id: "later", title: "Later"),
        ]
        XCTAssertEqual(NotificationPlan.derivedCategory(for: buttons), "an_b1305f79a85f")
    }

    func testAMessageWithNoButtonsRegistersNoCategory() {
        let plan = NotificationPlan.of(PushPayload(deliveryId: "d", runId: "r", category: "an_abc"))
        XCTAssertNil(plan.categoryIdentifier, "a category with no actions would only hide the payload's own")
        XCTAssertTrue(plan.buttons.isEmpty)
    }

    func testOnlyAnHttpsImageIsFetchedUnlessTheHostAllowsOtherwise() {
        func plan(_ url: String?, allowInsecure: Bool = false) -> URL? {
            NotificationPlan.of(PushPayload(deliveryId: "d", runId: "r", imageUrl: url), allowInsecureImages: allowInsecure).imageUrl
        }

        XCTAssertEqual(plan("https://example.com/a.png")?.absoluteString, "https://example.com/a.png")
        XCTAssertNil(plan("http://10.0.2.2:9099/media/sample.png"), "Apple's transport security refuses it")
        XCTAssertEqual(
            plan("http://localhost:9099/media/sample.png", allowInsecure: true)?.absoluteString,
            "http://localhost:9099/media/sample.png",
            "a local provider over http, when the extension opts in"
        )
        XCTAssertNil(plan("file:///etc/passwd"))
        XCTAssertNil(plan(nil))
    }

    func testACollapseKeyBecomesTheThreadSoTwoPushesGroup() {
        let plan = NotificationPlan.of(PushPayload(deliveryId: "d", runId: "r", collapseKey: "market_close"))
        XCTAssertEqual(plan.threadIdentifier, "market_close")
        XCTAssertNil(NotificationPlan.of(PushPayload(deliveryId: "d", runId: "r")).threadIdentifier)
    }

    // MARK: - The receipt, written from the extension

    func testTheExtensionQueuesAReceiptWithNoSessionUnderTheAppsIdentity() throws {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let identity = IdentityStore(defaults: defaults)
        identity.userId = "u-1"
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jsonl")
        let queue = EventQueue(url: file, maxEvents: 100)
        defer { try? FileManager.default.removeItem(at: file) }

        let writer = PassiveEventWriter(defaults: defaults, queue: queue, device: DeviceContext())
        writer.write(
            ReservedEvents.pushReceived,
            properties: [ReservedEvents.pushDeliveryId: "del-1", ReservedEvents.pushRunId: "run-1"]
        )

        let line = queue.peek(1).first!
        let event = try WireJson.decoder.decode(RawEvent.self, from: Data(line.utf8))
        XCTAssertEqual(event.eventName, ReservedEvents.pushReceived)
        XCTAssertEqual(event.sessionId, "", "a push arriving in the background opens no visit")
        XCTAssertEqual(event.userId, "u-1", "the app's own identity, through shared storage")
        XCTAssertEqual(event.deviceId, identity.deviceId)
        XCTAssertEqual(event.properties[ReservedEvents.pushDeliveryId], .string("del-1"))
    }

    // MARK: - The token

    func testATokenIsSentOnceUntilSomethingAboutItChanges() {
        let store = PushTokenStore(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)

        XCTAssertTrue(store.shouldSend(token: "tok-1", kind: TokenKinds.apns, status: TokenStatuses.active))
        store.remember(token: "tok-1", kind: TokenKinds.apns, status: TokenStatuses.active)
        XCTAssertFalse(store.shouldSend(token: "tok-1", kind: TokenKinds.apns, status: TokenStatuses.active))

        XCTAssertTrue(store.shouldSend(token: "tok-2", kind: TokenKinds.apns, status: TokenStatuses.active))
        XCTAssertTrue(store.shouldSend(token: "tok-1", kind: TokenKinds.fcm, status: TokenStatuses.active))
        XCTAssertTrue(store.shouldSend(token: "tok-1", kind: TokenKinds.apns, status: TokenStatuses.disabled))
        XCTAssertFalse(store.shouldSend(token: "  ", kind: TokenKinds.apns, status: TokenStatuses.active))

        store.forget()
        XCTAssertTrue(store.shouldSend(token: "tok-1", kind: TokenKinds.apns, status: TokenStatuses.active), "a reset re-registers")
    }

    /// The registry's locale and time zone are what a run picks a template's language and clock by,
    /// so a phone switched to Turkish has to say so without waiting for a new token.
    func testAPhoneSetToAnotherLanguageOrTimeZoneReRegisters() {
        let store = PushTokenStore(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        let here = DeviceRegion(locale: "en-US", timezone: "America/New_York")
        store.remember(token: "tok-1", kind: TokenKinds.apns, status: TokenStatuses.active, region: here)

        XCTAssertFalse(store.shouldSend(token: "tok-1", kind: TokenKinds.apns, status: TokenStatuses.active, region: here))
        var turkish = here
        turkish.locale = "tr-TR"
        XCTAssertTrue(store.shouldSend(token: "tok-1", kind: TokenKinds.apns, status: TokenStatuses.active, region: turkish))
        var istanbul = here
        istanbul.timezone = "Europe/Istanbul"
        XCTAssertTrue(store.shouldSend(token: "tok-1", kind: TokenKinds.apns, status: TokenStatuses.active, region: istanbul))
    }

    func testAnAppleIdentifierIsSentAsALanguageTag() {
        XCTAssertEqual(DeviceInfo.languageTag("tr_TR@rg=dezzzz"), "tr-TR")
        XCTAssertEqual(DeviceInfo.languageTag("zh-Hans-CN"), "zh-Hans-CN")
        XCTAssertEqual(DeviceInfo.languageTag("en"), "en")
        XCTAssertFalse(DeviceInfo.region().locale.contains("_"))
    }

    func testAnAppleDeviceTokenIsAddressedAsLowercaseHex() {
        XCTAssertEqual(PushTokenStore.hex(Data([0x0a, 0xff, 0x10])), "0aff10")
        XCTAssertEqual(PushTokenStore.statusFor(enabled: true), TokenStatuses.active)
        XCTAssertEqual(PushTokenStore.statusFor(enabled: false), TokenStatuses.disabled)
    }
}
