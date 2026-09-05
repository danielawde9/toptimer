import XCTest
import Foundation
import TopTimerDomain
@testable import TopTimerPersistence

final class TimerRepositoryTests: XCTestCase {
    private let created = Date(timeIntervalSinceReferenceDate: 1_000)
    private let completed = Date(timeIntervalSinceReferenceDate: 1_100)

    func testInMemoryStoreCreatesRepository() async throws {
        let store = try await CoreDataStore.inMemory()
        let repository = TimerCoreDataRepository(store: store)
        _ = repository
    }

    func testCompletionIsAtomicAndRetryCreatesOneHistoryAndSuccessor() async throws {
        let repository = try await repository()
        var timer = try countdown(recurrence: .interval(seconds: 300))
        try timer.start(at: created)
        _ = try await repository.insert(timer)

        let first = try await repository.complete(timer.id, at: completed)
        let second = try await repository.complete(timer.id, at: completed)

        XCTAssertEqual(first.completed.state, .completed)
        XCTAssertNotNil(first.successor)
        XCTAssertEqual(second.completed, first.completed)
        XCTAssertNil(second.successor)
        let historyCount = try await repository.historyCount(for: timer.id)
        let successorCount = try await repository.successors(of: timer.occurrenceID).count
        XCTAssertEqual(historyCount, 1)
        XCTAssertEqual(successorCount, 1)
    }

    func testSecondSuccessorForOnePredecessorIsRejectedByDatabase() async throws {
        let fixture = try await sqliteFixture()
        defer { fixture.removeFiles() }
        let repository = fixture.repository
        let predecessor = UUID()
        let first = try timerWithPredecessor(predecessor, occurrenceID: UUID())
        let second = try timerWithPredecessor(predecessor, occurrenceID: UUID())
        _ = try await repository.insert(first)

        do {
            _ = try await repository.insert(second)
            XCTFail("Expected predecessor uniqueness constraint to reject a second successor")
        } catch {
            XCTAssertFalse(error is TimerRepositoryError)
        }
    }

    func testDuplicateTimerAndHistoryOccurrencesAreRejectedByDatabase() async throws {
        let fixture = try await sqliteFixture()
        defer { fixture.removeFiles() }
        let repository = fixture.repository
        let occurrence = UUID()
        let first = try countdown(id: UUID(), occurrenceID: occurrence)
        let second = try countdown(id: UUID(), occurrenceID: occurrence)
        _ = try await repository.insert(first)
        await XCTAssertThrowsErrorAsync { _ = try await repository.insert(second) }

        let history = try HistoryEntry(
            timerID: first.id,
            occurrenceID: occurrence,
            title: first.title,
            kind: .countdown,
            endedAt: completed,
            elapsedSeconds: 60,
            completionReason: .finished
        )
        _ = try await repository.insertHistory(history)
        let duplicate = try HistoryEntry(
            timerID: UUID(),
            occurrenceID: occurrence,
            title: "Duplicate",
            kind: .countdown,
            endedAt: completed,
            elapsedSeconds: 60,
            completionReason: .finished
        )
        await XCTAssertThrowsErrorAsync { try await repository.insertHistory(duplicate) }
    }

    func testSQLiteReopenRecoversActiveAndCompletedTimers() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("TopTimer.sqlite")
        let active = try countdown(id: UUID(), occurrenceID: UUID())
        var done = try countdown(id: UUID(), occurrenceID: UUID())
        try done.start(at: created)

        do {
            let repository = TimerCoreDataRepository(store: try await CoreDataStore.sqlite(at: url), calendar: utcCalendar)
            _ = try await repository.insert(active)
            _ = try await repository.insert(done)
            _ = try await repository.complete(done.id, at: completed)
        }

