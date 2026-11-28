import XCTest

@MainActor
final class OnboardingTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone)
        continueAfterFailure = false
    }

    func testWelcomeAndReturningCodeEntry() {
        let app = welcome()
        capture("Campus welcome")
        app.buttons["usc-sign-in"].tap()
        XCTAssertTrue(app.staticTexts["Verify your USC email"].exists)
        let email = app.textFields["account-email"]
        email.tap()
        email.typeText("member@example.org")
        XCTAssertFalse(app.buttons["Email me a sign-in link"].isEnabled)
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["returning-sign-in"].tap()
        XCTAssertTrue(app.staticTexts["Welcome back"].exists)
        let returningEmail = app.textFields["account-email"]
        returningEmail.tap()
        returningEmail.typeText("member@example.org")
        app.buttons["I already have a code"].tap()
        XCTAssertTrue(app.staticTexts["Check your email"].exists)
        XCTAssertFalse(app.buttons["Verify email"].isEnabled)
        app.buttons["Use a different address"].tap()
        XCTAssertEqual(app.textFields["account-email"].value as? String, "member@example.org")
    }

    func testWarmAlumniInvitationOpensContextualEmailEntry() throws {
        let app = welcome()
        app.open(try XCTUnwrap(URL(string: "clubconnect://join/menasa?alumni=1")))
        XCTAssertTrue(app.staticTexts["Reconnect with your club"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Verify your personal email to create an alumni profile and request to join MENASA."].exists)
        capture("Alumni invitation")
        let email = app.textFields["account-email"]
        email.tap()
        email.typeText("alum@example.org")
        XCTAssertTrue(app.buttons["Email me a sign-in link"].isEnabled)
        app.open(try XCTUnwrap(URL(string: "clubconnect://join/menasa")))
    }

    // Hosted smoke checks use short-lived, mail-free fixture credentials supplied by the test runner.
    func testVerifiedCampusProfileAndReturningMember() throws {
        let fixture = try hostedFixture("CAMPUS")
        let app = welcome()
        app.buttons["usc-sign-in"].tap()
        verify(app, email: fixture.email, code: fixture.code)
        capture("Verified first profile")
        let next = app.buttons["onboarding-continue"]
        XCTAssertFalse(next.isEnabled)
        enterProfile(app, year: Calendar.current.component(.year, from: .now) + 2)
        XCTAssertFalse(next.isEnabled)
        app.buttons["standing-picker"].tap()
        app.buttons["Junior"].tap()
        next.tap()
        XCTAssertTrue(app.navigationBars["Your first club"].exists)
        capture("Choose your first club")
        app.buttons["onboarding-join"].tap()
        XCTAssertTrue(app.tabBars.buttons["Events"].waitForExistence(timeout: 20))
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Events"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.textFields["onboarding-name"].exists)
    }

    func testVerifiedAlumniCreatesProfileBeforeRequestingMembership() async throws {
        let fixture = try hostedFixture("ALUMNI")
        let env = ProcessInfo.processInfo.environment
        let firstID = try XCTUnwrap(env["CC_ONBOARDING_ALUMNI_CLUB"])
        let secondID = try XCTUnwrap(env["CC_ONBOARDING_ALUMNI_SECOND_CLUB"])
        let reviewer = try XCTUnwrap(env["CC_ONBOARDING_REVIEW_TOKEN"])
        let app = welcome()
        app.buttons["alumni-sign-up"].tap()
        XCTAssertTrue(app.staticTexts["Reconnect with your club"].waitForExistence(timeout: 8))
        verify(app, email: fixture.email, code: fixture.code)
        enterProfile(app, year: 2020)
        XCTAssertFalse(app.buttons["standing-picker"].exists)
        app.buttons["onboarding-continue"].tap()
        XCTAssertTrue(app.navigationBars["Alumni clubs"].waitForExistence(timeout: 18))
        XCTAssertFalse(app.tabBars.buttons["Messages"].exists)
        capture("Alumni club discovery")

        app.buttons["Account"].tap()
        app.buttons["Edit alumni profile"].tap()
        XCTAssertTrue(app.navigationBars["Edit profile"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["Major"].exists)
        app.buttons["Cancel"].tap()
        app.launchArguments = []
        app.open(try XCTUnwrap(URL(string: "clubconnect://join/" + firstID + "?alumni=1")))
        let first = app.buttons["alumni-club-" + firstID]
        let second = app.buttons["alumni-club-" + secondID]
        XCTAssertTrue(app.buttons["Request to join"].waitForExistence(timeout: 18))
        capture("Review an alumni club request")
        app.buttons["Request to join"].tap()
        await waitForLabel("Pending organizer review", on: first)
        second.tap()
        app.buttons["Request to join"].tap()
        await waitForLabel("Pending organizer review", on: second)
        XCTAssertTrue(first.label.contains("Pending"))
        capture("Two pending alumni memberships")

        app.terminate()
        app.launch()
        XCTAssertTrue(first.waitForExistence(timeout: 18))
        XCTAssertTrue(first.label.contains("Pending") && second.label.contains("Pending"))
        XCTAssertFalse(app.tabBars.buttons["People"].exists)
        first.tap()
        app.buttons["Withdraw request"].tap()
        app.buttons.matching(identifier: "Withdraw request").allElementsBoundByIndex.last?.tap()
        await waitForLabel("Withdrawn", on: first)
        first.tap()
        app.buttons["Request to join"].tap()
        await waitForLabel("Pending", on: first)
        try await decideFixture(clubID: firstID, reviewer: reviewer, approve: false)
        app.buttons["Refresh"].tap()
        await waitForLabel("Declined", on: first)
        XCTAssertTrue(second.label.contains("Pending"))
        capture("Declined and pending club requests")
        first.tap()
        app.buttons["Request to join"].tap()
        await waitForLabel("Pending", on: first)

        try await decideFixture(clubID: firstID, reviewer: reviewer, approve: true)
        app.buttons["Refresh"].tap()
        XCTAssertTrue(app.tabBars.buttons["People"].waitForExistence(timeout: 18))
        XCTAssertTrue(app.tabBars.buttons["Messages"].exists)
        app.tabBars.buttons["Clubs"].tap()
        if app.navigationBars["Alumni UI Fixture"].exists { app.navigationBars.buttons.firstMatch.tap() }
        let joinedFirst = app.buttons["select-club-" + firstID]
        let joinedSecond = app.buttons["select-club-" + secondID]
        XCTAssertTrue(joinedFirst.waitForExistence(timeout: 12))
        XCTAssertFalse(joinedSecond.exists)
        let pendingSecond = app.buttons["discover-club-" + secondID]
        XCTAssertTrue(pendingSecond.exists)
        capture("First club admitted with another request pending")
        pendingSecond.tap()
        XCTAssertTrue(app.staticTexts["Pending review"].waitForExistence(timeout: 5))
        app.buttons["Close"].tap()

        try await decideFixture(clubID: secondID, reviewer: reviewer, approve: true)
        app.buttons["Refresh memberships"].tap()
        XCTAssertTrue(joinedSecond.waitForExistence(timeout: 18))
        joinedSecond.tap()
        XCTAssertTrue(app.navigationBars["Alumni UI Studio"].waitForExistence(timeout: 8))
        app.navigationBars.buttons.firstMatch.tap()
        joinedFirst.tap()
        XCTAssertTrue(app.navigationBars["Alumni UI Fixture"].waitForExistence(timeout: 8))
    }

    func testVerifiedNonmemberCanDeleteTheirOwnAccount() throws {
        let fixture = try hostedFixture("DELETION")
        let app = welcome()
        app.buttons["alumni-sign-up"].tap()
        verify(app, email: fixture.email, code: fixture.code)
        app.buttons["Account"].tap()
        app.buttons["Delete account"].tap()
        XCTAssertTrue(app.buttons["Delete my account"].waitForExistence(timeout: 5))
        app.buttons["Delete my account"].tap()
        XCTAssertTrue(app.alerts["Account deleted"].waitForExistence(timeout: 18))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["returning-sign-in"].waitForExistence(timeout: 5))
    }

    private func waitForLabel(_ text: String, on element: XCUIElement) async {
        let status = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: element)
        await fulfillment(of: [status], timeout: 18)
    }

    /// Uses the separate fixture organizer while the applicant stays signed in on the simulator.
    private func decideFixture(clubID: String, reviewer: String, approve: Bool) async throws {
        let env = ProcessInfo.processInfo.environment
        let base = try XCTUnwrap(env["CC_ONBOARDING_PROJECT_URL"])
        let key = try XCTUnwrap(env["CC_ONBOARDING_PUBLIC_KEY"])
        func rpc(_ name: String, _ payload: [String: Any]) async throws -> Data {
            let url = try XCTUnwrap(URL(string: base + "/rest/v1/rpc/" + name))
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(key, forHTTPHeaderField: "apikey")
            request.setValue("Bearer " + reviewer, forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = try XCTUnwrap((response as? HTTPURLResponse)?.statusCode)
            XCTAssertTrue((200...299).contains(code))
            return data
        }
        let data = try await rpc("review_alumni_applications", ["c": clubID])
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let id = try XCTUnwrap(rows.first { ($0["status"] as? String) == "pending" }?["id"] as? String)
        _ = try await rpc("decide_alumni_application", ["c": clubID, "application_id": id, "approve": approve])
    }

    private func hostedFixture(_ role: String) throws -> (email: String, code: String) {
        let env = ProcessInfo.processInfo.environment
        guard let email = env["CC_ONBOARDING_" + role + "_EMAIL"],
              let code = env["CC_ONBOARDING_" + role + "_CODE"] else {
            throw XCTSkip("A disposable hosted onboarding fixture is required.")
        }
        return (email, code)
    }

    private func verify(_ app: XCUIApplication, email: String, code: String) {
        let field = app.textFields["account-email"]
        field.tap()
        field.typeText(email)
        app.buttons["I already have a code"].tap()
        let input = app.textFields["account-otp"]
        input.tap()
        input.typeText(code)
        app.buttons["Verify email"].tap()
        XCTAssertTrue(app.textFields["onboarding-name"].waitForExistence(timeout: 20))
    }

    private func enterProfile(_ app: XCUIApplication, year: Int) {
        let name = app.textFields["onboarding-name"]
        name.tap()
        name.typeText("Pilot Member")
        app.buttons["graduation-term-picker"].tap()
        app.buttons["Spring"].tap()
        let yearField = app.textFields["graduation-year-input"]
        yearField.tap()
        yearField.typeText(String(year))
    }

    private func welcome() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ClubConnectFreshDemo", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["usc-sign-in"].waitForExistence(timeout: 10))
        return app
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
