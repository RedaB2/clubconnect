import XCTest

@MainActor
final class AlumniMembershipTests: XCTestCase {
    func testOrganizerApprovesAnAlumAndTheirProfileAppearsInPeople() throws {
        let app = try openQueue()
        XCTAssertTrue(app.staticTexts["Samira Khalil"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["samira@example.invalid"].exists)
        let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        capture.name = "Organizer reviewing an alumni request"
        capture.lifetime = .keepAlways
        add(capture)
        app.buttons["Approve"].firstMatch.tap()
        app.alerts.buttons["Approve"].tap()
        XCTAssertTrue(app.staticTexts["Approved"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Approve"].exists)
        app.buttons["Done"].tap()
        app.tabBars.buttons["People"].tap()
        app.buttons["Alumni"].tap()
        let samira = app.descendants(matching: .any)["member-demo-approved-2a0f8120-fd89-4b1d-a065-7f372bc1e13c"].firstMatch
        for _ in 0..<4 where !samira.isHittable { app.swipeUp() }
        XCTAssertTrue(samira.isHittable, app.debugDescription)
        samira.tap()
        XCTAssertTrue(app.navigationBars["Member profile"].waitForExistence(timeout: 5))
    }

    func testDeclineMovesRequestToHistoryAndHidesReviewFromMemberView() throws {
        let app = try openQueue()
        app.buttons["Decline"].firstMatch.tap()
        app.alerts.buttons["Decline"].tap()
        XCTAssertTrue(app.staticTexts["Declined"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Approve"].exists)
        app.buttons["Done"].tap()
        let toggle = app.switches["member-view-toggle"]
        let control = toggle.switches.firstMatch
        if control.exists { control.tap() } else { toggle.tap() }
        XCTAssertFalse(app.buttons["review-alumni-requests"].exists)
    }

    private func openQueue() throws -> XCUIApplication {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone)
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ClubConnectFreshDemo", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.buttons["explore-demo"].tap()
        app.tabBars.buttons["Clubs"].tap()
        app.buttons["select-club-menasa"].tap()
        let manage = app.buttons["review-alumni-requests"]
        for _ in 0..<5 where !manage.isHittable { app.swipeUp() }
        manage.tap()
        XCTAssertTrue(app.navigationBars["Membership requests"].waitForExistence(timeout: 5))
        return app
    }
}
