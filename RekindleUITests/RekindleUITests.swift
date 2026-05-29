import XCTest

final class RekindleUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.pranavsanghvi.rekindle")
        app.launch()
        sleep(2)
    }

    func capture(_ name: String) {
        let ss = XCUIScreen.main.screenshot()
        let att = XCTAttachment(screenshot: ss)
        att.name = name
        att.lifetime = .keepAlways
        add(att)
    }

    // MARK: - App Screens

    func testExploreAllScreens() throws {
        capture("1_Today")

        let tabs = app.tabBars.firstMatch

        tabs.buttons["Contacts"].tap()
        sleep(1)
        capture("2_Contacts")

        tabs.buttons["History"].tap()
        sleep(1)
        capture("3_History")

        tabs.buttons["Settings"].tap()
        sleep(1)
        capture("4_Settings")

        // Scroll to About section and verify version shows bundle value, not hardcoded "1.0.0"
        app.swipeUp()
        sleep(1)
        capture("4b_Settings_Scrolled")
        let versionText = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '2.'")).firstMatch
        XCTAssert(versionText.exists, "Settings should show bundle version (2.x), not hardcoded 1.0.0")

        tabs.buttons["Today"].tap()
        sleep(1)

        let morePicksBtn = app.buttons["Get More Picks"]
        if morePicksBtn.exists {
            morePicksBtn.tap()
            sleep(1)
            capture("5_More_Picks")
        }
    }

    // MARK: - Onboarding (drives the personalized-notification scheduling path)

    func testDriveOnboarding() throws {
        // Requires hasCompletedOnboarding=false in defaults (set externally before run).
        capture("onboarding_welcome")

        // Page 0 → 1
        let getStarted = app.buttons["Get Started"]
        if getStarted.waitForExistence(timeout: 5) {
            getStarted.tap()
            sleep(1)
        }
        // Page 1 → 2 (Contacts; permission already granted, just advances)
        let continueButtons = app.buttons.matching(NSPredicate(format: "label == 'Continue'"))
        if continueButtons.firstMatch.waitForExistence(timeout: 5) {
            continueButtons.firstMatch.tap()
            sleep(2)
        }
        // Page 2 (Notifications) → triggers schedulePersonalized + onComplete
        let cont2 = app.buttons.matching(NSPredicate(format: "label == 'Continue'")).firstMatch
        if cont2.waitForExistence(timeout: 5) {
            cont2.tap()
            sleep(3)
        }
        capture("onboarding_complete")
    }

    // MARK: - Widget (Small 2×2 and Medium 4×2)

    func testWidgets() throws {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

        // --- Step 1: Screenshot small widget on home screen ---
        XCUIDevice.shared.press(.home)
        sleep(2)
        capture("widget_small_home")

        // --- Step 2: Enter jiggle mode ---
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).press(forDuration: 2)
        sleep(2)
        capture("widget_jiggle_mode")

        // iOS 16-17: "+" top-left. iOS 18+: "Edit" -> "Add Widget".
        // Try "+" first, fall back to Edit flow.
        let plusBtn = springboard.buttons["+"]
        let editBtn = springboard.buttons["Edit"]

        if plusBtn.waitForExistence(timeout: 2) {
            plusBtn.tap()
        } else if editBtn.waitForExistence(timeout: 2) {
            editBtn.tap()
            sleep(1)
            capture("widget_edit_menu")
            // Look for "Add Widget" in the menu that appears
            let addWidgetOpt = springboard.buttons.matching(
                NSPredicate(format: "label CONTAINS 'Add Widget'")
            ).firstMatch
            if addWidgetOpt.waitForExistence(timeout: 2) {
                addWidgetOpt.tap()
            }
        }
        sleep(2)
        capture("widget_gallery_opened")

        // Search for Rekindle in the widget gallery
        let searchField = springboard.searchFields.firstMatch
        if searchField.waitForExistence(timeout: 4) {
            searchField.tap()
            searchField.typeText("Rekindle")
            sleep(1)
            capture("widget_search_results")

            let cell = springboard.cells.matching(
                NSPredicate(format: "label CONTAINS[c] 'Rekindle'")
            ).firstMatch
            if cell.waitForExistence(timeout: 3) {
                cell.tap()
                sleep(1)
                capture("widget_size_small")

                // Swipe to medium
                springboard.scrollViews.firstMatch.swipeLeft()
                sleep(1)
                capture("widget_size_medium")

                let addBtn = springboard.buttons.matching(
                    NSPredicate(format: "label CONTAINS 'Add Widget'")
                ).firstMatch
                if addBtn.waitForExistence(timeout: 3) {
                    addBtn.tap()
                    sleep(1)
                }
            }
        }

        // Exit jiggle mode
        let doneBtn = springboard.buttons["Done"]
        if doneBtn.waitForExistence(timeout: 3) {
            doneBtn.tap()
            sleep(1)
        }
        XCUIDevice.shared.press(.home)
        sleep(1)
        capture("widget_medium_home_screen")
    }
}
