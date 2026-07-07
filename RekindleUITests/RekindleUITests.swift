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

    // MARK: - Favorites (requires favorites enabled + at least one favorite contact in the store)

    func testFavoritesFlow() throws {
        let tabs = app.tabBars.firstMatch

        // --- Settings: favorites section + deep link ---
        tabs.buttons["Settings"].tap()
        sleep(1)
        // Scroll a touch in case the section is below the fold
        let favSwitch = app.switches["Favorite picks"]
        XCTAssertTrue(favSwitch.waitForExistence(timeout: 4), "Settings should show the Favorite picks toggle")
        capture("fav_1_settings")

        // Manage Favorites sits at the bottom of the form — scroll it into view, then require it.
        app.swipeUp()
        sleep(1)
        let manage = app.buttons["manageFavorites"]
        XCTAssertTrue(manage.waitForExistence(timeout: 4), "Settings should show Manage Favorites")
        manage.tap()
        sleep(1)
        capture("fav_2_manage_lands_contacts")
        // Deep link should land on Contacts → Favorites with our favorite visible
        XCTAssertTrue(
            app.staticTexts["Kate Bell"].waitForExistence(timeout: 4),
            "Manage Favorites should deep-link to the Favorites filter showing the favorite contact"
        )

        // --- Today: favorite card + expand + remove confirmation ---
        tabs.buttons["Today"].tap()
        sleep(1)
        app.swipeUp()
        sleep(1)
        capture("fav_3_today_keep_close")

        let kate = app.staticTexts["Kate Bell"]
        if kate.waitForExistence(timeout: 3) {
            kate.tap() // expand the favorite card
            sleep(1)
            capture("fav_4_expanded")

            let remove = app.buttons["Remove from Favorites"]
            if remove.waitForExistence(timeout: 3) {
                remove.tap()
                sleep(1)
                capture("fav_5_remove_confirm")
                // Confirmation alert must appear; Cancel keeps the favorite
                XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 3), "Remove should prompt a confirmation alert")
                if app.alerts.buttons["Cancel"].exists {
                    app.alerts.buttons["Cancel"].tap()
                }
            }
        }
    }

    // MARK: - Favorites empty state (requires no favorites in the store)

    func testFavoritesEmptyState() throws {
        let tabs = app.tabBars.firstMatch
        tabs.buttons["Contacts"].tap()
        sleep(1)
        // Tap the "Favorites" segment
        let favSegment = app.buttons["Favorites"]
        if favSegment.waitForExistence(timeout: 3) {
            favSegment.tap()
            sleep(1)
        }
        capture("fav_empty_state")
        // Precondition: no favorites in the store. testFavoritesFlow needs the
        // opposite, so skip (not fail) when a favorite exists in this run.
        if !app.buttons["Browse contacts"].waitForExistence(timeout: 3) {
            if app.staticTexts["Kate Bell"].exists {
                throw XCTSkip("Store has favorites; empty state not reachable in this run")
            }
            XCTFail("Favorites empty state should offer a 'Browse contacts' button")
        }
    }

    // MARK: - Limited contacts access (iOS 18+)
    // Drives the real permission prompt end-to-end: choose "Select Contacts",
    // pick two, and verify the app treats limited access as having access
    // (contacts list + banner, Settings "Limited" + Manage row).
    // Requires contacts permission to be un-determined — reset it first with:
    //   xcrun simctl privacy <device> reset contacts com.pranavsanghvi.rekindle
    // Skips (rather than fails) when permission is already granted.
    // The picker is a system remote view, so rows are tapped by screen
    // coordinate — sized for the iPhone "17.1" simulator used by this suite.

    func testLimitedAccessFlow() throws {
        let tabs = app.tabBars.firstMatch
        tabs.buttons["Contacts"].tap()
        sleep(1)
        capture("p1_gate")

        let allow = app.buttons["Allow Access"]
        guard allow.waitForExistence(timeout: 4) else {
            throw XCTSkip("Contacts permission already determined — reset it via simctl to run this test")
        }
        allow.tap()
        sleep(2)

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        capture("p2_prompt")

        // Two-step prompt on this iOS: "Continue" first, then the access-level choice
        let cont = springboard.buttons["Continue"]
        if cont.waitForExistence(timeout: 3) {
            cont.tap()
            sleep(2)
        }
        capture("p2b_access_choice")

        // Pick the limited-access option in the system prompt (label varies by iOS version)
        let candidates = ["Limit Access…", "Limit Access...", "Select Contacts…", "Select Contacts...", "Select Contacts", "Choose Contacts…", "Choose Contacts"]
        var tapped = false
        for label in candidates {
            let b = springboard.buttons[label]
            if b.waitForExistence(timeout: 2) { b.tap(); tapped = true; break }
        }
        if !tapped {
            for label in candidates {
                let b = app.buttons[label]
                if b.waitForExistence(timeout: 2) { b.tap(); tapped = true; break }
            }
        }
        XCTAssertTrue(tapped, "Should find a limited-access option in the system prompt")
        sleep(2)
        capture("p3_picker")

        // Select two contacts in the picker, then confirm.
        // The picker is a system remote view — element taps don't toggle the
        // selection circles, so tap by screen coordinate instead.
        // Rows (from p3_picker capture): John Appleseed ~0.336, Kate Bell ~0.449 of screen height.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.336)).tap()
        sleep(1)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.449)).tap()
        sleep(1)
        capture("p4_selected")
        // "Continue" pill at ~0.868 of screen height; enabled once something is selected
        let contBtn = app.buttons["Continue"]
        if contBtn.waitForExistence(timeout: 2) && contBtn.isEnabled {
            contBtn.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.868)).tap()
        }
        // Final confirmation: "Allow access to N contacts?" → Allow Selected Contacts
        for host in [app!, springboard] {
            let allowSelected = host.buttons["Allow Selected Contacts"]
            if allowSelected.waitForExistence(timeout: 3) {
                allowSelected.tap()
                break
            }
        }
        sleep(3)
        capture("p5_contacts_after")

        // The contacts list should now show with the limited-access banner
        XCTAssertTrue(app.staticTexts["Limited access"].waitForExistence(timeout: 6),
                      "Contacts list should show the limited-access banner")

        // Settings should show "Limited" + Manage Selected Contacts
        tabs.buttons["Settings"].tap()
        sleep(1)
        app.swipeUp()
        sleep(1)
        capture("p6_settings")
        XCTAssertTrue(app.staticTexts["Limited"].waitForExistence(timeout: 4),
                      "Settings permission row should read Limited")
        XCTAssertTrue(app.buttons["Manage Selected Contacts"].waitForExistence(timeout: 4) ||
                      app.staticTexts["Manage Selected Contacts"].waitForExistence(timeout: 2),
                      "Settings should offer Manage Selected Contacts")

        // Open the in-app picker from Settings to prove the button works
        let manageBtn = app.buttons["Manage Selected Contacts"].exists
            ? app.buttons["Manage Selected Contacts"]
            : app.staticTexts["Manage Selected Contacts"]
        manageBtn.tap()
        sleep(2)
        capture("p7_manage_picker")
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

        // If the long-press landed on a widget (crowded home screen), a context
        // menu appears instead — enter edit mode through it.
        let editHomeScreen = springboard.buttons["Edit Home Screen"]
        if editHomeScreen.waitForExistence(timeout: 2) {
            editHomeScreen.tap()
            sleep(1)
            capture("widget_jiggle_via_menu")
        }

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

        // Exit jiggle mode via Home — tapping "Done" is ambiguous because the
        // widget's own "✓ Done" intent buttons match the same query.
        XCUIDevice.shared.press(.home)
        sleep(1)
        capture("widget_medium_home_screen")

        // --- Cleanup (best effort): remove one Rekindle widget so repeated
        // runs don't accumulate widgets until the home screen misbehaves.
        let widget = springboard.otherElements.matching(
            NSPredicate(format: "label CONTAINS[c] 'Rekindle'")
        ).firstMatch
        if widget.exists {
            widget.press(forDuration: 2)
            sleep(1)
            let removeOpt = springboard.buttons["Remove Widget"]
            if removeOpt.waitForExistence(timeout: 3) {
                removeOpt.tap()
                let confirm = springboard.alerts.buttons["Remove"].firstMatch.exists
                    ? springboard.alerts.buttons["Remove"].firstMatch
                    : springboard.buttons["Remove"].firstMatch
                if confirm.waitForExistence(timeout: 3) {
                    confirm.tap()
                    sleep(1)
                }
            }
            XCUIDevice.shared.press(.home)
            sleep(1)
            capture("widget_after_cleanup")
        }
    }
}
