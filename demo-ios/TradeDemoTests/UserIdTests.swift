import XCTest
@testable import TradeDemo

/// The determinism these assert is the whole reason the demo can have accounts without an auth
/// backend. If it breaks, every sign-in becomes a new person and retention numbers silently
/// become meaningless rather than wrong-looking.
final class UserIdTests: XCTestCase {

    func testSameUsernameAlwaysYieldsTheSameId() {
        XCTAssertEqual(UserId.forUsername("ada"), UserId.forUsername("ada"))
    }

    func testIdIsStableAcrossRunsNotJustWithinOne() {
        // Pinned to a literal on purpose, and to the *same* literal the Android test pins:
        // comparing two live calls would still pass if the algorithm changed, changing it
        // invalidates every user_id already sent, and the two platforms disagreeing
        // would split one person in two on every page of the dashboard.
        XCTAssertEqual(UserId.forUsername("ada"), "u_fdee430d40bd57de")
    }

    func testCaseAndSurroundingWhitespaceDoNotMakeADifferentPerson() {
        let expected = UserId.forUsername("ada")
        XCTAssertEqual(UserId.forUsername("  ADA  "), expected)
        XCTAssertEqual(UserId.forUsername("Ada"), expected)
    }

    func testDifferentUsernamesYieldDifferentIds() {
        XCTAssertNotEqual(UserId.forUsername("ada"), UserId.forUsername("grace"))
    }

    func testIdIsPrefixedAndSixteenHexCharactersWide() {
        let id = UserId.forUsername("grace")
        XCTAssertEqual(id.count, 18)
        XCTAssertTrue(id.hasPrefix("u_"), "expected a u_ prefix, got \(id)")
        XCTAssertTrue(
            id.dropFirst(2).allSatisfy { "0123456789abcdef".contains($0) },
            "expected lowercase hex, got \(id)"
        )
    }
}
