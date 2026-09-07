import XCTest
@testable import TopTimerApp

final class SettingsValidationTests: XCTestCase {
    func testSettingsClampBoundedValues() {
        var settings = TopTimerSettings.defaults
        settings.snoozeSeconds = 0
        settings.historyPageSize = 5_000
        settings.alertVolume = 2
        settings.normalize()
        XCTAssertEqual(settings.snoozeSeconds, 60)
        XCTAssertEqual(settings.historyPageSize, 200)
        XCTAssertEqual(settings.alertVolume, 1)
    }
}
