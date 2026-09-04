import Foundation
import XCTest
@testable import TopTimerDomain

final class RecurrenceCalculatorTests: XCTestCase {
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var newYorkCalendar: Calendar {
        var calendar = utcCalendar
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func localDate(
        _ calendar: Calendar,
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0,
        minute: Int = 0
    ) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testWeekdayRuleSkipsWeekend() throws {
        let friday = date("2026-09-04T15:00:00+03:00")
        let calculator = RecurrenceCalculator(calendar: utcCalendar)

        let next = try calculator.nextDate(after: friday, rule: .weekdays(hour: 9, minute: 0))

        XCTAssertEqual(next, date("2026-09-07T09:00:00+00:00"))
    }

    func testDailyRuleUsesNextLocalOccurrence() throws {
        let reference = localDate(utcCalendar, year: 2026, month: 9, day: 4, hour: 15)
        let calculator = RecurrenceCalculator(calendar: utcCalendar)

        XCTAssertEqual(
            try calculator.nextDate(after: reference, rule: .daily(hour: 9, minute: 0)),
            localDate(utcCalendar, year: 2026, month: 9, day: 5, hour: 9)
        )
    }

    func testDailyRuleAtExactScheduledTimeAdvancesStrictly() throws {
        let reference = localDate(utcCalendar, year: 2026, month: 9, day: 4, hour: 9)
        let calculator = RecurrenceCalculator(calendar: utcCalendar)

        XCTAssertEqual(
            try calculator.nextDate(after: reference, rule: .daily(hour: 9, minute: 0)),
            localDate(utcCalendar, year: 2026, month: 9, day: 5, hour: 9)
        )
    }

    func testWeeklyAndSelectedWeekdayRules() throws {
        let reference = localDate(utcCalendar, year: 2026, month: 9, day: 4, hour: 15)
        let calculator = RecurrenceCalculator(calendar: utcCalendar)

        XCTAssertEqual(
            try calculator.nextDate(after: reference, rule: .weekly(weekday: 2, hour: 9, minute: 0)),
            localDate(utcCalendar, year: 2026, month: 9, day: 7, hour: 9)
        )
        XCTAssertEqual(
            try calculator.nextDate(after: reference, rule: .selectedWeekdays(weekdays: [2, 6], hour: 9, minute: 0)),
            localDate(utcCalendar, year: 2026, month: 9, day: 7, hour: 9)
        )
    }

    func testSelectedWeekdayRuleRejectsInvalidWeekdayDirectly() {
        let calculator = RecurrenceCalculator(calendar: utcCalendar)
        let reference = localDate(utcCalendar, year: 2026, month: 9, day: 4, hour: 15)

        XCTAssertThrowsError(
            try calculator.nextDate(after: reference, rule: .selectedWeekdays(weekdays: [0], hour: 9, minute: 0))
        ) { error in
            XCTAssertEqual(error as? RecurrenceCalculatorError, .invalidWeekday)
        }
    }

    func testIntervalBoundsAreInclusiveAndResultsAreStrictlyLater() throws {
        let reference = date("2026-09-04T12:00:00+00:00")
        let calculator = RecurrenceCalculator(calendar: utcCalendar)

        XCTAssertEqual(
            try calculator.nextDate(after: reference, rule: .interval(seconds: 1)),
            reference.addingTimeInterval(1)
        )
        XCTAssertEqual(
            try calculator.nextDate(after: reference, rule: .interval(seconds: 365 * 24 * 60 * 60)),
            reference.addingTimeInterval(365 * 24 * 60 * 60)
        )
        XCTAssertThrowsError(try calculator.nextDate(after: reference, rule: .interval(seconds: 0))) { error in
            XCTAssertEqual(error as? RecurrenceCalculatorError, .invalidInterval)
        }
        XCTAssertThrowsError(try calculator.nextDate(after: reference, rule: .interval(seconds: 365 * 24 * 60 * 60 + 1))) { error in
            XCTAssertEqual(error as? RecurrenceCalculatorError, .invalidInterval)
        }
    }

    func testTimerFactoryRejectsOutOfRangeIntervals() {
        let created = date("2026-09-04T12:00:00+00:00")
        let invalidIntervals: [TimeInterval] = [0.5, 365 * 24 * 60 * 60 + 1]
        for seconds in invalidIntervals {
            XCTAssertThrowsError(
                try TimerItem.countdown(title: "Invalid", duration: 60, recurrence: .interval(seconds: seconds), createdAt: created)
            ) { error in
                XCTAssertEqual(error as? RecurrenceValidationError, .invalidInterval)
            }
        }
    }

    func testDSTNonexistentTimeAdvancesAndRepeatedTimeChoosesFirstOccurrence() throws {
        let calculator = RecurrenceCalculator(calendar: newYorkCalendar)
        let springReference = localDate(newYorkCalendar, year: 2026, month: 3, day: 8, hour: 1, minute: 59)
        let spring = try calculator.nextDate(after: springReference, rule: .daily(hour: 2, minute: 30))
        XCTAssertEqual(spring, date("2026-03-08T07:00:00+00:00"))

        let fallReference = localDate(newYorkCalendar, year: 2026, month: 11, day: 1, hour: 0, minute: 30)
        let fall = try calculator.nextDate(after: fallReference, rule: .daily(hour: 1, minute: 30))
        XCTAssertEqual(fall, date("2026-11-01T05:30:00+00:00"))
    }

    func testRepeatedTimeChoosesFirstOccurrenceStillLaterThanReference() throws {
        let calculator = RecurrenceCalculator(calendar: newYorkCalendar)
        let reference = localDate(newYorkCalendar, year: 2026, month: 11, day: 1, hour: 1, minute: 45)

        let next = try calculator.nextDate(after: reference, rule: .daily(hour: 1, minute: 30))

        XCTAssertEqual(next, date("2026-11-01T06:30:00+00:00"))
    }

    func testCalendarTimeZoneControlsLocalRecurrence() throws {
        let reference = date("2026-09-04T15:00:00+00:00")
        let calculator = RecurrenceCalculator(calendar: newYorkCalendar)

        XCTAssertEqual(
            try calculator.nextDate(after: reference, rule: .daily(hour: 9, minute: 0)),
            date("2026-09-05T13:00:00+00:00")
        )
    }

    func testCalendarSearchHasBoundedNoDateFailure() {
        let calculator = RecurrenceCalculator(calendar: utcCalendar)
        let unrepresentableReference = Date(timeIntervalSinceReferenceDate: .greatestFiniteMagnitude)

        XCTAssertThrowsError(
            try calculator.nextDate(after: unrepresentableReference, rule: .daily(hour: 9, minute: 0))
        ) { error in
            XCTAssertEqual(error as? RecurrenceCalculatorError, .noDateFound)
        }
    }

    func testCompletionCreatesOnlyOneSuccessor() throws {
        let created = date("2026-09-04T14:00:00+00:00")
        let dueDate = date("2026-09-04T15:00:00+00:00")
        var timer = try TimerItem.countdown(
            title: "Focus",
            duration: 60,
            details: "Deep work",
            tags: ["client"],
            recurrence: .interval(seconds: 300),
            alertName: "Ping",
            alertVolume: 0.5,
            createdAt: created
        )
        try timer.start(at: created)
        let recurrence = RecurrenceService(calendar: utcCalendar)

        let result1 = try recurrence.complete(timer, at: dueDate)
        let result2 = try recurrence.complete(result1.completed, at: dueDate)

        let successor = try XCTUnwrap(result1.successor)
        XCTAssertEqual(result1.completed.state, .completed)
        XCTAssertEqual(result1.completed.successorID, successor.id)
        XCTAssertNil(result2.successor)
        XCTAssertEqual(result2.completed, result1.completed)
        XCTAssertNotEqual(successor.id, result1.completed.id)
        XCTAssertNotEqual(successor.occurrenceID, result1.completed.occurrenceID)
        XCTAssertEqual(successor.state, .running)
        XCTAssertEqual(successor.deadline, dueDate.addingTimeInterval(300))
        XCTAssertEqual(successor.title, timer.title)
        XCTAssertEqual(successor.details, timer.details)
        XCTAssertEqual(successor.tags, timer.tags)
        XCTAssertEqual(successor.duration, 300)
        XCTAssertEqual(successor.alertName, timer.alertName)
        XCTAssertEqual(successor.alertVolume, timer.alertVolume)
        XCTAssertEqual(successor.recurrence, timer.recurrence)
    }

    func testCalendarSuccessorDurationIsScheduledWindowAndSurvivesPausePersistence() throws {
        let created = localDate(utcCalendar, year: 2026, month: 9, day: 4, hour: 14)
        let dueDate = localDate(utcCalendar, year: 2026, month: 9, day: 4, hour: 15)
        var timer = try TimerItem.countdown(
            title: "Daily",
            duration: 60,
            recurrence: .daily(hour: 9, minute: 0),
            createdAt: created
        )
        try timer.start(at: created)
        let outcome = try RecurrenceService(calendar: utcCalendar).complete(timer, at: dueDate)
        var successor = try XCTUnwrap(outcome.successor)
        let nextDeadline = localDate(utcCalendar, year: 2026, month: 9, day: 5, hour: 9)
        let scheduledWindow = nextDeadline.timeIntervalSince(dueDate)

        XCTAssertEqual(successor.duration, scheduledWindow)
        XCTAssertEqual(successor.remaining(at: dueDate), scheduledWindow)
        try successor.pause(at: nextDeadline.addingTimeInterval(-3_600))
        let data = try JSONEncoder().encode(successor)
        var restored = try JSONDecoder().decode(TimerItem.self, from: data)
        XCTAssertEqual(restored.remaining, 3_600)
        try restored.resume(at: nextDeadline.addingTimeInterval(-1_800))
        XCTAssertEqual(restored.deadline, nextDeadline.addingTimeInterval(-1_800 + 3_600))
        try restored.restart(at: nextDeadline.addingTimeInterval(3_600))
        XCTAssertEqual(restored.deadline, nextDeadline.addingTimeInterval(3_600).addingTimeInterval(scheduledWindow))
    }

    func testWeeklySuccessorDurationIsScheduledWindowAndCanBePausedAndEncoded() throws {
        let created = localDate(utcCalendar, year: 2026, month: 9, day: 4, hour: 14)
        let dueDate = localDate(utcCalendar, year: 2026, month: 9, day: 4, hour: 15)
        var timer = try TimerItem.countdown(
            title: "Weekly",
            duration: 60,
            recurrence: .weekly(weekday: 2, hour: 9, minute: 0),
            createdAt: created
        )
        try timer.start(at: created)
        let outcome = try RecurrenceService(calendar: utcCalendar).complete(timer, at: dueDate)
        var successor = try XCTUnwrap(outcome.successor)
        let nextDeadline = localDate(utcCalendar, year: 2026, month: 9, day: 7, hour: 9)

        XCTAssertEqual(successor.duration, nextDeadline.timeIntervalSince(dueDate))
        try successor.pause(at: nextDeadline.addingTimeInterval(-7_200))
        XCTAssertNoThrow(try JSONEncoder().encode(successor))
    }

    func testIdenticalStaleSnapshotsProduceIdenticalSuccessorIdentities() throws {
        let created = date("2026-09-04T14:00:00+00:00")
        let dueDate = date("2026-09-04T15:00:00+00:00")
        var timer = try TimerItem.countdown(title: "Stable", duration: 60, recurrence: .interval(seconds: 300), createdAt: created)
        try timer.start(at: created)
        let service = RecurrenceService(calendar: utcCalendar)

        let first = try service.complete(timer, at: dueDate)
        let second = try service.complete(timer, at: dueDate)
        XCTAssertEqual(first.completed.successorID, second.completed.successorID)
        XCTAssertEqual(first.successor?.id, second.successor?.id)
        XCTAssertEqual(first.successor?.occurrenceID, second.successor?.occurrenceID)
        XCTAssertEqual(first.successor?.predecessorOccurrenceID, timer.occurrenceID)
        let successorID = try XCTUnwrap(first.successor?.id)
        XCTAssertEqual(successorID.uuid.6 & 0xF0, 0x50)
        XCTAssertEqual(successorID.uuid.8 & 0xC0, 0x80)
    }

    func testStopwatchRecurrenceIsRejectedAtEveryBoundary() throws {
        let created = date("2026-09-04T14:00:00+00:00")
        XCTAssertThrowsError(
            try TimerItem.stopwatch(title: "Watch", recurrence: .daily(hour: 9, minute: 0), createdAt: created)
        ) { error in
            XCTAssertEqual(error as? TimerValidationError, .recurrenceUnsupportedForStopwatch)
        }

        var stale = try TimerItem.stopwatch(title: "Watch", createdAt: created)
        stale.recurrence = .daily(hour: 9, minute: 0)
        XCTAssertThrowsError(try stale.duplicate(at: created)) { error in
            XCTAssertEqual(error as? TimerValidationError, .recurrenceUnsupportedForStopwatch)
        }
        XCTAssertThrowsError(try JSONEncoder().encode(stale))
        let validData = try JSONEncoder().encode(try TimerItem.stopwatch(title: "Valid", createdAt: created))
        var corrupted = try XCTUnwrap(JSONSerialization.jsonObject(with: validData) as? [String: Any])
        let recurringData = try JSONEncoder().encode(
            try TimerItem.countdown(title: "Recurring", duration: 60, recurrence: .daily(hour: 9, minute: 0), createdAt: created)
        )
        let recurringObject = try XCTUnwrap(JSONSerialization.jsonObject(with: recurringData) as? [String: Any])
        corrupted["recurrence"] = recurringObject["recurrence"]
        XCTAssertThrowsError(
            try JSONDecoder().decode(TimerItem.self, from: JSONSerialization.data(withJSONObject: corrupted))
        )
        try stale.start(at: created)
        XCTAssertThrowsError(try RecurrenceService(calendar: utcCalendar).complete(stale, at: created)) { error in
            XCTAssertEqual(error as? TimerValidationError, .recurrenceUnsupportedForStopwatch)
        }
    }

    func testCancelledTimerCannotBeCompletedByRecurrenceService() throws {
        let created = date("2026-09-04T14:00:00+00:00")
        var timer = try TimerItem.countdown(title: "Cancelled", duration: 60, recurrence: .interval(seconds: 300), createdAt: created)
        try timer.start(at: created)
        try timer.cancel(at: created.addingTimeInterval(60))

        XCTAssertThrowsError(try RecurrenceService(calendar: utcCalendar).complete(timer, at: created.addingTimeInterval(60))) { error in
            XCTAssertEqual(error as? TimerTransitionError, .invalidState)
        }
    }

    func testOutcomeCodableRejectsBrokenSuccessorLinks() throws {
        let created = date("2026-09-04T14:00:00+00:00")
        let dueDate = date("2026-09-04T15:00:00+00:00")
        var timer = try TimerItem.countdown(title: "Links", duration: 60, recurrence: .interval(seconds: 60), createdAt: created)
        try timer.start(at: created)
        let outcome = try RecurrenceService(calendar: utcCalendar).complete(timer, at: dueDate)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(outcome)) as? [String: Any])
        var completed = try XCTUnwrap(object["completed"] as? [String: Any])
        completed["successorID"] = nil
        object["completed"] = completed
        let malformed = try JSONSerialization.data(withJSONObject: object)

