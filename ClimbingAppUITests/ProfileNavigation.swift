import XCTest

extension XCUIApplication {
    /// iOS 27 can expose the toolbar image's accessibility node instead of its NavigationLink.
    var profileButton: XCUIElement {
        buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@ OR label == %@", "openSettings", "Default profile picture", "Profile picture")).firstMatch
    }
}
