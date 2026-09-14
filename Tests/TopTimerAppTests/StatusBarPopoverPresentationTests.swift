import AppKit
import XCTest

@testable import TopTimerApp

@MainActor final class StatusBarPopoverPresentationTests: XCTestCase {
  func testPopoverUsesReadableBoundedSize() throws {
    let state = AppState(
      repository: RecordingRepository(), notifications: RecordingNotifications())
    let controller = StatusBarController(state: state)
    defer { controller.shutdown() }

    controller.open()

    let popover = controller.popoverForTesting
    XCTAssertEqual(popover.contentSize, NSSize(width: 320, height: 300))
    let content = try XCTUnwrap(popover.contentViewController?.view)
    content.layoutSubtreeIfNeeded()
    XCTAssertGreaterThan(content.bounds.width, 0)
    XCTAssertGreaterThanOrEqual(content.bounds.height, 300)
    controller.close()
  }
}