        XCTAssertThrowsError(try JSONDecoder().decode(CompletionOutcome.self, from: malformed))
    }

    func testCompletionOutcomeRoundTripsCompletedAndSuccessor() throws {
        let created = date("2026-09-04T14:00:00+00:00")
        let dueDate = date("2026-09-04T15:00:00+00:00")
        var timer = try TimerItem.countdown(title: "Focus", duration: 60, recurrence: .interval(seconds: 60), createdAt: created)
        try timer.start(at: created)
        let outcome = try RecurrenceService(calendar: utcCalendar).complete(timer, at: dueDate)
        let successor = try XCTUnwrap(outcome.successor)

        let completedData = try JSONEncoder().encode(outcome.completed)
        let successorData = try JSONEncoder().encode(successor)
        let outcomeData = try JSONEncoder().encode(outcome)
        XCTAssertEqual(try JSONDecoder().decode(TimerItem.self, from: completedData), outcome.completed)
        XCTAssertEqual(try JSONDecoder().decode(TimerItem.self, from: successorData), successor)
        XCTAssertEqual(try JSONDecoder().decode(CompletionOutcome.self, from: outcomeData), outcome)
    }

    func testNoRecurrenceProducesNoSuccessor() throws {
        let created = date("2026-09-04T14:00:00+00:00")
        let dueDate = date("2026-09-04T15:00:00+00:00")
        var timer = try TimerItem.countdown(title: "Once", duration: 60, createdAt: created)
        try timer.start(at: created)

        let outcome = try RecurrenceService(calendar: utcCalendar).complete(timer, at: dueDate)

        XCTAssertNil(outcome.successor)
        XCTAssertNil(outcome.completed.successorID)
        XCTAssertThrowsError(
            try RecurrenceService(calendar: utcCalendar).complete(outcome.completed, at: dueDate)
        ) { error in
            XCTAssertEqual(error as? TimerTransitionError, .alreadyCompleted)
        }
    }
}
