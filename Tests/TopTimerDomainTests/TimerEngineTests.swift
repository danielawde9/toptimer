import XCTest
@testable import TopTimerDomain

final class TimerEngineTests: XCTestCase {
    private let firstID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    private let secondID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!

    private func roundTrip(_ timer: TimerItem, file: StaticString = #filePath, line: UInt = #line) throws {
        let data = try JSONEncoder().encode(timer)
        XCTAssertEqual(try JSONDecoder().decode(TimerItem.self, from: data), timer, file: file, line: line)
    }

    func testSleepDoesNotIntroduceCountdownDrift() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        var timer = try TimerItem.countdown(title: "Focus", duration: 60)
        try timer.start(at: start)

        XCTAssertEqual(timer.remaining(at: start.addingTimeInterval(45)), 15)
        XCTAssertTrue(timer.isDue(at: start.addingTimeInterval(61)))
    }

    func testPauseAndResumePreserveRemainingTime() throws {
        let start = Date(timeIntervalSince1970: 2_000)
        var timer = try TimerItem.countdown(title: "Focus", duration: 60)
        try timer.start(at: start)
        try timer.pause(at: start.addingTimeInterval(20))
        try timer.resume(at: start.addingTimeInterval(200))

        XCTAssertEqual(timer.remaining(at: start.addingTimeInterval(210)), 30)
    }

    func testCountdownTransitionsRoundTripAndCompletesExactlyOnce() throws {
        let start = Date(timeIntervalSince1970: 3_000)
        var timer = try TimerItem.countdown(
            title: "Focus",
            duration: 60,
            id: firstID,
            occurrenceID: secondID,
            createdAt: start
        )
        XCTAssertEqual(timer.state, .idle)
        XCTAssertEqual(timer.remaining(at: start), 60)
        try roundTrip(timer)

        try timer.start(at: start)
        XCTAssertEqual(timer.state, .running)
        XCTAssertEqual(timer.startedAt, start)
        XCTAssertEqual(timer.lastTransitionAt, start)
        XCTAssertEqual(timer.deadline, start.addingTimeInterval(60))
        try roundTrip(timer)

        try timer.pause(at: start.addingTimeInterval(20))
        XCTAssertEqual(timer.state, .paused)
        XCTAssertEqual(timer.remaining, 40)
        XCTAssertEqual(timer.lastTransitionAt, start.addingTimeInterval(20))
        XCTAssertNil(timer.deadline)
        try roundTrip(timer)

        try timer.resume(at: start.addingTimeInterval(100))
        XCTAssertEqual(timer.state, .running)
        XCTAssertEqual(timer.startedAt, start)
        XCTAssertEqual(timer.lastTransitionAt, start.addingTimeInterval(100))
        XCTAssertEqual(timer.deadline, start.addingTimeInterval(140))
        try roundTrip(timer)

        try timer.complete(at: start.addingTimeInterval(141))
        XCTAssertEqual(timer.state, .completed)
        XCTAssertEqual(timer.completedAt, start.addingTimeInterval(141))
        XCTAssertEqual(timer.lastTransitionAt, start.addingTimeInterval(141))
        XCTAssertEqual(timer.remaining(at: start.addingTimeInterval(141)), 0)
        try roundTrip(timer)
        XCTAssertThrowsError(try timer.complete(at: start.addingTimeInterval(142))) { error in
            XCTAssertEqual(error as? TimerTransitionError, .alreadyCompleted)
        }
    }

    func testRestartClearsCompletionAndUsesOriginalDuration() throws {
        let start = Date(timeIntervalSince1970: 4_000)
        var timer = try TimerItem.countdown(title: "Focus", duration: 90, createdAt: start)
        try timer.start(at: start)
        try timer.complete(at: start.addingTimeInterval(90))
        try timer.acknowledge(at: start.addingTimeInterval(91))
        XCTAssertEqual(timer.state, .acknowledged)

        let restart = start.addingTimeInterval(300)
        try timer.restart(at: restart)
        XCTAssertEqual(timer.state, .running)
        XCTAssertEqual(timer.startedAt, restart)
        XCTAssertEqual(timer.lastTransitionAt, restart)
        XCTAssertEqual(timer.deadline, restart.addingTimeInterval(90))
        XCTAssertNil(timer.completedAt)
        XCTAssertNil(timer.deletedAt)
        try roundTrip(timer)
    }

    func testAcknowledgeDismissesCompletedTimerWithoutChangingCompletion() throws {
        let start = Date(timeIntervalSince1970: 5_000)
        var timer = try TimerItem.countdown(title: "Focus", duration: 1, createdAt: start)
        try timer.start(at: start)
        try timer.complete(at: start.addingTimeInterval(1))
        let completion = timer.completedAt
        try timer.acknowledge(at: start.addingTimeInterval(2))

        XCTAssertEqual(timer.state, .acknowledged)
        XCTAssertEqual(timer.completedAt, completion)
        XCTAssertEqual(timer.deletedAt, start.addingTimeInterval(2))
        XCTAssertEqual(timer.remaining(at: start.addingTimeInterval(2)), 0)
        try roundTrip(timer)
    }

    func testDuplicateIsReadyWithNewIdentitiesAndSameMetadata() throws {
        let start = Date(timeIntervalSince1970: 6_000)
        let timer = try TimerItem.countdown(
            title: "Focus",
            duration: 75,
            details: "Deep work",
            tags: ["client"],
            recurrence: .daily(hour: 9, minute: 30),
            alertName: "Ping",
            alertVolume: 0.4,
            id: firstID,
            occurrenceID: secondID,
            createdAt: start
        )
        let duplicate = try timer.duplicate(at: start.addingTimeInterval(10))

        XCTAssertNotEqual(duplicate.id, timer.id)
        XCTAssertNotEqual(duplicate.occurrenceID, timer.occurrenceID)
        XCTAssertEqual(duplicate.state, .idle)
        XCTAssertEqual(duplicate.title, timer.title)
        XCTAssertEqual(duplicate.details, timer.details)
        XCTAssertEqual(duplicate.tags, timer.tags)
        XCTAssertEqual(duplicate.duration, timer.duration)
        XCTAssertEqual(duplicate.recurrence, timer.recurrence)
        XCTAssertEqual(duplicate.alertName, timer.alertName)
        XCTAssertEqual(duplicate.alertVolume, timer.alertVolume)
        XCTAssertNil(duplicate.lastTransitionAt)
        try roundTrip(duplicate)
    }

    func testStopwatchElapsedExcludesPausedWallTimeAndCompletes() throws {
        let start = Date(timeIntervalSince1970: 7_000)
        var timer = try TimerItem.stopwatch(title: "Watch", createdAt: start)
        try timer.start(at: start)
        XCTAssertEqual(timer.elapsed(at: start.addingTimeInterval(30)), 30)
        try timer.pause(at: start.addingTimeInterval(30))
        XCTAssertEqual(timer.elapsed(at: start.addingTimeInterval(90)), 30)
        try roundTrip(timer)

        try timer.resume(at: start.addingTimeInterval(90))
        XCTAssertEqual(timer.startedAt, start)
        XCTAssertEqual(timer.elapsed(at: start.addingTimeInterval(120)), 60)
        try timer.complete(at: start.addingTimeInterval(150))
        XCTAssertEqual(timer.elapsed(at: start.addingTimeInterval(500)), 90)
        XCTAssertEqual(timer.state, .completed)
        try roundTrip(timer)
    }

    func testCompletingPausedStopwatchExcludesTheFinalPauseSegment() throws {
        let start = Date(timeIntervalSince1970: 7_500)
        var timer = try TimerItem.stopwatch(title: "Watch", createdAt: start)
        try timer.start(at: start)
        try timer.pause(at: start.addingTimeInterval(30))
        try timer.complete(at: start.addingTimeInterval(90))

        XCTAssertEqual(timer.elapsed(at: start.addingTimeInterval(500)), 30)
        try roundTrip(timer)
    }

    func testCountdownRejectsBackwardPauseAfterResume() throws {
        let start = Date(timeIntervalSince1970: 7_750)
        var timer = try TimerItem.countdown(title: "Focus", duration: 60, createdAt: start)
        try timer.start(at: start)
        try timer.pause(at: start.addingTimeInterval(20))
        try timer.resume(at: start.addingTimeInterval(100))

        XCTAssertThrowsError(try timer.pause(at: start.addingTimeInterval(50))) { error in
            XCTAssertEqual(error as? TimerTransitionError, .invalidTimestamp)
        }
        try roundTrip(timer)
    }

    func testStopwatchRejectsBackwardCompletionAfterResume() throws {
        let start = Date(timeIntervalSince1970: 7_800)
        var timer = try TimerItem.stopwatch(title: "Watch", createdAt: start)
        try timer.start(at: start)
        try timer.pause(at: start.addingTimeInterval(20))
        try timer.resume(at: start.addingTimeInterval(100))

        XCTAssertThrowsError(try timer.complete(at: start.addingTimeInterval(50))) { error in
            XCTAssertEqual(error as? TimerTransitionError, .invalidTimestamp)
        }
        try roundTrip(timer)
    }

    func testRestartRejectsBackwardTransitionAndResetsBookkeepingForward() throws {
        let start = Date(timeIntervalSince1970: 7_850)
        var timer = try TimerItem.countdown(title: "Focus", duration: 60, createdAt: start)
        try timer.start(at: start)
        try timer.pause(at: start.addingTimeInterval(20))
        try timer.resume(at: start.addingTimeInterval(100))

        XCTAssertThrowsError(try timer.restart(at: start.addingTimeInterval(50))) { error in
            XCTAssertEqual(error as? TimerTransitionError, .invalidTimestamp)
        }

        let restart = start.addingTimeInterval(200)
        try timer.restart(at: restart)
        XCTAssertEqual(timer.lastTransitionAt, restart)
        XCTAssertEqual(timer.startedAt, restart)
        XCTAssertEqual(timer.remaining(at: restart), 60)
        try roundTrip(timer)
    }

    func testInvalidTransitionsAreRejected() throws {
        let start = Date(timeIntervalSince1970: 8_000)
        var timer = try TimerItem.countdown(title: "Focus", duration: 60, createdAt: start)
        XCTAssertThrowsError(try timer.pause(at: start))
        XCTAssertThrowsError(try timer.resume(at: start))
        XCTAssertThrowsError(try timer.complete(at: start))

        try timer.start(at: start)
        XCTAssertThrowsError(try timer.start(at: start)) { error in
            XCTAssertEqual(error as? TimerTransitionError, .invalidState)
        }
        XCTAssertThrowsError(try timer.complete(at: start.addingTimeInterval(59))) { error in
            XCTAssertEqual(error as? TimerTransitionError, .notDue)
        }
        XCTAssertThrowsError(try timer.acknowledge(at: start))
        XCTAssertThrowsError(try timer.pause(at: start.addingTimeInterval(-1))) { error in
            XCTAssertEqual(error as? TimerTransitionError, .invalidTimestamp)
        }
    }

    func testPriorityPrefersSoonestCountdownThenOldestStopwatch() throws {
        let start = Date(timeIntervalSince1970: 9_000)
        var later = try TimerItem.countdown(title: "Later", duration: 120, id: secondID, createdAt: start)
        var sooner = try TimerItem.countdown(title: "Sooner", duration: 60, id: firstID, createdAt: start)
        try later.start(at: start)
        try sooner.start(at: start)
        XCTAssertEqual(TimerPriority.select(from: [later, sooner], at: start)?.id, firstID)

        var stopwatch = try TimerItem.stopwatch(title: "Watch", id: secondID, createdAt: start)
        try stopwatch.start(at: start)
        XCTAssertEqual(TimerPriority.select(from: [stopwatch], at: start)?.id, secondID)
    }

    func testPriorityTiesBreakByUUID() throws {
        let start = Date(timeIntervalSince1970: 10_000)
        var first = try TimerItem.countdown(title: "First", duration: 60, id: firstID, createdAt: start)
        var second = try TimerItem.countdown(title: "Second", duration: 60, id: secondID, createdAt: start)
        try first.start(at: start)
        try second.start(at: start)
        XCTAssertEqual(TimerPriority.select(from: [second, first], at: start)?.id, firstID)

        try first.complete(at: start.addingTimeInterval(60))
        try second.complete(at: start.addingTimeInterval(60))
        var firstWatch = try TimerItem.stopwatch(title: "First", id: firstID, createdAt: start)
        var secondWatch = try TimerItem.stopwatch(title: "Second", id: secondID, createdAt: start)
        try firstWatch.start(at: start)
        try secondWatch.start(at: start)
        XCTAssertEqual(TimerPriority.select(from: [secondWatch, firstWatch], at: start)?.id, firstID)
    }
}
