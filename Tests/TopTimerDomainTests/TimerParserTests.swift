import Foundation
import XCTest
@testable import TopTimerDomain

final class TimerParserTests: XCTestCase {
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var fixedNow: Date {
        utcCalendar.date(from: DateComponents(year: 2026, month: 1, day: 15, hour: 13, minute: 45, second: 30))!
    }

    func testParsesSupportedDurationsAndMetadata() throws {
        let parser = TimerParser(calendar: utcCalendar, now: fixedNow)
        let cases: [(String, TimeInterval)] = [
            ("15", 900), ("60s", 60), ("1.5h", 5_400),
            ("1h 20m", 4_800), ("1:30:45", 5_445)
        ]

        for (input, seconds) in cases {
            XCTAssertEqual(try parser.parse(input).duration, seconds)
        }

        let parsed = try parser.parse("25m Design review #client #ui")
        XCTAssertEqual(parsed.title, "Design review")
        XCTAssertEqual(parsed.tags, ["client", "ui"])
    }

    func testBlankInputCreatesStopwatch() throws {
        let parser = TimerParser(calendar: utcCalendar, now: fixedNow)

        XCTAssertEqual(try parser.parse("   ").kind, .stopwatch)
    }

    func testInputIsBounded() {
        let parser = TimerParser(calendar: utcCalendar, now: fixedNow)

        XCTAssertThrowsError(try parser.parse(String(repeating: "x", count: 2_049))) { error in
            XCTAssertEqual(error as? TimerParserError, .inputTooLong)
        }
    }

    func testParsesWallClockAndRollsOverToTheNextDay() throws {
        let parser = TimerParser(calendar: utcCalendar, now: fixedNow)
        let sameDay = try parser.parse("@3pm Design review")
        let expectedSameDay = utcCalendar.date(from: DateComponents(year: 2026, month: 1, day: 15, hour: 15))!

        XCTAssertEqual(sameDay.kind, .countdown)
        XCTAssertEqual(sameDay.deadline, expectedSameDay)
        XCTAssertEqual(sameDay.duration, 4_470)
        XCTAssertEqual(sameDay.title, "Design review")

        let nextDay = try parser.parse("@1pm Tomorrow")
        let expectedNextDay = utcCalendar.date(from: DateComponents(year: 2026, month: 1, day: 16, hour: 13))!
        XCTAssertEqual(nextDay.deadline, expectedNextDay)
        XCTAssertEqual(nextDay.duration, 83_670)
    }

    func testParsesTwelveAndTwentyFourHourWallClockValues() throws {
        let parser = TimerParser(calendar: utcCalendar, now: fixedNow)
        let noon = try parser.parse("@12pm")
        let midnight = try parser.parse("@12am")
        let twentyFourHour = try parser.parse("@14:30")

        XCTAssertEqual(noon.deadline, utcCalendar.date(from: DateComponents(year: 2026, month: 1, day: 16, hour: 12))!)
        XCTAssertEqual(midnight.deadline, utcCalendar.date(from: DateComponents(year: 2026, month: 1, day: 16))!)
        XCTAssertEqual(twentyFourHour.deadline, utcCalendar.date(from: DateComponents(year: 2026, month: 1, day: 15, hour: 14, minute: 30))!)
    }

    func testPreservesApostrophesAndMixedScriptTitles() throws {
        let parser = TimerParser(calendar: utcCalendar, now: fixedNow)
        let parsed = try parser.parse("10m Daniel's مراجعة #عميل")

        XCTAssertEqual(parsed.title, "Daniel's مراجعة")
        XCTAssertEqual(parsed.tags, ["عميل"])
    }

    func testEnforcesTagLimits() {
        let parser = TimerParser(calendar: utcCalendar, now: fixedNow)
        let tooMany = (0...12).map { "#tag\($0)" }.joined(separator: " ")

        XCTAssertThrowsError(try parser.parse("1m \(tooMany)")) { error in
            XCTAssertEqual(error as? TimerValidationError, .tooManyTags)
        }
        XCTAssertThrowsError(try parser.parse("1m #\(String(repeating: "x", count: 33))")) { error in
            XCTAssertEqual(error as? TimerValidationError, .tagTooLong)
        }
    }

    func testRejectsMalformedDurations() {
        let parser = TimerParser(calendar: utcCalendar, now: fixedNow)
        let cases: [(String, TimerParserError)] = [
            ("1h 2h", .duplicateUnit),
            ("10q", .unsupportedSuffix),
            ("-1m", .negativeValue),
            ("0", .nonPositiveDuration),
            ("NaNh", .nonFiniteValue),
            ("1e400h", .nonFiniteValue),
            ("366d", .durationTooLong)
        ]

        for (input, expectedError) in cases {
            XCTAssertThrowsError(try parser.parse(input)) { error in
                XCTAssertEqual(error as? TimerParserError, expectedError, input)
            }
        }
    }

    func testRejectsMalformedTagsInsteadOfDroppingThem() {
        let parser = TimerParser(calendar: utcCalendar, now: fixedNow)

        XCTAssertThrowsError(try parser.parse("1m #")) { error in
            XCTAssertEqual(error as? TimerParserError, .malformedTag)
        }
        XCTAssertThrowsError(try parser.parse("1m Plan#later")) { error in
            XCTAssertEqual(error as? TimerParserError, .malformedTag)
        }
    }
}
