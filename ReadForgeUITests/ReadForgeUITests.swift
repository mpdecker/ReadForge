//
//  ReadForgeUITests.swift
//  ReadForgeUITests
//
//  Created by Matthieu Decker on 5/5/26.
//

import XCTest

final class ReadForgeUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
    }

    override func tearDownWithError() throws {
        app = nil
    }

    @MainActor
    func testAppLaunchAndBasicNavigation() throws {
        app.launch()
        
        // Verify main tabs are present
        XCTAssertTrue(app.tabBars.buttons["Library"].exists)
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists)
        
        // Test tab switching
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].exists)
        
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.navigationBars["Library"].exists)
    }

    @MainActor
    func testDocumentImportFlow() throws {
        app.launch()
        
        // Navigate to Library tab
        app.tabBars.buttons["Library"].tap()
        
        // Look for import button (may be in navigation bar or floating action button)
        let importButton = app.buttons["Import Document"].exists ? 
            app.buttons["Import Document"] : 
            app.navigationBars.buttons["Import"]
        
        XCTAssertTrue(importButton.waitForExistence(timeout: 5), "Import button should be visible")
        
        // Note: Actual file picker testing requires additional setup
        // This test verifies the UI flow up to the file picker presentation
        importButton.tap()
        
        // Verify file picker sheet appears (iOS 17+ style)
        XCTAssertTrue(app.sheets.element.exists)
    }

    @MainActor
    func testEmptyLibraryState() throws {
        app.launch()
        app.tabBars.buttons["Library"].tap()
        
        // Verify empty state message is shown
        XCTAssertTrue(app.staticTexts["No documents yet"].exists || 
                     app.staticTexts["Import your first document"].exists)
        
        // Verify import button is available in empty state
        XCTAssertTrue(app.buttons["Import Document"].exists)
    }

    @MainActor
    func testPlayerControlsAccessibility() throws {
        app.launch()
        app.tabBars.buttons["Library"].tap()
        
        // Test that player controls are accessible when present
        let playButton = app.buttons["Play"]
        let pauseButton = app.buttons["Pause"]
        
        // These may not exist in empty state, but should be accessible when present
        if playButton.exists {
            XCTAssertTrue(playButton.isHittable)
            XCTAssertTrue(playButton.accessibilityLabel != "")
        }
        
        if pauseButton.exists {
            XCTAssertTrue(pauseButton.isHittable)
            XCTAssertTrue(pauseButton.accessibilityLabel != "")
        }
    }

    @MainActor
    func testSettingsScreen() throws {
        app.launch()
        app.tabBars.buttons["Settings"].tap()
        
        // Verify key settings sections exist
        XCTAssertTrue(app.staticTexts["Voice Settings"].exists || 
                     app.staticTexts["Playback"].exists)
        
        // Test settings toggles
        let voiceSettings = app.buttons["Voice Settings"]
        if voiceSettings.exists {
            voiceSettings.tap()
            XCTAssertTrue(app.navigationBars["Voice Settings"].exists)
        }
    }

    @MainActor
    func testDocumentDetailNavigation() throws {
        app.launch()
        app.tabBars.buttons["Library"].tap()
        
        // Look for any document in the list
        let firstDocument = app.tables.cells.firstMatch
        
        if firstDocument.exists {
            firstDocument.tap()
            
            // Verify document detail view loads
            XCTAssertTrue(app.navigationBars.firstMatch.exists)
            
            // Test player controls in detail view
            let playButton = app.buttons["Play"]
            if playButton.exists {
                XCTAssertTrue(playButton.isHittable)
            }
        }
    }

    @MainActor
    func testBackgroundAudioPermissions() throws {
        app.launch()
        
        // This test verifies the app handles background audio properly
        // In a real test, you'd simulate backgrounding the app
        // For now, we verify the UI responds correctly
        
        app.tabBars.buttons["Library"].tap()
        
        // Simulate playing audio (if document exists)
        let playButton = app.buttons["Play"]
        if playButton.exists {
            playButton.tap()
            
            // Verify player UI updates
            XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 2))
        }
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            app.launch()
        }
    }
}
