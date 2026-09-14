import AppKit
import XCTest

@testable import TopTimerApp

@MainActor final class StatusBarPopoverPresentationTests: XCTestCase {
  func testOpeningFromTheStatusItemLeavesRoomForTheSettingsToolbar() throws {
    let state = AppState(
      repository: RecordingRepository(), notifications: RecordingNotifications())
    let controller = StatusBarController(state: state)
    defer { controller.shutdown() }

    controller.open()

    let popover = controller.popoverForTesting
    XCTAssertEqual(popover.contentSize, NSSize(width: 276, height: 240))
    let content = try XCTUnwrap(popover.contentViewController?.view)
    content.layoutSubtreeIfNeeded()
    XCTAssertGreaterThan(content.bounds.width, 0)
    XCTAssertGreaterThanOrEqual(content.bounds.height, 240)
    controller.close()
  }
}
