import XCTest

@MainActor
final class MessageFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testComposeSendAndReopenConversation() throws {
        let app = openSample()
        let messages = app.buttons["Messages"].firstMatch
        messages.tap()
        let row = app.descendants(matching: .any)["conversation-demo-yasmin"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8), app.debugDescription)
        capture("Messages inbox")
        app.buttons["New message"].firstMatch.tap()
        let yasmin = app.buttons["Yasmin Mansour"]
        XCTAssertTrue(yasmin.waitForExistence(timeout: 5), app.debugDescription)
        capture("Choose a message recipient")
        yasmin.tap()
        let field = app.descendants(matching: .any).matching(
            NSPredicate(format: "(elementType == %d OR elementType == %d) AND label == %@",
                        XCUIElement.ElementType.textField.rawValue, XCUIElement.ElementType.textView.rawValue,
                        "Message to Yasmin Mansour")).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        let body = "Thanks, Yasmin! How did you find your first engineering role?"
        let replies = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "You, \(body),"))
        field.tap()
        field.typeText(body)
        XCTAssertTrue(app.buttons["Send message"].isEnabled)
        app.buttons["Send message"].tap()
        XCTAssertTrue(replies.firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Send message"].isEnabled)

        app.terminate()
        app.launchArguments = []
        app.launch()
        if app.buttons["explore-demo"].waitForExistence(timeout: 2) { app.buttons["explore-demo"].tap() }
        messages.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 6))
        XCTAssertTrue(row.label.contains(body), row.label)
        row.tap()
        XCTAssertTrue(replies.firstMatch.waitForExistence(timeout: 6))
        capture("Conversation with Yasmin")
        app.buttons["View profile of Yasmin Mansour"].tap()
        XCTAssertTrue(app.navigationBars["Member profile"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Yasmin Mansour"].firstMatch.exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
    }

    func testDirectorySearchMatchesInterests() {
        let app = openSample()
        app.buttons["People"].firstMatch.tap()
        let profile = app.descendants(matching: .any)["member-demo-yasmin"].firstMatch
        XCTAssertTrue(profile.waitForExistence(timeout: 5), app.debugDescription)
        capture("People directory")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Mentorship")
        XCTAssertTrue(profile.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["member-demo-omar"].firstMatch.exists)
        profile.tap()
        XCTAssertTrue(app.navigationBars["Member profile"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Yasmin Mansour"].firstMatch.exists)
    }

    func testDirectoryAndRecipientWithAccessibilityText() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone)
        let app = openSample(largeText: true)
        app.buttons["People"].firstMatch.tap()
        let member = app.descendants(matching: .any)["member-demo-lina"].firstMatch
        XCTAssertTrue(member.waitForExistence(timeout: 5))
        capture("People at accessibility text sizes")
        member.tap()
        XCTAssertTrue(app.staticTexts["Lina Khoury"].waitForExistence(timeout: 5))
        app.buttons["Messages"].firstMatch.tap()
        app.buttons["New message"].firstMatch.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Film Studies")
        let recipient = app.buttons["Omar Benali"]
        XCTAssertTrue(recipient.waitForExistence(timeout: 5))
        recipient.tap()
        XCTAssertTrue(app.buttons["Send message"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Send message"].isEnabled)
    }

    private func openSample(largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ClubConnectFreshDemo", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        let sample = app.buttons["explore-demo"]
        XCTAssertTrue(sample.waitForExistence(timeout: 12))
        sample.tap()
        return app
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
