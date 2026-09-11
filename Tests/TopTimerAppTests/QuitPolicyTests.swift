import XCTest
@testable import TopTimerApp
@testable import TopTimerDomain

final class QuitPolicyTests: XCTestCase {
  func testQuitPolicyQuitsImmediatelyWithoutActiveTimers() {
    XCTAssertEqual(QuitPolicy.decide(activeTimers: []), .quitImmediately)
  }

  func testQuitPolicyConfirmsWhenRunningOrPausedTimersExist() throws {
    var running = try TimerItem.countdown(title: "", duration: 60)
    try running.start(at: .now)
    var paused = try TimerItem.stopwatch(title: "")
    try paused.start(at: .now)
    try paused.pause(at: .now)
    XCTAssertEqual(QuitPolicy.decide(activeTimers: [running]), .confirmPersistence(running: 1, paused: 0))
    XCTAssertEqual(QuitPolicy.decide(activeTimers: [paused]), .confirmPersistence(running: 0, paused: 1))
  }
}
