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
}