        let repository = TimerCoreDataRepository(store: try await CoreDataStore.sqlite(at: url), calendar: utcCalendar)
        let recovered = try await repository.active(limit: 10)
        XCTAssertEqual(recovered, [active])
        let historyCount = try await repository.historyCount(for: done.id)
        XCTAssertEqual(historyCount, 1)
    }

    func testCompletionConstraintFailureRollsBackTimerAndHistory() async throws {
        let fixture = try await sqliteFixture()
        defer { fixture.removeFiles() }
        let repository = fixture.repository
        var source = try countdown(recurrence: .interval(seconds: 300))
        try source.start(at: created)
        let expected = try RecurrenceService(calendar: utcCalendar).complete(source, at: completed)
        let existingSuccessor = try XCTUnwrap(expected.successor)
        _ = try await repository.insert(source)
        _ = try await repository.insert(existingSuccessor)

        await XCTAssertThrowsErrorAsync { _ = try await repository.complete(source.id, at: self.completed) }

        let active = try await repository.active(limit: 10)
        XCTAssertTrue(active.contains(source))
        let historyCount = try await repository.historyCount(for: source.id)
        let successorCount = try await repository.successors(of: source.occurrenceID).count
        XCTAssertEqual(historyCount, 0)
        XCTAssertEqual(successorCount, 1)
    }

    func testActivePageIsBoundedAt200AndCursorGetsRemainder() async throws {
        let repository = try await repository()
        for offset in 0..<201 {
            let date = created.addingTimeInterval(TimeInterval(offset))
            let timer = try TimerItem.countdown(title: "\(offset)", duration: 60, createdAt: date)
            _ = try await repository.insert(timer)
        }

        let first = try await repository.activePage(limit: 200)
        let cursor = try XCTUnwrap(first.nextCursor)
        let second = try await repository.activePage(limit: 200, after: cursor)

        XCTAssertEqual(first.timers.count, 200)
        XCTAssertEqual(second.timers.count, 1)
        XCTAssertNil(second.nextCursor)
    }

    func testActiveRejectsLimitsOutsideClosedBound() async throws {
        let repository = try await repository()
        await XCTAssertThrowsErrorAsync({ _ = try await repository.active(limit: 0) }, matching: .invalidLimit)
        await XCTAssertThrowsErrorAsync({ _ = try await repository.active(limit: 201) }, matching: .invalidLimit)
        await XCTAssertThrowsErrorAsync({ _ = try await repository.activePage(limit: 0) }, matching: .invalidLimit)
        await XCTAssertThrowsErrorAsync({ _ = try await repository.historyCount(for: UUID(), limit: 201) }, matching: .invalidLimit)
        await XCTAssertThrowsErrorAsync({ _ = try await repository.successors(of: UUID(), limit: 0) }, matching: .invalidLimit)
    }

    func testUnknownVersionIsRejectedAndSelectedWeekdaysAreCanonical() throws {
        let timer = try countdown(recurrence: .selectedWeekdays(weekdays: [6, 2, 4], hour: 9, minute: 30))
        let encoded = try TimerPayloadCodec.encodeTimer(timer)
        let outer = try XCTUnwrap(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let payload = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(outer["payload"] as? String)))
        let timerObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: payload) as? [String: Any])
        let recurrence = try XCTUnwrap(timerObject["recurrence"] as? [String: Any])
        let selected = try XCTUnwrap(recurrence["selectedWeekdays"] as? [String: Any])
        XCTAssertEqual((selected["weekdays"] as? [NSNumber])?.map(\.intValue), [2, 4, 6])

        var unknown = outer
        unknown["version"] = 2
        let unknownData = try JSONSerialization.data(withJSONObject: unknown, options: [.sortedKeys])
        XCTAssertThrowsError(try TimerPayloadCodec.decodeTimer(unknownData)) { error in
            XCTAssertEqual(error as? TimerRepositoryError, .unsupportedPayloadVersion(2))
        }
    }

    func testSoftDeleteExcludesActiveWhilePreservingRecoverableRecord() async throws {
        let repository = try await repository()
        let timer = try countdown()
        _ = try await repository.insert(timer)

        try await repository.softDelete(timer.id, at: completed)

        let active = try await repository.active(limit: 1)
        XCTAssertEqual(active, [])
        let recovered = try await repository.timer(id: timer.id)
        XCTAssertEqual(recovered.deletedAt, completed)
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func repository() async throws -> TimerCoreDataRepository {
        TimerCoreDataRepository(store: try await CoreDataStore.inMemory(), calendar: utcCalendar)
    }

    private func sqliteFixture() async throws -> SQLiteFixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try await CoreDataStore.sqlite(at: directory.appendingPathComponent("TopTimer.sqlite"))
        return SQLiteFixture(
            repository: TimerCoreDataRepository(store: store, calendar: utcCalendar),
            directory: directory
        )
    }

    private func countdown(
        id: UUID = UUID(),
        occurrenceID: UUID = UUID(),
        recurrence: RecurrenceRule = .none
    ) throws -> TimerItem {
        try TimerItem.countdown(
            title: "Focus",
            duration: 60,
            recurrence: recurrence,
            id: id,
            occurrenceID: occurrenceID,
            createdAt: created
        )
    }

    private func timerWithPredecessor(_ predecessor: UUID, occurrenceID: UUID) throws -> TimerItem {
        let timer = try countdown(occurrenceID: occurrenceID)
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(timer)) as? [String: Any])
        object["predecessorOccurrenceID"] = predecessor.uuidString
        return try JSONDecoder().decode(TimerItem.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func XCTAssertThrowsErrorAsync(
        _ expression: @escaping () async throws -> Void,
        matching expected: TimerRepositoryError? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await expression()
            XCTFail("Expected an error", file: file, line: line)
        } catch {
            if let expected {
                XCTAssertEqual(error as? TimerRepositoryError, expected, file: file, line: line)
            }
        }
    }
}

private struct SQLiteFixture {
    let repository: TimerCoreDataRepository
    let directory: URL

    func removeFiles() {
        try? FileManager.default.removeItem(at: directory)
    }
}
