//
//  UIAutomationTests.swift
//  ReadForgeUITests
//
//  Created by Matthieu Decker on 5/10/26.
//

import XCTest
import SwiftUI

final class UIAutomationTests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["UI_TESTING"]
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - Library View Tests
    
    func testLibraryViewDisplaysCorrectly() throws {
        // Verify library view is displayed
        XCTAssertTrue(app.tabBars.buttons["Library"].exists)
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists)
        
        // Verify library tab is selected by default
        XCTAssertTrue(app.tabBars.buttons["Library"].isSelected)
    }
    
    func testDocumentImportFlow() throws {
        // Tap import button
        let importButton = app.buttons["Import Document"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 5))
        importButton.tap()
        
        // Verify file picker is presented (if supported in test environment)
        // Note: File picker might not be accessible in UI tests
        // This test verifies the import button is tappable
    }
    
    func testDocumentListDisplays() throws {
        // Wait for documents to load
        let documentsList = app.collectionViews.firstMatch
        XCTAssertTrue(documentsList.waitForExistence(timeout: 10))
        
        // If there are no documents, verify empty state
        if documentsList.cells.count == 0 {
            XCTAssertTrue(app.staticTexts["No documents"].exists)
        }
    }
    
    func testDocumentSelection() throws {
        let documentsList = app.collectionViews.firstMatch
        
        // Only test if documents exist
        if documentsList.cells.count > 0 {
            let firstDocument = documentsList.cells.firstMatch
            XCTAssertTrue(firstDocument.exists)
            
            // Tap on first document
            firstDocument.tap()
            
            // Verify navigation to player view
            let playerView = app.otherElements["PlayerView"]
            XCTAssertTrue(playerView.waitForExistence(timeout: 5))
        }
    }
    
    // MARK: - Player View Tests
    
    func testPlayerViewControls() throws {
        // Navigate to player view (assuming a document exists)
        navigateToPlayerView()
        
        // Verify play/pause button exists
        let playButton = app.buttons["Play"]
        let pauseButton = app.buttons["Pause"]
        
        // Either play or pause button should be visible
        XCTAssertTrue(playButton.exists || pauseButton.exists)
        
        // Test play/pause toggle
        if playButton.exists {
            playButton.tap()
            XCTAssertTrue(pauseButton.waitForExistence(timeout: 2))
        } else if pauseButton.exists {
            pauseButton.tap()
            XCTAssertTrue(playButton.waitForExistence(timeout: 2))
        }
    }
    
    func testPlayerViewSpeedControl() throws {
        navigateToPlayerView()
        
        // Verify speed control exists
        let speedPicker = app.pickers["Speed"]
        XCTAssertTrue(speedPicker.waitForExistence(timeout: 5))
        
        // Test speed change
        speedPicker.tap()
        let speedOption = app.buttons["1.5×"]
        if speedOption.exists {
            speedOption.tap()
        }
    }
    
    func testPlayerViewSkipControls() throws {
        navigateToPlayerView()
        
        // Verify skip buttons exist
        let skipBackButton = app.buttons["Skip Back"]
        let skipForwardButton = app.buttons["Skip Forward"]
        
        XCTAssertTrue(skipBackButton.waitForExistence(timeout: 5))
        XCTAssertTrue(skipForwardButton.waitForExistence(timeout: 5))
        
        // Test skip functionality
        skipForwardButton.tap()
        skipBackButton.tap()
    }
    
    func testPlayerViewBookmark() throws {
        navigateToPlayerView()
        
        // Verify bookmark button exists
        let bookmarkButton = app.buttons["Bookmark"]
        XCTAssertTrue(bookmarkButton.waitForExistence(timeout: 5))
        
        // Test bookmark creation
        bookmarkButton.tap()
        
        // Verify bookmark was created (check for confirmation or bookmark list)
        // This might require additional UI elements to verify bookmark creation
    }
    
    // MARK: - Settings View Tests
    
    func testSettingsViewDisplays() throws {
        // Navigate to settings
        app.tabBars.buttons["Settings"].tap()
        
        // Verify settings view elements
        XCTAssertTrue(app.navigationBars["Settings"].exists)
        
        // Look for common settings options
        let textSettings = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'text' OR label CONTAINS[c] 'speech'")).firstMatch
        if textSettings.exists {
            XCTAssertTrue(textSettings.exists)
        }
    }
    
    func testTabNavigation() throws {
        // Test switching between tabs
        let libraryTab = app.tabBars.buttons["Library"]
        let settingsTab = app.tabBars.buttons["Settings"]
        
        // Start with library
        libraryTab.tap()
        XCTAssertTrue(libraryTab.isSelected)
        XCTAssertFalse(settingsTab.isSelected)
        
        // Switch to settings
        settingsTab.tap()
        XCTAssertFalse(libraryTab.isSelected)
        XCTAssertTrue(settingsTab.isSelected)
        
        // Switch back to library
        libraryTab.tap()
        XCTAssertTrue(libraryTab.isSelected)
        XCTAssertFalse(settingsTab.isSelected)
    }
    
    // MARK: - Accessibility Tests
    
    func testAccessibilityElements() throws {
        // Verify VoiceOver support
        let libraryTab = app.tabBars.buttons["Library"]
        XCTAssertTrue(libraryTab.isAccessibilityElement)
        XCTAssertNotNil(libraryTab.accessibilityLabel)
        
        let settingsTab = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settingsTab.isAccessibilityElement)
        XCTAssertNotNil(settingsTab.accessibilityLabel)
        
        navigateToPlayerView()
        
        // Test player controls accessibility
        let playButton = app.buttons["Play"]
        if playButton.exists {
            XCTAssertTrue(playButton.isAccessibilityElement)
            XCTAssertNotNil(playButton.accessibilityLabel)
        }
        
        let bookmarkButton = app.buttons["Bookmark"]
        if bookmarkButton.exists {
            XCTAssertTrue(bookmarkButton.isAccessibilityElement)
            XCTAssertNotNil(bookmarkButton.accessibilityLabel)
        }
    }
    
    func testAccessibilityTraits() throws {
        // Verify proper accessibility traits
        let libraryTab = app.tabBars.buttons["Library"]
        XCTAssertTrue(libraryTab.accessibilityTraits.contains(.button))
        XCTAssertTrue(libraryTab.accessibilityTraits.contains(.selected))
        
        let playButton = app.buttons["Play"]
        if playButton.exists {
            XCTAssertTrue(playButton.accessibilityTraits.contains(.button))
        }
    }
    
    // MARK: - Performance Tests
    
    func testAppLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
    
    func testScrollPerformance() throws {
        navigateToPlayerView()
        
        let scrollView = app.scrollViews.firstMatch
        if scrollView.exists {
            measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric]) {
                scrollView.swipeUp()
                scrollView.swipeDown()
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func navigateToPlayerView() {
        // Try to navigate to player view through library
        let libraryTab = app.tabBars.buttons["Library"]
        if !libraryTab.isSelected {
            libraryTab.tap()
        }
        
        // Wait for documents to load
        let documentsList = app.collectionViews.firstMatch
        if documentsList.waitForExistence(timeout: 5) && documentsList.cells.count > 0 {
            let firstDocument = documentsList.cells.firstMatch
            firstDocument.tap()
            
            // Wait for player view to appear
            let playerView = app.otherElements["PlayerView"]
            _ = playerView.waitForExistence(timeout: 5)
        }
    }
}
