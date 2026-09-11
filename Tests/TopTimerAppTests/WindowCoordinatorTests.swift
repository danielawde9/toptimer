import XCTest
import SwiftUI
@testable import TopTimerApp

@MainActor final class WindowCoordinatorTests: XCTestCase {
  func testReopeningAWindowReusesItsController() {
    let coordinator = WindowCoordinator()
    let first = coordinator.show(kind: .history) { Text("History") }
    let second = coordinator.show(kind: .history) { Text("History") }
    XCTAssertTrue(first === second)
    XCTAssertEqual(coordinator.windowCount, 1)
  }

  func testNowWindowIsSingletonAndHasMinimumSize() {
    let coordinator = WindowCoordinator()
    let first = coordinator.show(kind: .now) { Text("Now") }
    let second = coordinator.show(kind: .now) { Text("Ignored") }
    XCTAssertTrue(first === second)
    XCTAssertEqual(first.window?.minSize, NSSize(width: 460, height: 360))
    coordinator.closeAll()
  }
}
