import AppKit
import XCTest

@testable import TopTimerApp

@MainActor final class StatusBarPopoverPresentationTests: XCTestCase {
  func testOpeningFromTheStatusItemInstallsNonEmptyPopoverContent() throws {
    let state = AppState(
      repository: RecordingRepository(), notifications: RecordingNotifications())
    let controller = StatusBarController(state: state)
    defer { controller.shutdown() }

    controller.open()

    let popover = controller.popoverForTesting
    XCTAssertEqual(popover.contentSize, NSSize(width: 276, height: 110))
    let content = try XCTUnwrap(popover.contentViewController?.view)
    content.layoutSubtreeIfNeeded()
    XCTAssertGreaterThan(content.bounds.width, 0)
    XCTAssertGreaterThan(content.bounds.height, 0)
    controller.close()
  }
}
