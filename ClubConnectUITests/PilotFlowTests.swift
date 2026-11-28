import XCTest

@MainActor
final class PilotFlowTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "These flows exercise the iPhone tab bar and compact navigation.")
        continueAfterFailure = false
    }

    func testOrganizerPublishesEventAndChecksInTicket() throws {
        let app = launchDemo()
        app.tabBars.buttons["Events"].tap()
        XCTAssertTrue(app.buttons["Create event"].waitForExistence(timeout: 5))
        attachScreenshot("Events on iPhone")

        app.buttons["Create event"].tap()
        app.textFields["Event title"].tap()
        app.textFields["Event title"].typeText("Pilot coffee hour")
        app.textFields["Location"].tap()
        app.textFields["Location"].typeText("Student Union")
        app.buttons["Publish"].tap()

        XCTAssertTrue(app.staticTexts["Pilot coffee hour"].waitForExistence(timeout: 5))
        app.buttons["RSVP"].tap()
        let ticketCode = app.descendants(matching: .any)["event-ticket-code"].firstMatch
        XCTAssertTrue(ticketCode.waitForExistence(timeout: 5))
        let walletStatus = app.descendants(matching: .any)["wallet-status"].firstMatch
        XCTAssertTrue(walletStatus.exists, "The offline fixture should explain how to get a Wallet pass.")
        let code = ticketCode.label.isEmpty ? (try XCTUnwrap(ticketCode.value as? String)) : ticketCode.label
        XCTAssertFalse(code.isEmpty)
        app.buttons["Done"].tap()

        app.buttons["Manage event"].tap()
        app.buttons["Check in members"].tap()
        let field = app.textFields["Ticket code"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(code)
        app.buttons["Check in member"].tap()
        XCTAssertTrue(app.staticTexts["Noor Haddad is checked in."].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()

        app.buttons["View ticket"].tap()
        XCTAssertTrue(app.staticTexts["Checked in"].waitForExistence(timeout: 5))
        XCTAssertFalse(ticketCode.exists)
    }

    func testProfileChangesAppearInDirectory() {
        let app = launchDemo()
        app.tabBars.buttons["Profile"].tap()
        app.buttons["Edit profile"].tap()
        let major = app.textFields["Major"]
        XCTAssertTrue(major.waitForExistence(timeout: 5))
        major.tap()
        major.typeText(" and Design")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Architecture and Design"].waitForExistence(timeout: 5))

        app.tabBars.buttons["People"].tap()
        app.buttons["Alumni"].tap()
        let alumni = app.descendants(matching: .any)["member-demo-yasmin"].firstMatch
        XCTAssertTrue(alumni.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["member-demo-organizer"].firstMatch.exists)
        alumni.tap()
        XCTAssertTrue(app.navigationBars["Member profile"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Yasmin Mansour"].exists)

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Students"].tap()
        let student = app.descendants(matching: .any)["member-demo-organizer"].firstMatch
        XCTAssertTrue(student.waitForExistence(timeout: 5))
        student.tap()
        XCTAssertTrue(app.staticTexts["Architecture and Design"].waitForExistence(timeout: 5))
    }

    func testGraduationProfileAndAlumniDirectory() throws {
        let app = launchDemo()
        app.tabBars.buttons["Profile"].tap()
        let name = app.staticTexts["Noor Haddad"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.frame.midX, app.frame.midX, accuracy: 3)
        attachScreenshot("Centered member profile")

        app.buttons["Edit profile"].tap()
        let year = app.textFields["graduation-year-input"]
        if !year.exists { app.swipeUp() }
        XCTAssertTrue(year.waitForExistence(timeout: 5), app.debugDescription)
        let existingYear = try XCTUnwrap(year.value as? String)
        year.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        year.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existingYear.count))
        year.typeText("2004")
        XCTAssertEqual(year.value as? String, "2004")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Alumni"].waitForExistence(timeout: 5))

        app.tabBars.buttons["People"].tap()
        app.buttons["Students"].tap()
        let changedMember = app.descendants(matching: .any)["member-demo-organizer"].firstMatch
        XCTAssertFalse(changedMember.exists)
        app.buttons["Alumni"].tap()
        XCTAssertTrue(changedMember.waitForExistence(timeout: 5))
        changedMember.tap()
        XCTAssertTrue(app.staticTexts["Noor Haddad"].waitForExistence(timeout: 5))
    }

    func testCalendarEditorContainsSelectedEvent() {
        let app = launchDemo()
        app.tabBars.buttons["Events"].tap()
        app.buttons["event-a1000000-0000-4000-8000-000000000001"].tap()
        app.buttons["Add to Calendar"].tap()

        let titleField = app.descendants(matching: .any)
            .matching(NSPredicate(format: "value == %@", "Coffee at the Majlis")).firstMatch
        XCTAssertTrue(titleField.waitForExistence(timeout: 12))
        XCTAssertTrue(app.buttons["Cancel"].exists)
    }

    func testDarkModeEventDetailAccessibility() throws {
        let device = XCUIDevice.shared
        let original = device.appearance
        defer { device.appearance = original }
        let app = launchDemo()
        device.appearance = .dark
        app.tabBars.buttons["Events"].tap()
        app.buttons["event-a1000000-0000-4000-8000-000000000001"].tap()
        XCTAssertTrue(app.buttons["RSVP"].waitForExistence(timeout: 5))
        attachScreenshot("Event detail in dark mode")
        try auditVisibleControls(in: app)
    }

    func testLargeTextEventNavigationAndAccessibility() throws {
        let app = launchDemo(extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        app.tabBars.buttons["Events"].tap()
        XCTAssertTrue(app.buttons["event-filter-menu"].waitForExistence(timeout: 5))
        attachScreenshot("Events at largest accessibility size")
        try auditVisibleControls(in: app)

        let coffee = app.buttons["event-a1000000-0000-4000-8000-000000000001"]
        XCTAssertTrue(coffee.exists)
        coffee.tap()
        XCTAssertTrue(app.buttons["RSVP"].waitForExistence(timeout: 5))
        try auditVisibleControls(in: app)
    }

    private func auditVisibleControls(in app: XCUIApplication) throws {
        try app.performAccessibilityAudit(for: [.contrast, .hitRegion, .sufficientElementDescription, .textClipped]) { issue in
            XCTContext.runActivity(named: issue.detailedDescription) { activity in
                if let element = issue.element {
                    activity.add(XCTAttachment(string: element.debugDescription))
                }
            }
            return false
        }
    }

    private func launchDemo(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ClubConnectFreshDemo", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + extraArguments
        app.launch()
        let explore = app.buttons["explore-demo"]
        XCTAssertTrue(explore.waitForExistence(timeout: 10))
        explore.tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        return app
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
