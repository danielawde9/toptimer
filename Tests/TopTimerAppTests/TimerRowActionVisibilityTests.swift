import XCTest
@testable import TopTimerApp

final class TimerRowActionVisibilityTests: XCTestCase {
    func testActionsAreVisibleForHoverOrKeyboardFocus() {
        XCTAssertFalse(TimerRowActionVisibility(isHovered: false, isFocused: false).showsActions)
        XCTAssertTrue(TimerRowActionVisibility(isHovered: true, isFocused: false).showsActions)
        XCTAssertTrue(TimerRowActionVisibility(isHovered: false, isFocused: true).showsActions)
    }
}
