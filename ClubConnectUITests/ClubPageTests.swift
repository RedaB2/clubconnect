import XCTest

@MainActor
final class ClubPageTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone)
        continueAfterFailure = false
    }

    func testClubAgendaOpensNativeEventAndFollowsClubSwitch() {
        let app = openSample()
        app.tabBars.buttons["Clubs"].tap()
        XCTAssertTrue(app.navigationBars["Campus clubs"].waitForExistence(timeout: 5))
        capture("Campus club directory")

        app.buttons["discover-club-campus-cinema"].tap()
        app.buttons["Join Campus Cinema"].tap()
        XCTAssertTrue(app.navigationBars["Campus Cinema"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["club-events-empty"].exists)
        XCTAssertFalse(app.buttons["club-create-event"].exists)

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["select-club-menasa"].tap()
        let coffee = app.buttons["club-event-a1000000-0000-4000-8000-000000000001"]
        XCTAssertTrue(coffee.waitForExistence(timeout: 5))
        capture("MENASA club page with upcoming events")
        XCTAssertTrue(app.buttons["club-create-event"].exists)
        coffee.tap()
        XCTAssertTrue(app.buttons["RSVP"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Add to Calendar"].exists)

        app.tabBars.buttons["Events"].tap()
        app.buttons["Switch club, MENASA"].tap()
        app.buttons["Campus Cinema"].tap()
        app.tabBars.buttons["Clubs"].tap()
        XCTAssertTrue(app.navigationBars["Campus Cinema"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["club-events-empty"].exists)
        XCTAssertFalse(coffee.exists)
        XCTAssertFalse(app.buttons["RSVP"].exists)
    }

    func testBusyClubPreviewsThreeEventsAndOpensFullCalendar() {
        let app = openSample()
        app.tabBars.buttons["Events"].tap()
        app.buttons["Past"].tap()
        app.tabBars.buttons["Clubs"].tap()
        app.buttons["select-club-menasa"].tap()
        XCTAssertFalse(app.buttons["club-all-upcoming"].exists)

        app.buttons["club-create-event"].tap()
        app.textFields["Event title"].tap()
        app.textFields["Event title"].typeText("Club board games")
        app.textFields["Location"].tap()
        app.textFields["Location"].typeText("Student Union")
        app.buttons["Publish"].tap()
        XCTAssertTrue(app.navigationBars["Event"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Club board games"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let all = app.buttons["club-all-upcoming"]
        XCTAssertTrue(all.waitForExistence(timeout: 5))
        let previewRows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "club-event-"))
        XCTAssertEqual(previewRows.count, 3)
        all.tap()
        XCTAssertTrue(app.navigationBars["Events"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Upcoming"].isSelected)
        XCTAssertTrue(app.buttons["event-a1000000-0000-4000-8000-000000000003"].exists)
    }

    func testClubInvitationOpensClubPageAndPreservesDirectoryBackNavigation() throws {
        let app = openSample()
        app.tabBars.buttons["People"].tap()
        let url = try XCTUnwrap(URL(string: "clubconnect://join/menasa?sample=1"))
        app.terminate()
        app.launchArguments = []
        app.open(url)
        XCTAssertTrue(app.navigationBars["MENASA"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["club-event-a1000000-0000-4000-8000-000000000001"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Campus clubs"].waitForExistence(timeout: 5))
    }

    private func openSample() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ClubConnectFreshDemo", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.buttons["explore-demo"].tap()
        return app
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
