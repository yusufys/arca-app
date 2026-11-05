import XCTest
final class UXFlowsTests: XCTestCase {
    let bundle = "app.arca.acceptance.uxflows20261105"
    func launch(_ screen: String, _ lang: String, large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: bundle)
        app.launchArguments = ["-arca.language", lang]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launchEnvironment = ["ARCA_API_BASE_URL":"http://127.0.0.1:19274", "ARCA_FLOW_SCREEN": screen]
        app.launch()
        let loaded = NSPredicate { _,_ in app.staticTexts.count > 0 && !app.staticTexts["Loading fixture"].exists }
        expectation(for: loaded, evaluatedWith: app); waitForExpectations(timeout: 30)
        return app
    }
    func shot(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
    }
    func reveal(_ app: XCUIApplication, _ element: XCUIElement) {
        for _ in 0..<10 { if element.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
    func onboarding(_ lang: String) {
        let app = launch("onboarding", lang)
        shot(app, "\(lang)-01-welcome-top")
        reveal(app, app.buttons["onboarding.getStarted"])
        shot(app, "\(lang)-02-welcome-bottom")
        app.buttons["onboarding.getStarted"].tap()
        XCTAssertTrue(app.buttons["onboarding.continue"].waitForExistence(timeout: 5))
        shot(app, "\(lang)-03-storage-top")
        let consent = app.buttons["onboarding.acceptCloud"]
        reveal(app, consent); consent.tap()
        reveal(app, app.buttons["onboarding.continue"])
        shot(app, "\(lang)-04-storage-consent")
        app.buttons["onboarding.continue"].tap()
        let email = app.textFields["account.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        shot(app, "\(lang)-05-sign-in")
        email.tap(); email.typeText("designer@example.com")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        shot(app, "\(lang)-06-email-keyboard")
        // A tap inside the input keeps editing. A tap outside dismisses it.
        email.tap(); XCTAssertTrue(app.keyboards.firstMatch.exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(email.value as? String, "designer@example.com")
        shot(app, "\(lang)-07-keyboard-dismissed")
        let create = app.segmentedControls.buttons.element(boundBy: 1)
        create.tap(); shot(app, "\(lang)-08-create-account")
        let skip = app.buttons["onboarding.skipAccount"]
        reveal(app, skip); skip.tap()
        shot(app, "\(lang)-09-onboarding-templates-top")
        app.swipeUp(); shot(app, "\(lang)-10-onboarding-templates-bottom")
        app.terminate()
    }
    func flows(_ lang: String) {
        continueAfterFailure = false
        onboarding(lang)
        let screens = ["home", "spaces", "templates", "ai", "manual", "collection", "record-new", "record-edit", "record-detail", "fields", "sensitive", "insights", "settings", "backups", "sync", "devices", "migration", "privacy", "plan"]
        for (index, screen) in screens.enumerated() {
            let app = launch(screen, lang)
            shot(app, "\(lang)-\(20+index)-\(screen)-top")
            if app.scrollViews.count > 0 { app.swipeUp(); shot(app, "\(lang)-\(20+index)-\(screen)-bottom") }
            if screen == "ai" {
                let existing = app.buttons["aiCollection.existingReply"]
                reveal(app, existing); existing.tap()
                shot(app, "\(lang)-40-ai-import")
            }
            app.terminate()
        }
    }
    func testEnglishFlows() { flows("en") }
    func testArabicFlows() { flows("ar") }
    func testTurkishFlows() { flows("tr") }
    func testLargeTextAndLanguageSwitch() throws {
        let app = launch("onboarding", "en", large: true)
        shot(app, "accessibility-01-largest-welcome")
        app.buttons["onboarding.language"].tap()
        app.buttons["العربية"].tap()
        XCTAssertTrue(app.staticTexts["سجلاتك. بطريقتك."].waitForExistence(timeout: 5))
        shot(app, "accessibility-02-largest-arabic")
        // Apple's audit verifies that interactive elements have useful descriptions.
        try app.performAccessibilityAudit(for: [.elementDetection])
        app.terminate()
        let settings = launch("settings", "ar", large: true)
        shot(settings, "accessibility-03-largest-settings")
        settings.swipeUp(); shot(settings, "accessibility-04-largest-settings-bottom")
        settings.terminate()
    }
    func testUpdatedScreensAndAIFlow() throws {
        continueAfterFailure = false
        for lang in ["en", "ar", "tr"] {
            let screens = [(20,"home"),(21,"spaces"),(24,"manual"),(26,"record-new"),(27,"record-edit"),(29,"fields"),(32,"settings"),(31,"insights")]
            for (index, screen) in screens {
                let app = launch(screen, lang)
                shot(app, "\(lang)-\(index)-\(screen)-top")
                if screen == "manual" { try app.performAccessibilityAudit(for: [.elementDetection]) }
                if app.scrollViews.count > 0 {
                    for page in 2...4 {
                        app.swipeUp()
                        shot(app, "\(lang)-\(index)-\(screen)-" + (page == 2 ? "bottom" : "page\(page)"))
                    }
                }
                app.terminate()
            }
            let app = launch("ai", lang)
            let input = app.descendants(matching: .any)["aiCollection.intent"].firstMatch
            input.tap(); input.typeText("Organize my household equipment")
            reveal(app, app.buttons["aiCollection.prepare"]); app.buttons["aiCollection.prepare"].tap()
            XCTAssertTrue(app.buttons["aiCollection.copyPrompt"].waitForExistence(timeout: 15))
            shot(app, "\(lang)-41-ai-prepared-prompt")
            let reply = app.textViews["aiCollection.reply"]
            reveal(app, reply); reply.tap()
            reply.typeText("not JSON")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
            reveal(app, app.buttons["aiCollection.preview"]); app.buttons["aiCollection.preview"].tap()
            XCTAssertTrue(app.staticTexts["aiCollection.error"].waitForExistence(timeout: 5))
            shot(app, "\(lang)-42-ai-invalid-reply")
            reply.tap()
            reply.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8))
            reply.typeText(#"{"name":"Design sample","fields":[{"label":"Item","type":"short_text","isPrimaryTitle":true}]}"#)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
            reveal(app, app.buttons["aiCollection.preview"]); app.buttons["aiCollection.preview"].tap()
            XCTAssertTrue(app.buttons["aiCollection.create"].waitForExistence(timeout: 5))
            shot(app, "\(lang)-43-ai-schema-preview")
            app.terminate()
        }
    }

    func testLargeControls() throws {
        for screen in ["manual", "sync", "home", "insights"] {
            let app = launch(screen, "ar", large: true)
            shot(app, "accessibility-large-\(screen)-top")
            if screen == "manual" || screen == "sync" { try app.performAccessibilityAudit(for: [.elementDetection]) }
            app.swipeUp(); shot(app, "accessibility-large-\(screen)-bottom")
            app.terminate()
        }
    }

    func testConnectedAccountAndFinalDetails() throws {
        continueAfterFailure = false
        let deletion = ["en":"Delete Cloud Account", "ar":"حذف الحساب السحابي", "tr":"Bulut Hesabını Sil"]
        for lang in ["en", "ar", "tr"] {
            for (number, screen) in [(28,"record-detail"),(29,"fields"),(26,"record-new"),(32,"settings"),(44,"connected-sync"),(45,"connected-devices")] {
                let app = launch(screen, lang)
                XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Fixture failed:")).firstMatch.exists)
                shot(app, "\(lang)-\(number)-\(screen)-top")
                if screen == "connected-sync" {
                    let button = app.buttons[deletion[lang]!]
                    reveal(app, button); button.tap()
                    shot(app, "\(lang)-46-delete-account-confirmation")
                } else if app.scrollViews.count > 0 {
                    for page in 2...4 {
                        app.swipeUp(); shot(app, "\(lang)-\(number)-\(screen)-" + (page == 2 ? "bottom" : "page\(page)"))
                    }
                }
                app.terminate()
            }
        }
    }

}
