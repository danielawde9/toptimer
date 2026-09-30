import AppKit
import SwiftUI
import XCTest

@testable import TopTimerApp

@MainActor final class WindowCoordinatorTests: XCTestCase {
  func testEveryWindowHasNavigationToEveryScreen() throws {
    let coordinator = WindowCoordinator()
    var destinations: [TopTimerWindow] = []
    coordinator.navigate = { destinations.append($0) }
    defer { coordinator.closeAll() }
    for kind in TopTimerWindow.allCases {
      let window = try XCTUnwrap(coordinator.show(kind: kind) { Text("Content") }.window)
      let popup = try XCTUnwrap(
        window.toolbar?.items.compactMap { $0.view as? NSPopUpButton }.first)
      let menu = try XCTUnwrap(popup.menu)
      destinations = []
      for index in 1..<menu.items.count { menu.performActionForItem(at: index) }
      XCTAssertEqual(destinations, TopTimerWindow.allCases)
    }
  }

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
    XCTAssertEqual(first.window?.contentMinSize, NSSize(width: 460, height: 360))
    coordinator.closeAll()
  }
}
