import AppKit
import Carbon
import XCTest

@testable import TopTimerApp
import TopTimerSystem

final class ShortcutRecorderTests: XCTestCase {
  func testRecorderAcceptsCommandShiftT() throws {
    XCTAssertEqual(
      try ShortcutRecorder.shortcut(keyCode: 17, modifiers: [.command, .shift]),
      try Shortcut(keyCode: 17, modifiers: UInt32(cmdKey | shiftKey)))
  }

  func testRecorderRejectsModifierOnlyAndUnsupportedModifiers() {
    XCTAssertThrowsError(try ShortcutRecorder.shortcut(keyCode: nil, modifiers: [.command]))
    XCTAssertThrowsError(try ShortcutRecorder.shortcut(keyCode: 17, modifiers: [.function]))
  }
}
