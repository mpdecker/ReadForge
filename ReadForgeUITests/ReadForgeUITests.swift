//
//  ReadForgeUITests.swift
//  ReadForgeUITests
//
//  Created by Matthieu Decker on 5/5/26.
//

import XCTest

/// Covers the app shell: launching past the sign-in gate, the tab bar, the empty library, and
/// Settings. Player and document flows live in `UIAutomationTests`.
final class ReadForgeUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Boot past sign-in into an empty in-memory library. Without the bypass the app opens on
        // `AuthenticationView` and nothing below this line is reachable.
        app.launchArguments = [
            UITestLaunchArgument.bypassAuth,
            UITestLaunchArgument.inMemoryStore,
        ]
    }

    override func tearDownWithError() throws {
        app = nil
    }

    @MainActor
    func testLaunchesIntoLibraryWithTabBar() throws {
        app.launch()

        XCTAssertTrue(
            app.tabBars.buttons["Library"].waitForExistence(timeout: 10),
            "Expected the Library tab; the app may still be sitting on the sign-in screen."
        )
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists)
        XCTAssertTrue(app.tabBars.buttons["Library"].isSelected)
        // The library's own navigation title is the app name, not "Library".
        XCTAssertTrue(app.navigationBars["ReadForge"].exists)
    }

    @MainActor
    func testTabNavigation() throws {
        app.launch()

        let libraryTab = app.tabBars.buttons["Library"]
        let settingsTab = app.tabBars.buttons["Settings"]
        XCTAssertTrue(libraryTab.waitForExistence(timeout: 10))

        settingsTab.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(settingsTab.isSelected)
        XCTAssertFalse(libraryTab.isSelected)

        libraryTab.tap()
        XCTAssertTrue(app.navigationBars["ReadForge"].waitForExistence(timeout: 5))
        XCTAssertTrue(libraryTab.isSelected)
        XCTAssertFalse(settingsTab.isSelected)
    }

    @MainActor
    func testEmptyLibraryState() throws {
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Library"].waitForExistence(timeout: 10))

        XCTAssertTrue(app.staticTexts["No documents yet"].exists)
        XCTAssertTrue(app.staticTexts["Import a PDF to get started."].exists)
        XCTAssertTrue(app.buttons[UITestIdentifier.importDocumentEmptyState].exists)
    }

    /// Import is the only way to get content into the app, and it appears twice while the
    /// library is empty ("Import" in the toolbar, "Import PDF" in the empty state), so both are
    /// worth pinning as present and tappable.
    ///
    /// Deliberately stops short of asserting that the system document browser appears:
    /// `fileImporter` presents it from a separate process whose elements are not in this app's
    /// query tree, so any such assertion tests Apple's UI via a remote-view detail that changes
    /// between iOS releases.
    @MainActor
    func testImportButtonIsPresentAndHittable() throws {
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Library"].waitForExistence(timeout: 10))

        // Both are present and independently tappable while the library is empty.
        let toolbarImport = app.buttons[UITestIdentifier.importDocumentToolbar]
        XCTAssertTrue(toolbarImport.waitForExistence(timeout: 5))
        XCTAssertTrue(toolbarImport.isHittable)

        let emptyStateImport = app.buttons[UITestIdentifier.importDocumentEmptyState]
        XCTAssertTrue(emptyStateImport.exists)
        XCTAssertTrue(emptyStateImport.isHittable)
    }

    @MainActor
    func testSettingsScreenShowsCoreSections() throws {
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Settings"].tap()

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        // Only the sections above the fold: a `Form` builds its rows lazily, so asserting on a
        // section further down (Privacy, Diagnostics, About) fails until it is scrolled into
        // view rather than because it is missing.
        XCTAssertTrue(app.staticTexts["Account"].exists)
        XCTAssertTrue(app.staticTexts["Playback"].exists)
    }

    @MainActor
    func testSettingsExposesVoiceAndSpeedControls() throws {
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        // Both live in the Playback section and are the two settings that change how narration
        // sounds, so they are the ones worth guarding against an accidental removal. A `Picker`
        // in a `Form` surfaces as a row whose label carries its current value too ("Voice,
        // System Default"), hence the prefix match rather than an exact one.
        XCTAssertTrue(settingsRow(labelPrefix: "Voice").waitForExistence(timeout: 5))
        XCTAssertTrue(settingsRow(labelPrefix: "Default Speed").exists)
    }

    /// First element whose accessibility label starts with `labelPrefix`, across element types —
    /// `Form` rows land on different types depending on the control they wrap.
    private func settingsRow(labelPrefix: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH[c] %@", labelPrefix))
            .firstMatch
    }
}
