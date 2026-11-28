import XCTest

@MainActor
final class FirstRunTests: XCTestCase {
    private let cleanLaunch = ["-ClubConnectFreshDemo", "-ClubConnectResetIntroduction"]
    private let locale = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]

    override func setUp() {
        continueAfterFailure = false
    }

    func testThreePagesLeadToAccountChoicesAndFinishOnlyOnce() {
        let app = firstRun()
        record("01 – First introduction page")
        app.buttons["intro-next"].tap()
        XCTAssertTrue(app.staticTexts["intro-page-1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Skip"].exists)
        record("02 – Second introduction page")
        app.buttons["intro-next"].tap()
        XCTAssertTrue(app.staticTexts["intro-page-2"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Skip"].exists)
        record("03 – Third introduction page")
        XCTAssertTrue(app.buttons["intro-finish"].waitForExistence(timeout: 5))
        app.buttons["intro-finish"].tap()
        assertAccountAccess(app)
        record("08 – Account choices")
        relaunch(app)
        assertAccountAccess(app)
    }

    func testBackAndSwipeNavigationLeadToReturningSignIn() {
        let app = firstRun()
        app.buttons["intro-next"].tap()
        app.buttons["intro-back"].tap()
        XCTAssertTrue(app.staticTexts["intro-page-0"].waitForExistence(timeout: 5))
        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["intro-page-1"].waitForExistence(timeout: 5))
        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["intro-page-2"].waitForExistence(timeout: 5))
        app.buttons["intro-finish"].tap()
        assertAccountAccess(app)
        relaunch(app)
        assertAccountAccess(app)
        app.buttons["returning-sign-in"].tap()
        XCTAssertTrue(app.staticTexts["Welcome back"].waitForExistence(timeout: 5))
    }

    func testColdAlumniLinkBypassesAnUnfinishedIntroduction() throws {
        let app = firstRun()
        app.terminate()
        app.launchArguments = locale
        app.open(try XCTUnwrap(URL(string: "clubconnect://join/menasa?alumni=1")))
        XCTAssertTrue(app.staticTexts["Reconnect with your club"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["account-email"].exists)
        XCTAssertTrue(app.staticTexts["Verify your personal email to create an alumni profile and request to join MENASA."].exists)
        XCTAssertFalse(app.buttons["intro-next"].exists)
    }

    func testReturningCommunityMemberAndColdEventLinkBypassIntroduction() throws {
        let app = firstRun()
        app.buttons["intro-next"].tap()
        app.buttons["intro-next"].tap()
        app.buttons["intro-finish"].tap()
        app.buttons["explore-demo"].tap()
        XCTAssertTrue(app.buttons["event-a1000000-0000-4000-8000-000000000001"].waitForExistence(timeout: 10))
        app.terminate()
        // Reset the flag alone to simulate a previously enrolled member upgrading to this release.
        app.launchArguments = ["-ClubConnectResetIntroduction"] + locale
        app.launch()
        XCTAssertTrue(app.buttons["event-a1000000-0000-4000-8000-000000000001"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["intro-next"].exists)
        app.terminate()
        app.launchArguments = locale
        app.open(try XCTUnwrap(URL(string: "clubconnect://event/a1000000-0000-4000-8000-000000000002?sample=1")))
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["After graduation"].firstMatch.exists)
        XCTAssertFalse(app.buttons["intro-next"].exists)
    }

    func testLargestDynamicTypeKeepsActionsReachable() {
        let app = firstRun(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        record("04 – Introduction at largest text size")
        tapIfReachable(app.buttons["intro-next"], in: app)
        XCTAssertTrue(app.staticTexts["intro-page-1"].waitForExistence(timeout: 5))
        tapIfReachable(app.buttons["intro-next"], in: app)
        XCTAssertTrue(app.staticTexts["intro-page-2"].waitForExistence(timeout: 5))
        tapIfReachable(app.buttons["intro-finish"], in: app)
        assertAccountAccess(app)
    }

    func testIPadLandscapeIntroduction() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        let previous = XCUIDevice.shared.orientation
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = previous }
        let app = firstRun()
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        record("05 – Landscape introduction on iPad")
        app.buttons["intro-next"].tap()
        XCTAssertTrue(app.staticTexts["intro-page-1"].waitForExistence(timeout: 5))
        record("06 – Second landscape page on iPad")
        app.buttons["intro-next"].tap()
        XCTAssertTrue(app.staticTexts["intro-page-2"].waitForExistence(timeout: 5))
        record("07 – Third landscape page on iPad")
        app.buttons["intro-finish"].tap()
        assertAccountAccess(app)
    }

    private func firstRun(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = cleanLaunch + locale + extra
        app.launch()
        XCTAssertTrue(app.staticTexts["intro-page-0"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Skip"].exists)
        return app
    }

    private func relaunch(_ app: XCUIApplication) {
        app.terminate()
        app.launchArguments = locale
        app.launch()
    }

    private func assertAccountAccess(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["returning-sign-in"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["usc-sign-in"].label, "USC Email")
        XCTAssertEqual(app.buttons["alumni-sign-up"].label, "Alum")
        XCTAssertFalse(app.buttons["intro-finish"].exists)
    }

    private func tapIfReachable(_ button: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<3 where !button.isHittable { app.swipeUp() }
        XCTAssertTrue(button.isHittable)
        button.tap()
    }

    private func record(_ name: String) {
        // During a recorded walkthrough, let the viewer read the live page before advancing.
        if ProcessInfo.processInfo.environment["CLUBCONNECT_RECORD_WALKTHROUGH"] == "1" {
            Thread.sleep(forTimeInterval: 3.0)
        }
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
