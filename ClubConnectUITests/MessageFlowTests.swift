import XCTest

final class MessageFlowTests: XCTestCase {
    @MainActor
    func testComposeSendAndReopenConversation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ClubConnectFreshDemo", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let sample = app.buttons["explore-demo"]
        XCTAssertTrue(sample.waitForExistence(timeout: 12))
        sample.tap()
        let messages = app.tabBars.buttons["Messages"]
        XCTAssertTrue(messages.waitForExistence(timeout: 8))
        messages.tap()
        let compose = app.buttons["New message"].firstMatch
        XCTAssertTrue(compose.waitForExistence(timeout: 8))
        compose.tap()
        let yasmin = app.buttons["Yasmin Mansour"]
        XCTAssertTrue(yasmin.waitForExistence(timeout: 5))
        yasmin.tap()
        let field = app.descendants(matching: .any).matching(
            NSPredicate(format: "(elementType == %d OR elementType == %d) AND label == %@",
                        XCUIElement.ElementType.textField.rawValue, XCUIElement.ElementType.textView.rawValue,
                        "Message to Yasmin Mansour")).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        let body = "Hello from campus " + UUID().uuidString.prefix(4)
        field.typeText(String(body))
        app.buttons["Send message"].tap()
        let sent = app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@", "You, \(body),")).firstMatch
        XCTAssertTrue(sent.waitForExistence(timeout: 8))

        app.terminate()
        app.launch()
        if sample.waitForExistence(timeout: 4) { sample.tap() }
        XCTAssertTrue(messages.waitForExistence(timeout: 8))
        messages.tap()
        let row = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", body)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 6))
        row.tap()
        XCTAssertTrue(sent.waitForExistence(timeout: 6))
    }
}
