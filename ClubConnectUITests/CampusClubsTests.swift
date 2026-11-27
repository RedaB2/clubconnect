import XCTest

@MainActor
final class CampusClubsTests: XCTestCase {
    func testManagingTwoClubsAndSwitchingToMemberView() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone)
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ClubConnectFreshDemo"]
        app.launch()
        app.buttons["explore-demo"].tap()
        app.tabBars.buttons["Clubs"].tap()
        app.buttons["select-club-menasa"].tap()
        let memberMode = app.switches["member-view-toggle"].firstMatch
        XCTAssertTrue(memberMode.waitForExistence(timeout: 5))
        memberMode.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(memberMode.value as? String, "1")
        app.tabBars.buttons["Events"].tap()
        XCTAssertFalse(app.buttons["Create event"].exists)
        app.tabBars.buttons["Clubs"].tap()
        memberMode.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Create a club"].tap()
        app.textFields["Club name"].tap()
        app.textFields["Club name"].typeText("Campus Robotics")
        app.buttons["Create"].tap()
        XCTAssertTrue(app.navigationBars["Campus Robotics"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Events"].tap()
        XCTAssertTrue(app.buttons["Create event"].exists)
        XCTAssertFalse(app.buttons["event-a1000000-0000-4000-8000-000000000001"].exists)
        app.buttons["Switch club, Campus Robotics"].tap()
        app.buttons["MENASA"].tap()
        XCTAssertTrue(app.buttons["event-a1000000-0000-4000-8000-000000000001"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Create event"].exists)
    }
}
