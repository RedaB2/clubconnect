import XCTest

@MainActor
final class AdaptiveInterfaceTests: XCTestCase {
    func testIPadEventAndDirectoryDetails() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        let app = XCUIApplication()
        app.launchArguments = ["-ClubConnectFreshDemo"]
        app.launch()
        record("Welcome on iPad")
        app.buttons["explore-demo"].tap()
        let coffee = app.descendants(matching: .button).matching(NSPredicate(format: "label CONTAINS[c] %@", "Coffee at the Majlis")).firstMatch
        XCTAssertTrue(coffee.waitForExistence(timeout: 10), app.debugDescription)
        coffee.tap()
        XCTAssertTrue(app.buttons["RSVP"].waitForExistence(timeout: 5), app.debugDescription)
        record("Event details on iPad")
        let people = app.buttons["People"].firstMatch
        XCTAssertTrue(people.waitForExistence(timeout: 5), app.debugDescription)
        people.tap()
        let member = app.descendants(matching: .any)["member-demo-yasmin"].firstMatch
        XCTAssertTrue(member.waitForExistence(timeout: 5), app.debugDescription)
        member.tap()
        XCTAssertTrue(app.staticTexts["Software engineer"].waitForExistence(timeout: 5))
        record("Directory on iPad")
    }

    func testSharedEventRestoresSessionOnColdLaunch() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        let app = XCUIApplication()
        app.launchArguments = ["-ClubConnectFreshDemo"]
        app.launch()
        app.buttons["explore-demo"].tap()
        app.buttons["People"].firstMatch.tap()
        let url = try XCTUnwrap(URL(string: "clubconnect://event/a1000000-0000-4000-8000-000000000002?sample=1"))
        app.terminate()
        app.launchArguments = []
        app.open(url)
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["After graduation"].firstMatch.exists)
        XCTAssertTrue(app.buttons["RSVP"].exists)
        app.buttons["Close"].tap()
    }

    private func record(_ title: String) {
        let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        capture.name = title
        capture.lifetime = .keepAlways
        add(capture)
    }
}
