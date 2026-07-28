import XCTest

@MainActor
final class VacuumUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testMenuBarApplicationLaunches() {
        let application = XCUIApplication()
        application.launchArguments += ["-vacuumUITesting", "YES"]
        application.launch()

        let state = application.state
        XCTAssertTrue(
            state == .runningForeground || state == .runningBackground,
            "Expected Vacuum to be running, but state was \(state.rawValue)."
        )
    }
}
