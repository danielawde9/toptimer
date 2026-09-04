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

    func testInputBoundaryUsesUnicodeScalars() throws {
        let parser = TimerParser(calendar: utcCalendar, now: fixedNow)
        let accepted = String(repeating: " ", count: 2_048)
        XCTAssertEqual(try parser.parse(accepted).kind, .stopwatch)

        let composed = String(repeating: "e\u{301}", count: 1_024)
        XCTAssertEqual(composed.count, 1_024)
        XCTAssertEqual(composed.unicodeScalars.count, 2_048)
        XCTAssertThrowsError(try parser.parse(composed)) { error in
            XCTAssertNotEqual(error as? TimerParserError, .inputTooLong)
        }

        let overLimit = composed + "x"
        XCTAssertEqual(overLimit.unicodeScalars.count, 2_049)
        XCTAssertThrowsError(try parser.parse(overLimit)) { error in
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

    func testWallClockUsesNextTimeForSpringForwardGap() throws {
        var calendar = utcCalendar
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 1, minute: 59))!
        let parsed = try TimerParser(calendar: calendar, now: now).parse("@2:30am")

        XCTAssertEqual(parsed.deadline, Date(timeIntervalSince1970: 1_772_953_200))
        XCTAssertEqual(parsed.duration, 60)
    }

    func testWallClockUsesFirstOccurrenceForFallBackFold() throws {
        var calendar = utcCalendar
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 0, minute: 30))!
        let parsed = try TimerParser(calendar: calendar, now: now).parse("@1:30am")

        XCTAssertEqual(parsed.deadline, Date(timeIntervalSince1970: 1_793_511_000))
        XCTAssertEqual(parsed.duration, 3_600)
    }

    func testRejectsOverflowingWallClockIntegerAsInvalidWallClock() {
        let parser = TimerParser(calendar: utcCalendar, now: fixedNow)

        XCTAssertThrowsError(try parser.parse("@999999999999999999999")) { error in
            XCTAssertEqual(error as? TimerParserError, .invalidWallClock)
        }
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
            ("366d", .durationTooLong),
            ("1:60", .invalidFormat)
        ]

        for (input, expectedError) in cases {
            XCTAssertThrowsError(try parser.parse(input)) { error in
                XCTAssertEqual(error as? TimerParserError, expectedError, input)
            }
        }
        XCTAssertEqual(try? parser.parse("365d").duration, 365 * 24 * 60 * 60)
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
