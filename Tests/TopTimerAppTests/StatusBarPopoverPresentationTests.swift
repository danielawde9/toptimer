import AppKit
import XCTest

@testable import TopTimerApp

@MainActor final class StatusBarPopoverPresentationTests: XCTestCase {
  func testOpenInstallsCompactNonEmptyPopoverContent() {
    let state = AppState(
      repository: RecordingRepository(), notifications: RecordingNotifications())
    let controller = StatusBarController(state: state)
    defer { controller.shutdown() }

    controller.open()

    let popover = controller.popoverForTesting
    XCTAssertEqual(popover.contentSize, NSSize(width: 276, height: 110))
    let content = try! XCTUnwrap(popover.contentViewController?.view)
    content.layoutSubtreeIfNeeded()
    XCTAssertGreaterThan(content.bounds.width, 0)
    XCTAssertGreaterThan(content.bounds.height, 0)
    XCTAssertTrue(
      descendants(of: content).contains { ($0 as? NSTextField)?.accessibilityIdentifier() == "quick-entry" })
    controller.close()
  }

  private func descendants(of root: NSView) -> [NSView] {
    var pending = [root]
    var result: [NSView] = []
    for _ in 0..<300 where !pending.isEmpty {
      let view = pending.removeFirst()
      result.append(view)
      pending.append(contentsOf: view.subviews.prefix(100))
    }
    return result
  }
}
