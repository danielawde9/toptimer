import XCTest
@testable import TopTimerDomain

final class TimerModelsTests: XCTestCase {
    func testCountdownRejectsNonPositiveDuration() {
        XCTAssertThrowsError(
            try TimerItem.countdown(
                title: "Tea",
                duration: 0,
                createdAt: Date(timeIntervalSince1970: 1)
            )
        )
    }

    func testMetadataLimitsAreEnforced() throws {
        let item = try TimerItem.stopwatch(
            title: String(repeating: "T", count: 80),
            details: String(repeating: "D", count: 500),
            tags: (0..<12).map { "tag\($0)" },
            createdAt: Date(timeIntervalSince1970: 1)
        )
        XCTAssertEqual(item.details.count, 500)
        XCTAssertEqual(item.tags.count, 12)
    }

    func testMetadataBoundariesRejectInvalidValuesWithExactErrors() {
        let cases: [(String, String, TimerValidationError)] = [
            (String(repeating: "T", count: 81), "", .titleTooLong),
            ("", String(repeating: "D", count: 501), .descriptionTooLong)
        ]

        for (title, details, expectedError) in cases {
            XCTAssertThrowsError(
                try TimerItem.stopwatch(
                    title: title,
                    details: details,
                    createdAt: Date(timeIntervalSince1970: 1)
                )
            ) { error in
                XCTAssertEqual(error as? TimerValidationError, expectedError)
            }
        }

        XCTAssertThrowsError(
            try TimerItem.stopwatch(
                title: "Tags",
                tags: (0..<13).map(String.init),
                createdAt: Date(timeIntervalSince1970: 1)
            )
        ) { error in
            XCTAssertEqual(error as? TimerValidationError, .tooManyTags)
        }

        XCTAssertThrowsError(
            try TimerItem.stopwatch(
                title: "Tag",
                tags: [String(repeating: "x", count: 33)],
                createdAt: Date(timeIntervalSince1970: 1)
            )
        ) { error in
            XCTAssertEqual(error as? TimerValidationError, .tagTooLong)
        }
    }

    func testCountdownRejectsAllNonFiniteAndNonPositiveDurations() {
        for duration in [
            TimeInterval(0),
            -1,
            .nan,
            .infinity,
            -.infinity
        ] {
            XCTAssertThrowsError(
                try TimerItem.countdown(title: "Invalid", duration: duration, createdAt: Date(timeIntervalSince1970: 1))
            ) { error in
                XCTAssertEqual(error as? TimerValidationError, .nonPositiveDuration)
            }
        }
    }

    func testEmptyTitleIsValidAndStopwatchHasNoCountdownFields() throws {
        let item = try TimerItem.stopwatch(title: "", createdAt: Date(timeIntervalSince1970: 1))

        XCTAssertTrue(item.title.isEmpty)
        XCTAssertNil(item.duration)
        XCTAssertNil(item.remaining)
        XCTAssertNil(item.deadline)
    }

    func testMetadataUpdatesRemainValidatedAfterConstruction() throws {
        var item = try TimerItem.stopwatch(title: "Tea", createdAt: Date(timeIntervalSince1970: 1))

        XCTAssertThrowsError(
            try item.updateMetadata(
                title: "Tea",
                details: String(repeating: "D", count: 501),
                tags: []
            )
        ) { error in
            XCTAssertEqual(error as? TimerValidationError, .descriptionTooLong)
        }
        XCTAssertEqual(item.details, "")
    }

    func testTimerItemRoundTripsThroughCodable() throws {
        let date = Date(timeIntervalSince1970: 1_000)
        let item = try TimerItem.countdown(
            title: "Focus",
            duration: 60,
            details: "Deep work",
            tags: ["client"],
            recurrence: .weekly(weekday: 2, hour: 9, minute: 30),
            alertName: "Ping",
            alertVolume: 0.5,
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            occurrenceID: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            createdAt: date
        )

        let data = try JSONEncoder().encode(item)
        XCTAssertEqual(try JSONDecoder().decode(TimerItem.self, from: data), item)
    }

