//
//  UIAutomationTests.swift
//  ReadForgeUITests
//
//  Created by Matthieu Decker on 5/10/26.
//

import XCTest

/// Covers the document flows that need content to exist: library row → detail → player, the
/// transport controls, and their accessibility labels.
///
/// Every test here launches with a seeded in-memory library. The previous version navigated
/// through a *fresh* simulator with no documents, so its `navigateToPlayerView()` helper
/// silently did nothing and each test then asserted on player controls that were never on
/// screen — a guaranteed failure rather than a real check.
final class UIAutomationTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            UITestLaunchArgument.bypassAuth,
            UITestLaunchArgument.inMemoryStore,
            UITestLaunchArgument.seedLibrary,
        ]
        app.launch()
        XCTAssertTrue(
            app.tabBars.buttons["Library"].waitForExistence(timeout: 10),
            "App did not reach the library; check the sign-in bypass launch argument."
        )
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Library

    func testSeededDocumentAppearsInLibrary() throws {
        XCTAssertTrue(documentRow.waitForExistence(timeout: 10))
        // The empty state must be gone once a document exists.
        XCTAssertFalse(app.staticTexts["No documents yet"].exists)
    }

    func testDocumentRowOpensDetailView() throws {
        XCTAssertTrue(documentRow.waitForExistence(timeout: 10))
        documentRow.tap()

        XCTAssertTrue(app.navigationBars[UITestFixture.documentTitle].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[UITestFixture.firstSectionTitle].exists)
        XCTAssertTrue(app.staticTexts[UITestFixture.secondSectionTitle].exists)
    }

    // MARK: - Player

    func testPlayerExposesTransportControls() throws {
        try openPlayer()

        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Skip Forward"].exists)
        XCTAssertTrue(app.buttons["Skip Back"].exists)
        // Nothing has played yet, so there is nowhere to skip back to.
        XCTAssertFalse(app.buttons["Skip Back"].isEnabled)
    }

    /// The player shows which sentence of the section is current. Deterministic regardless of
    /// whether the simulator actually produces audio.
    func testPlayerShowsSentenceProgress() throws {
        try openPlayer()
        XCTAssertTrue(progressLabel.waitForExistence(timeout: 10), "Player shows no progress label.")
        // Opens on the first sentence. The total depends on how `SentenceChunker` splits the
        // fixture, so only the position is pinned.
        XCTAssertTrue(
            progressLabel.label.hasPrefix("1 of "),
            "Expected to open on the first sentence, got \(progressLabel.label)"
        )
    }

    func testPlayerExposesSpeedControl() throws {
        try openPlayer()

        // A segmented `Picker` surfaces as a segmented control whose options are buttons.
        let oneAndAHalf = app.buttons["1.5×"]
        XCTAssertTrue(oneAndAHalf.waitForExistence(timeout: 10))
        oneAndAHalf.tap()
        XCTAssertTrue(oneAndAHalf.isSelected)
    }

    func testPlayerExposesSectionPicker() throws {
        try openPlayer()

        // `SectionPickerView` uses `.pickerStyle(.menu)`, so only the current selection is on
        // screen and the menu button is labelled "<title>, <current value>"; the other chapters
        // appear once the menu is opened.
        let picker = app.buttons["Section, \(UITestFixture.firstSectionTitle)"]
        XCTAssertTrue(
            picker.waitForExistence(timeout: 10),
            "Expected the section picker showing the current chapter."
        )
        picker.tap()
        XCTAssertTrue(
            app.buttons[UITestFixture.secondSectionTitle].waitForExistence(timeout: 5),
            "Section picker menu did not offer the second chapter."
        )
    }

    func testBookmarkButtonIsAvailableInPlayer() throws {
        try openPlayer()

        let bookmark = app.buttons["Bookmark"]
        XCTAssertTrue(bookmark.waitForExistence(timeout: 10))
        bookmark.tap()
        // Adding a bookmark is silent apart from haptic feedback; the check is that tapping it
        // neither crashes the app nor dismisses the player.
        XCTAssertTrue(app.buttons["Play"].exists || app.buttons["Pause"].exists)
    }

    // MARK: - Accessibility

    func testTabBarItemsAreLabelled() throws {
        for name in ["Library", "Settings"] {
            let tab = app.tabBars.buttons[name]
            XCTAssertTrue(tab.exists, "Missing tab: \(name)")
            XCTAssertFalse(tab.label.isEmpty, "Tab \(name) has no accessibility label")
        }
    }

    /// The transport controls are icon-only `Image(systemName:)` buttons, which carry no
    /// accessible name unless one is set explicitly — this guards the labels added to
    /// `PlayerControlsView`.
    func testPlayerControlsAreLabelledForVoiceOver() throws {
        try openPlayer()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 10))

        for name in ["Play", "Skip Forward", "Skip Back", "Bookmark"] {
            let control = app.buttons[name]
            XCTAssertTrue(control.exists, "Missing labelled control: \(name)")
            XCTAssertEqual(control.label, name)
        }
    }

    // MARK: - Helpers

    /// The library row. `DocumentRowView` stacks the title with a status and a listening-time
    /// label, so the row's accessibility label is the concatenation of all three ("UI Test
    /// Document, ·, < 1 min") — an exact-match lookup on the title alone never matches it.
    private var documentRow: XCUIElement {
        app.buttons
            .matching(NSPredicate(format: "label CONTAINS[c] %@", UITestFixture.documentTitle))
            .firstMatch
    }

    /// `PlayerControlsView`'s "<n> of <total>" caption.
    private var progressLabel: XCUIElement {
        app.staticTexts
            .matching(NSPredicate(format: "label MATCHES %@", "^[0-9]+ of [0-9]+$"))
            .firstMatch
    }

    /// Library → document detail → player, failing the test at the first step that does not
    /// arrive rather than silently continuing against the wrong screen.
    private func openPlayer() throws {
        XCTAssertTrue(documentRow.waitForExistence(timeout: 10), "Seeded document never appeared.")
        documentRow.tap()

        XCTAssertTrue(
            app.navigationBars[UITestFixture.documentTitle].waitForExistence(timeout: 10),
            "Document detail view never appeared."
        )

        // The play bar reads "Play" with no saved progress and "Resume" with some.
        let playBar = app.buttons["Play"].exists ? app.buttons["Play"] : app.buttons["Resume"]
        XCTAssertTrue(playBar.waitForExistence(timeout: 10), "Play bar never appeared.")
        playBar.tap()
    }
}
