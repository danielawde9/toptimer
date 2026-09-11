import XCTest
@testable import TopTimerApp
import TopTimerDomain

final class StatusFormattingTests: XCTestCase {
    func testRunningCountdownUsesCompactIconAndRemainingTime() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        var timer = try TimerItem.countdown(title: "Tea", duration: 900, createdAt: now)
        try timer.start(at: now)
        let value = StatusTitleFormatter.format(timer: timer, now: now.addingTimeInterval(22))
        XCTAssertEqual(value.text, "14:38")
        XCTAssertEqual(value.accessibilityLabel, "Tea, 14:38 remaining")
        XCTAssertTrue(value.showsIcon)
    }

    func testIdleTimerUsesOnlyItsSymbol() throws {
        let timer = try TimerItem.countdown(title: "Later", duration: 60, createdAt: .distantPast)
        let value = StatusTitleFormatter.format(timer: timer, now: .now)
        XCTAssertEqual(value.text, "")
        XCTAssertTrue(value.showsIcon)
    }

    func testSecondsModeIncludesHoursMinutesAndSeconds() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        var timer = try TimerItem.countdown(title: "Focus", duration: 3_600, createdAt: now)
        try timer.start(at: now)
        XCTAssertEqual(StatusTitleFormatter.format(timer: timer, now: now.addingTimeInterval(22), mode: .seconds).text, "00:59:38")
    }

    func testStatusIncludesAdditionalCountAndPausedState() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        var timer = try TimerItem.countdown(title: "Focus", duration: 900, createdAt: now)
        try timer.start(at: now)
        let value = StatusTitleFormatter.format(timer: timer, additionalActiveCount: 2, now: now)
        XCTAssertEqual(value.text, "15:00 +2")
        XCTAssertTrue(value.accessibilityLabel.contains("Focus"))
        XCTAssertTrue(value.accessibilityLabel.contains("2 additional active timers"))
        try timer.pause(at: now)
        let paused = StatusTitleFormatter.format(timer: timer, now: now)
        XCTAssertTrue(paused.accessibilityLabel.contains("Paused"))
    }

    func testIdleStatusExplainsHowToReturnToTopTimer() {
        let value = StatusTitleFormatter.format(timer: nil, now: .now)
        XCTAssertEqual(value.accessibilityLabel, "TopTimer")
    }
}
