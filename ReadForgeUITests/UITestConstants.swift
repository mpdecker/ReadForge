//
//  UITestConstants.swift
//  ReadForgeUITests
//

import Foundation

/// Launch arguments understood by the app's `UITestSupport` (debug builds only).
///
/// Duplicated rather than shared: XCUITests drive the app out of process and cannot import the
/// app module, so these strings are the contract between the two. Keep them in step with
/// `ReadForge/App/UITestSupport.swift`.
enum UITestLaunchArgument {
    static let bypassAuth = "-uitest-bypass-auth"
    static let inMemoryStore = "-uitest-in-memory-store"
    static let seedLibrary = "-uitest-seed-library"
}

/// Accessibility identifiers the app sets for automation.
///
/// The two import affordances are on screen together when the library is empty, so they carry
/// separate identifiers rather than one shared handle.
enum UITestIdentifier {
    /// Toolbar "Import" — present whether or not the library has documents.
    static let importDocumentToolbar = "ImportDocumentToolbar"
    /// The empty state's "Import PDF" call to action.
    static let importDocumentEmptyState = "ImportDocumentEmptyState"
}

/// Fixture inserted by `UITestLaunchArgument.seedLibrary`; mirrors
/// `UITestSupport.seededDocumentTitle`.
enum UITestFixture {
    static let documentTitle = "UI Test Document"
    static let firstSectionTitle = "Chapter 1"
    static let secondSectionTitle = "Chapter 2"
}
