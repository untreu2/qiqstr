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

    func testProfileHeaderAlignment() {
        assertProfileHeaderAlignment(contentSize: "UICTContentSizeCategoryL")
    }

    func testProfileHeaderAlignmentAtLargestAccessibilitySize() {
        assertProfileHeaderAlignment(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
    }

    func testDisconnectedWalletHasNoGetWalletSection() {
        let app = signedInApp(contentSize: "UICTContentSizeCategoryL")
        app.buttons["Wallet"].tap()
        let onboarding = app.descendants(matching: .any)["wallet-onboarding"].firstMatch
        XCTAssertTrue(onboarding.waitForExistence(timeout: 10), "This test requires the stored test account to have no connected wallet.")

        let connect = app.buttons["wallet-connect"]
        for _ in 0..<8 {
            XCTAssertFalse(app.staticTexts["Get a wallet"].exists)
            XCTAssertFalse(app.buttons["wallet-provider-coinos"].exists)
            if connect.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(connect.isHittable, "The wallet connection controls must remain reachable.")
        app.swipeUp()
        XCTAssertFalse(app.staticTexts["Get a wallet"].exists)
        XCTAssertTrue(app.buttons["wallet-connect-scan"].exists)
        attachScreenshot(app, name: "Wallet without provider recommendations")
    }

    func testSettingsOffersAccountDeletionContactAndTerms() {
        let app = signedInApp(contentSize: "UICTContentSizeCategoryL")
        let notNow = app.buttons["Not now"]
        if notNow.waitForExistence(timeout: 8) { notNow.tap() }
        let profile = app.navigationBars.buttons["Profile"].firstMatch
        XTCAssertExists(profile)
        profile.tap()
        let settings = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Settings")).firstMatch
        XTCAssertExists(settings)
        settings.tap()
        let list = app.collectionViews["settings-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        let delete = app.buttons["settings-delete-account"]
        for _ in 0..<6 where !delete.isHittable { list.swipeUp() }
        XCTAssertTrue(delete.isHittable, "Account deletion must be reachable from Settings.")
        XCTAssertTrue(app.buttons["settings-contact"].exists, "A support contact must be reachable from Settings.")
        XCTAssertTrue(app.buttons["settings-terms"].exists)
        app.buttons["settings-terms"].tap()
        XCTAssertTrue(app.staticTexts["qiqstr has zero tolerance for objectionable content and abusive users."].waitForExistence(timeout: 5) || app.otherElements["terms-sheet"].exists)
    }

    func testComposerRefusesToPublishAPrivateKey() {
        let app = signedInApp(contentSize: "UICTContentSizeCategoryL")
        let notNow = app.buttons["Not now"]
        if notNow.waitForExistence(timeout: 8) { notNow.tap() }
        let compose = app.buttons["feed-compose"]
        XTCAssertExists(compose)
        compose.tap()
        let text = app.textViews["compose-text"]
        XTCAssertExists(text)
        text.tap()
        text.typeText("my key nsec1vl029mgpspedva04g90vltkh6fvh240zqtv9k0t9af8935ke9laqsnlfe5")
        app.buttons["compose-post"].tap()
        let toast = app.descendants(matching: .any)["toast"].firstMatch
        XCTAssertTrue(toast.waitForExistence(timeout: 5), "The warning must be visible above the composer sheet.")
        XCTAssertTrue(app.textViews["compose-text"].exists, "The composer must stay open with the text.")
        app.buttons["compose-cancel"].tap()
        let discard = app.buttons["compose-discard"].firstMatch
        if discard.waitForExistence(timeout: 3) { discard.tap() }
    }

    private func XTCAssertExists(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), file: file, line: line)
    }

    private func signedInApp(contentSize: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-QIQ_LOGIN", Self.randomKeyHex(),
            "-UIPreferredContentSizeCategoryName", contentSize,
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-theme_preference", "system"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 40), "The stored test account or generated fallback must reach Home.")
        return app
    }

    private func assertProfileHeaderAlignment(contentSize: String) {
        let app = signedInApp(contentSize: contentSize)
        app.open(URL(string: "nostr:npub1vm08zv4rmmkxmtm57sxtvaflxgrpe2xfyq7736vk7rse76u82xhs8cwl68")!)

        let avatar = app.buttons["profile-avatar"]
        let name = app.staticTexts["profile-name"]
        let npub = app.buttons["profile-copy-npub"]
        XCTAssertTrue(avatar.waitForExistence(timeout: 30), "The test profile must open.")
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        XCTAssertTrue(npub.waitForExistence(timeout: 10))

        let screen = app.windows.firstMatch.frame
        let avatarFrame = avatar.frame
        let nameFrame = name.frame
        XCTAssertEqual(avatarFrame.minX + 4, nameFrame.minX, accuracy: 1, "The photo inside its 4-point border and the name must share a leading edge.")
        XCTAssertGreaterThanOrEqual(nameFrame.minY, avatarFrame.maxY, "The name must sit below the avatar.")
        assertHorizontalBounds(nameFrame, screen: screen)

        let share = app.buttons["profile-share"]
        XCTAssertTrue(share.waitForExistence(timeout: 10))
        var actions = [share]
        if app.buttons["profile-edit"].exists {
            actions.append(app.buttons["profile-edit"])
        } else {
            let message = app.buttons["profile-message"]
            XCTAssertTrue(message.exists)
            actions.append(message)
            let follow = app.buttons.matching(NSPredicate(format: "identifier IN %@", ["follow-button", "unfollow-button"])).firstMatch
            XCTAssertTrue(follow.exists)
            actions.append(follow)
            if app.buttons["profile-zap"].exists { actions.append(app.buttons["profile-zap"]) }
        }
        let actionFrames = actions.map(\.frame)
        for (index, frame) in actionFrames.enumerated() {
            assertHorizontalBounds(frame, screen: screen)
            XCTAssertGreaterThanOrEqual(frame.minY, screen.minY)
            XCTAssertLessThanOrEqual(frame.maxY, screen.maxY)
            XCTAssertFalse(frame.intersects(avatarFrame), "Profile actions must not overlap the avatar.")
            XCTAssertLessThanOrEqual(frame.maxY, nameFrame.minY, "Profile actions must remain above the name.")
            for other in actionFrames.dropFirst(index + 1) {
                XCTAssertFalse(frame.intersects(other), "Profile actions must not overlap each other.")
            }
        }

        for identifier in ["profile-following-count", "profile-followers-count"] {
            let count = app.buttons[identifier]
            XCTAssertTrue(count.waitForExistence(timeout: 10))
            let frame = count.frame
            assertHorizontalBounds(frame, screen: screen)
            XCTAssertGreaterThanOrEqual(frame.minY, npub.frame.maxY, "Counts must appear below the profile identity.")
        }
        attachScreenshot(app, name: "Profile header \(contentSize)")
    }

    private func assertHorizontalBounds(_ frame: CGRect, screen: CGRect) {
        XCTAssertGreaterThan(frame.width, 0)
        XCTAssertGreaterThan(frame.height, 0)
        XCTAssertGreaterThanOrEqual(frame.minX, screen.minX)
        XCTAssertLessThanOrEqual(frame.maxX, screen.maxX)
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private static func randomKeyHex() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        bytes[0] = max(bytes[0] & 0x7F, 1)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