    func testHistoryEntryValidatesAndRoundTripsThroughCodable() throws {
        let date = Date(timeIntervalSince1970: 1_000)
        let entry = try HistoryEntry(
            timerID: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            occurrenceID: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            title: "Tea",
            details: "Break",
            tags: ["rest"],
            kind: .stopwatch,
            startedAt: date,
            endedAt: date.addingTimeInterval(30),
            elapsedSeconds: 30,
            completionReason: .stopped
        )
        let data = try JSONEncoder().encode(entry)

        XCTAssertEqual(try JSONDecoder().decode(HistoryEntry.self, from: data), entry)
        XCTAssertThrowsError(
            try HistoryEntry(
                timerID: entry.timerID,
                occurrenceID: entry.occurrenceID,
                title: String(repeating: "T", count: 81),
                kind: .stopwatch,
                endedAt: date,
                elapsedSeconds: 0,
                completionReason: .stopped
            )
        ) { error in
            XCTAssertEqual(error as? TimerValidationError, .titleTooLong)
        }
    }

    func testCorruptedPersistedShapesAreRejected() throws {
        let item = try TimerItem.stopwatch(title: "Watch", createdAt: Date(timeIntervalSince1970: 1))
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any]
        )
        object["duration"] = 10.0
        object["remaining"] = 10.0
        object["deadline"] = 11.0
        let data = try JSONSerialization.data(withJSONObject: object)

        XCTAssertThrowsError(try JSONDecoder().decode(TimerItem.self, from: data)) { error in
            guard case DecodingError.dataCorrupted = error else {
                return XCTFail("Expected dataCorrupted, got \(error)")
            }
        }
    }

    func testPersistedRunningAndPausedShapesAreAcceptedOnlyWhenCoherent() throws {
        let date = Date(timeIntervalSince1970: 1_000)
        var running = try TimerItem.countdown(title: "Focus", duration: 60, createdAt: date)
        running.state = .running
        running.startedAt = date
        running.deadline = date.addingTimeInterval(60)

        let runningData = try JSONEncoder().encode(running)
        XCTAssertEqual(try JSONDecoder().decode(TimerItem.self, from: runningData), running)

        var malformedRunning = running
        malformedRunning.startedAt = nil
        XCTAssertThrowsError(
            try JSONDecoder().decode(TimerItem.self, from: JSONEncoder().encode(malformedRunning))
        ) { error in
            guard case DecodingError.dataCorrupted = error else {
                return XCTFail("Expected dataCorrupted, got \(error)")
            }
        }

        var paused = try TimerItem.countdown(title: "Focus", duration: 60, createdAt: date)
        paused.state = .paused
        paused.startedAt = date
        paused.pausedAt = date.addingTimeInterval(20)
        paused.remaining = 40
        let pausedData = try JSONEncoder().encode(paused)
        XCTAssertEqual(try JSONDecoder().decode(TimerItem.self, from: pausedData), paused)

        paused.remaining = nil
        XCTAssertThrowsError(
            try JSONDecoder().decode(TimerItem.self, from: JSONEncoder().encode(paused))
        )
    }

    func testInvalidRecurrenceIsRejected() {
        let date = Date(timeIntervalSince1970: 1)
        let cases: [(RecurrenceRule, RecurrenceValidationError)] = [
            (.interval(seconds: 0), .invalidInterval),
            (.daily(hour: 24, minute: 0), .invalidClockTime),
            (.weekly(weekday: 0, hour: 9, minute: 0), .invalidWeekday),
            (.selectedWeekdays(weekdays: [], hour: 9, minute: 0), .emptyWeekdays)
        ]
        for (rule, expectedError) in cases {
            XCTAssertThrowsError(
                try TimerItem.countdown(title: "Timer", duration: 60, recurrence: rule, createdAt: date)
            ) { error in
                XCTAssertEqual(error as? RecurrenceValidationError, expectedError)
            }
        }
    }
}
