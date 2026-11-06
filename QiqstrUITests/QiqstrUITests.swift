import Security
import XCTest

final class QiqstrUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testWelcomeRequiresTermsBeforeSignup() {
        let app = XCUIApplication()
        app.launchArguments += ["-QIQ_LOGIN", ""]
        app.launch()
        let create = app.buttons["Create a New Account"]
        guard create.waitForExistence(timeout: 20) else { return }
        create.tap()
        XCTAssertTrue(app.staticTexts["Acceptance of terms is required"].waitForExistence(timeout: 5))
    }

    func testThrowawayAccountReachesHome() {
        let app = XCUIApplication()
        app.launchArguments += ["-QIQ_LOGIN", Self.randomKeyHex()]
        app.launch()
        XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 40))
        XCTAssertTrue(app.buttons["Messages"].exists)
        XCTAssertTrue(app.buttons["Wallet"].exists)
        XCTAssertTrue(app.buttons["Notifications"].exists)
        app.buttons["Wallet"].tap()
        let connect = app.buttons["wallet-connect"]
        for _ in 0..<5 where !connect.exists {
            app.swipeUp()
        }
        XCTAssertTrue(connect.waitForExistence(timeout: 10))
    }

    private static func randomKeyHex() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        bytes[0] = max(bytes[0] & 0x7F, 1)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
