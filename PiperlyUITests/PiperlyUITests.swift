import XCTest

final class PiperlyUITests: XCTestCase {
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()
    }

    func testICloudControlsAreBehindParentGate() throws {
        let app = XCUIApplication()
        app.launch()

        let continueButton = app.buttons["Continue"]
        if continueButton.waitForExistence(timeout: 2) {
            continueButton.tap()
        }

        app.buttons["Settings"].tap()
        app.staticTexts["iCloud Sync"].tap()

        let parentCheck = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Parent check:'")
        ).firstMatch
        XCTAssertTrue(parentCheck.waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["Enable iCloud Sync"].exists)
        XCTAssertTrue(app.textFields["Parent check answer"].exists)
    }
}
