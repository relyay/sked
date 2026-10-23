import XCTest

/// UI test of the first-run flow. XCUITest needs Xcode on a Mac: generate a
/// project with `xtool dev generate-xcode-project`, add a UI Testing target
/// containing this file, and run it against a skedd instance:
///
///     SKED_ADMIN_SECRET=x go run ./cmd/skedd -addr 127.0.0.1:1984
final class OnboardingUITests: XCTestCase {
    private var app: XCUIApplication!

    // The app runs in Russian here, so the test types and looks up Russian
    // values (tab title, name, group) as they appear on screen.
    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        app.launchEnvironment = [
            "SKED_SERVER_URL": ProcessInfo.processInfo.environment["SKED_SERVER_URL"] ?? "http://127.0.0.1:1984",
        ]
        app.launch()
    }

    func testSaveIsBlockedUntilGroupChosen() {
        let save = app.buttons["onboarding.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled)

        let name = app.textFields["onboarding.name"]
        name.tap()
        name.typeText("Иванов Иван Иванович")
        XCTAssertFalse(save.isEnabled, "group is still missing")
    }

    func testCompletingOnboardingOpensHome() {
        let name = app.textFields["onboarding.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Иванов Иван Иванович")

        let group = app.buttons["onboarding.group"]
        XCTAssertTrue(group.waitForExistence(timeout: 10), "groups must load from the server")
        group.tap()
        app.searchFields.firstMatch.tap()
        app.searchFields.firstMatch.typeText("225а")
        app.buttons["ИСП-225а"].tap()

        app.segmentedControls["onboarding.subgroup"].buttons["2"].tap()

        let save = app.buttons["onboarding.save"]
        XCTAssertTrue(save.isEnabled)
        save.tap()

        XCTAssertTrue(app.tabBars.buttons["Главная"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["home.currentLesson"].waitForExistence(timeout: 10)
            || app.staticTexts["home.currentLesson"].exists)
    }

    func testUnreachableServerShowsRetry() {
        app.terminate()
        app.launchEnvironment["SKED_SERVER_URL"] = "http://127.0.0.1:9"
        app.launch()
        XCTAssertTrue(app.buttons["retry"].waitForExistence(timeout: 30))
    }
}
