import XCTest
@testable import TopTimerDomain

final class TimerModelsTests: XCTestCase {
    func testCountdownRejectsNonPositiveDuration() {
        XCTAssertThrowsError(
            try TimerItem.countdown(title: "Tea", duration: 0)
        )
    }

    func testMetadataLimitsAreEnforced() throws {
        let item = try TimerItem.stopwatch(
            title: String(repeating: "T", count: 80),
            details: String(repeating: "D", count: 500),
            tags: (0..<12).map { "tag\($0)" }
        )
        XCTAssertEqual(item.details.count, 500)
        XCTAssertEqual(item.tags.count, 12)
    }
}
