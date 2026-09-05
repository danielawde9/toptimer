import XCTest
@preconcurrency import CoreData
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

    func testSQLiteDescriptionDoesNotEnableUnusedPersistentHistoryTracking() {
        let description = CoreDataStore.sqliteDescription(
            at: FileManager.default.temporaryDirectory.appendingPathComponent("TopTimer.sqlite")
        )
        XCTAssertNil(description.options[NSPersistentHistoryTrackingKey])
    }

    func testUnsupportedStoreMetadataFailsWithStructuredMigrationError() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        do {
            _ = try await CoreDataStore.sqlite(at: directory)
            XCTFail("Expected a directory to be rejected as an unsupported SQLite store")
        } catch let error as CoreDataStoreError {
            guard case let .migrationFailed(domain, _, description) = error else {
                return XCTFail("Expected structured migration failure, got \(error)")
            }
            XCTAssertFalse(domain.isEmpty)
            XCTAssertFalse(description.isEmpty)
        }
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

    func testStaleRunningUpdateCannotRollbackCompletedRecurringSource() async throws {
        let repository = try await repository()
        var source = try countdown(recurrence: .interval(seconds: 300))
        try source.start(at: created)
        _ = try await repository.insert(source)
        let stale = try await repository.timer(id: source.id)

        let outcome = try await repository.complete(source.id, at: completed)
        await XCTAssertThrowsErrorAsync({ try await repository.update(stale) }, matching: .staleTimerUpdate)

        let persisted = try await repository.timer(id: source.id)
        let historyCount = try await repository.historyCount(for: source.id)
        let successorCount = try await repository.successors(of: source.occurrenceID).count
        XCTAssertEqual(persisted, outcome.completed)
        XCTAssertEqual(historyCount, 1)
        XCTAssertEqual(successorCount, 1)
    }

    func testUpdatePermitsForwardDomainTransitionsAndMetadataChanges() async throws {
        let repository = try await repository()
        var timer = try countdown()
        _ = try await repository.insert(timer)
        try timer.updateMetadata(title: "Edited", details: "Metadata", tags: ["work"])
        try await repository.update(timer)
        try timer.start(at: created)
        try await repository.update(timer)
        try timer.pause(at: created.addingTimeInterval(10))
        try await repository.update(timer)
        try timer.resume(at: created.addingTimeInterval(20))
        try await repository.update(timer)
        try timer.cancel(at: created.addingTimeInterval(30))
        try await repository.update(timer)

        let persisted = try await repository.timer(id: timer.id)
        XCTAssertEqual(persisted, timer)
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

    func testRawRowsEnforceSemanticPredecessorUniquenessWhileAllowingRoots() async throws {
        let fixture = try await sqliteFixture()
        defer { fixture.removeFiles() }
        let firstRoot = try countdown()
        let secondRoot = try countdown()
        try await fixture.store.perform { context in
            try insertRawTimer(firstRoot, predecessor: nil, in: context)
            try insertRawTimer(secondRoot, predecessor: nil, in: context)
            try context.save()
        }

        let predecessor = UUID()
        let firstChild = try countdown()
        let secondChild = try countdown()
        await XCTAssertThrowsErrorAsync {
            _ = try await fixture.store.perform { context in
                try insertRawTimer(firstChild, predecessor: predecessor, in: context)
                try insertRawTimer(secondChild, predecessor: predecessor, in: context)
                try context.save()
            }
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

    func testVersionOneSQLiteMigratesWithoutLosingTimerOrHistory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("TopTimer.sqlite")
        let timer = try countdown()
        let history = try HistoryEntry(
            timerID: timer.id,
            occurrenceID: timer.occurrenceID,
            title: timer.title,
            kind: timer.kind,
            endedAt: completed,
            elapsedSeconds: 60,
            completionReason: .finished
        )
        let timerPayload = try legacyEnvelope(payload: JSONEncoder().encode(timer))
        let historyPayload = try legacyEnvelope(payload: JSONEncoder().encode(history))

        try await writeLegacyV1Store(
            at: url,
            timer: timer,
            timerPayload: timerPayload,
            history: history,
            historyPayload: historyPayload
        )

        let repository = TimerCoreDataRepository(store: try await CoreDataStore.sqlite(at: url), calendar: utcCalendar)
        let recovered = try await repository.timer(id: timer.id)
        let historyCount = try await repository.historyCount(for: timer.id)
        XCTAssertEqual(recovered, timer)
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

    func testPublicBoundedAPIsClampLimitsToOneThroughTwoHundred() async throws {
        let repository = try await repository()
        for offset in 0..<201 {
            let timer = try TimerItem.countdown(
                title: "Timer \(offset)",
                duration: 60,
                createdAt: created.addingTimeInterval(TimeInterval(offset))
            )
            _ = try await repository.insert(timer)
        }

        let minimumActive = try await repository.active(limit: -1)
        let maximumActive = try await repository.active(limit: 201)
        let minimumPage = try await repository.activePage(limit: 0)
        let maximumPage = try await repository.activePage(limit: 201)
        XCTAssertEqual(minimumActive.count, 1)
        XCTAssertEqual(maximumActive.count, 200)
        XCTAssertEqual(minimumPage.timers.count, 1)
        XCTAssertEqual(maximumPage.timers.count, 200)

        let historyTimerID = UUID()
        for offset in 0..<201 {
            let history = try HistoryEntry(
                timerID: historyTimerID,
                occurrenceID: UUID(),
                title: "History \(offset)",
                kind: .countdown,
                endedAt: created.addingTimeInterval(TimeInterval(offset)),
                elapsedSeconds: 60,
                completionReason: .finished
            )
            try await repository.insertHistory(history)
        }
        let minimumHistory = try await repository.historyCount(for: historyTimerID, limit: -1)
        let maximumHistory = try await repository.historyCount(for: historyTimerID, limit: 201)
        XCTAssertEqual(minimumHistory, 1)
        XCTAssertEqual(maximumHistory, 200)

        let predecessor = UUID()
        let successor = try timerWithPredecessor(predecessor, occurrenceID: UUID())
        _ = try await repository.insert(successor)
        let minimumSuccessors = try await repository.successors(of: predecessor, limit: 0)
        let maximumSuccessors = try await repository.successors(of: predecessor, limit: 201)
        XCTAssertEqual(minimumSuccessors.count, 1)
        XCTAssertEqual(maximumSuccessors.count, 1)
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
        unknown["version"] = 3
        let unknownData = try JSONSerialization.data(withJSONObject: unknown, options: [.sortedKeys])
        XCTAssertThrowsError(try TimerPayloadCodec.decodeTimer(unknownData)) { error in
            XCTAssertEqual(error as? TimerRepositoryError, .unsupportedPayloadVersion(3))
        }
    }

    func testTimerAndHistoryJSONAreByteCanonicalAtEveryLayer() throws {
        let timerID = try XCTUnwrap(UUID(uuidString: "00000000-0000-4000-8000-000000000001"))
        let occurrenceID = try XCTUnwrap(UUID(uuidString: "00000000-0000-4000-8000-000000000002"))
        let timer = try countdown(
            id: timerID,
            occurrenceID: occurrenceID,
            recurrence: .selectedWeekdays(weekdays: [6, 2, 4], hour: 9, minute: 30)
        )
        let history = try HistoryEntry(
            id: try XCTUnwrap(UUID(uuidString: "00000000-0000-4000-8000-000000000003")),
            timerID: timerID,
            occurrenceID: occurrenceID,
            title: "Focus",
            kind: .countdown,
            endedAt: completed,
            elapsedSeconds: 60,
            completionReason: .finished
        )

        let timerFirst = try TimerPayloadCodec.encodeTimer(timer)
        let timerSecond = try TimerPayloadCodec.encodeTimer(timer)
        let historyFirst = try TimerPayloadCodec.encodeHistory(history)
        let historySecond = try TimerPayloadCodec.encodeHistory(history)

        XCTAssertEqual(timerFirst, timerSecond)
        XCTAssertEqual(historyFirst, historySecond)
        XCTAssertEqual((try JSONSerialization.jsonObject(with: timerFirst) as? [String: Any])?["version"] as? Int, 2)
        XCTAssertEqual((try JSONSerialization.jsonObject(with: historyFirst) as? [String: Any])?["version"] as? Int, 2)
        XCTAssertEqual(String(data: timerFirst, encoding: .utf8)?.prefix(12), "{\"payload\":\"")
        XCTAssertEqual(String(data: historyFirst, encoding: .utf8)?.prefix(12), "{\"payload\":\"")
        XCTAssertEqual(
            String(data: try envelopePayload(timerFirst), encoding: .utf8),
            "{\"accumulatedPause\":0,\"alertVolume\":1,\"createdAt\":978308200000,\"details\":\"\",\"duration\":60,\"id\":\"00000000-0000-4000-8000-000000000001\",\"kind\":\"countdown\",\"occurrenceID\":\"00000000-0000-4000-8000-000000000002\",\"recurrence\":{\"selectedWeekdays\":{\"hour\":9,\"minute\":30,\"weekdays\":[2,4,6]}},\"remaining\":60,\"state\":\"idle\",\"tags\":[],\"title\":\"Focus\"}"
        )
        XCTAssertEqual(
            String(data: try envelopePayload(historyFirst), encoding: .utf8),
            "{\"completionReason\":\"finished\",\"details\":\"\",\"elapsedSeconds\":60,\"endedAt\":978308300000,\"id\":\"00000000-0000-4000-8000-000000000003\",\"kind\":\"countdown\",\"occurrenceID\":\"00000000-0000-4000-8000-000000000002\",\"tags\":[],\"timerID\":\"00000000-0000-4000-8000-000000000001\",\"title\":\"Focus\"}"
        )
    }

    func testVersionOneTimerAndHistoryPayloadsRemainReadable() throws {
        let timer = try countdown()
        let history = try HistoryEntry(
            timerID: timer.id,
            occurrenceID: timer.occurrenceID,
            title: timer.title,
            kind: timer.kind,
            endedAt: completed,
            elapsedSeconds: 60,
            completionReason: .finished
        )

        let legacyTimer = try legacyEnvelope(payload: JSONEncoder().encode(timer))
        let legacyHistory = try legacyEnvelope(payload: JSONEncoder().encode(history))

        XCTAssertEqual(try TimerPayloadCodec.decodeTimer(legacyTimer), timer)
        XCTAssertEqual(try TimerPayloadCodec.decodeHistory(legacyHistory), history)
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

    func testSoftDeleteReencodesLegacyVersionOneTimerAsCanonicalVersionTwo() async throws {
        let fixture = try await sqliteFixture()
        defer { fixture.removeFiles() }
        let timer = try countdown()
        let legacyPayload = try legacyEnvelope(payload: JSONEncoder().encode(timer))
        try await fixture.store.perform { context in
            let record = TimerRecord(context: context)
            record.id = timer.id
            record.occurrenceID = timer.occurrenceID
            record.state = timer.state.rawValue
            record.createdAt = timer.createdAt
            record.payload = legacyPayload
            try context.save()
        }

        try await fixture.repository.softDelete(timer.id, at: completed)

        let recovered = try await fixture.repository.timer(id: timer.id)
        let payload = try await fixture.store.perform { context in
            try rawTimerPayload(id: timer.id, in: context)
        }
        XCTAssertEqual(recovered.deletedAt, completed)
        XCTAssertEqual((try JSONSerialization.jsonObject(with: payload) as? [String: Any])?["version"] as? Int, 2)
    }

    func testProtocolExistentialExposesEveryPersistenceOperation() async throws {
        let repository: any TimerRepository = ProtocolRepositoryFake()
        let timer = try countdown()

        _ = try await repository.insert(timer)
        try await repository.update(timer)
        _ = try await repository.active(limit: 1)
        _ = try await repository.activePage(limit: 1, after: nil)
        _ = try await repository.complete(timer.id, at: completed)
        try await repository.softDelete(timer.id, at: completed)
        _ = try await repository.historyCount(for: timer.id, limit: 1)
        _ = try await repository.successors(of: timer.occurrenceID, limit: 1)
        _ = try await repository.timer(id: timer.id)
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
            store: store,
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

    private func envelopePayload(_ data: Data) throws -> Data {
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(object["payload"] as? String)))
    }

    private func legacyEnvelope(payload: Data) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: ["version": 1, "payload": payload.base64EncodedString()],
            options: [.sortedKeys]
        )
    }

    private func writeLegacyV1Store(
        at url: URL,
        timer: TimerItem,
        timerPayload: Data,
        history: HistoryEntry,
        historyPayload: Data
    ) async throws {
        let legacyStore = try await CoreDataStore.legacyV1SQLite(at: url)
        try await legacyStore.perform { context in
            let timerRecord = NSEntityDescription.insertNewObject(forEntityName: "TimerRecord", into: context)
            timerRecord.setValue(timer.id, forKey: "id")
            timerRecord.setValue(timer.occurrenceID, forKey: "occurrenceID")
            timerRecord.setValue(timer.state.rawValue, forKey: "state")
            timerRecord.setValue(timer.createdAt, forKey: "createdAt")
            timerRecord.setValue(timerPayload, forKey: "payload")
            let historyRecord = NSEntityDescription.insertNewObject(forEntityName: "HistoryRecord", into: context)
            historyRecord.setValue(history.id, forKey: "id")
            historyRecord.setValue(history.timerID, forKey: "timerID")
            historyRecord.setValue(history.occurrenceID, forKey: "occurrenceID")
            historyRecord.setValue(history.endedAt, forKey: "endedAt")
            historyRecord.setValue(historyPayload, forKey: "payload")
            try context.save()
        }
        try await legacyStore.close()
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
    let store: CoreDataStore
    let directory: URL

    func removeFiles() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private func insertRawTimer(
    _ timer: TimerItem,
    predecessor: UUID?,
    in context: NSManagedObjectContext
) throws {
    let record = TimerRecord(context: context)
    record.id = timer.id
    record.occurrenceID = timer.occurrenceID
    record.predecessorOccurrenceID = predecessor
    record.state = timer.state.rawValue
    record.deadline = timer.deadline
    record.createdAt = timer.createdAt
    record.completedAt = timer.completedAt
    record.deletedAt = timer.deletedAt
    record.payload = try TimerPayloadCodec.encodeTimer(timer)
}

private func rawTimerPayload(id: UUID, in context: NSManagedObjectContext) throws -> Data {
    let request = NSFetchRequest<TimerRecord>(entityName: "TimerRecord")
    request.predicate = NSPredicate(format: "id == %@", id as NSUUID)
    request.fetchLimit = 1
    request.sortDescriptors = [NSSortDescriptor(key: "id", ascending: true)]
    return try XCTUnwrap(context.fetch(request).first?.payload)
}

private actor ProtocolRepositoryFake: TimerRepository {
    func insert(_ timer: TimerItem) async throws -> TimerItem { timer }

    func update(_ timer: TimerItem) async throws {}

    func active(limit: Int) async throws -> [TimerItem] { [] }

    func complete(_ id: UUID, at date: Date) async throws -> CompletionOutcome {
        let created = Date(timeIntervalSinceReferenceDate: 0)
        var timer = try TimerItem.stopwatch(title: "Complete", createdAt: created)
        try timer.start(at: created)
        return try RecurrenceService().complete(timer, at: date)
    }

    func softDelete(_ id: UUID, at date: Date) async throws {}

    func activePage(limit: Int, after cursor: TimerPageCursor?) async throws -> TimerPage {
        TimerPage(timers: [], nextCursor: nil)
    }

    func historyCount(for timerID: UUID, limit: Int) async throws -> Int { 0 }

    func successors(of occurrenceID: UUID, limit: Int) async throws -> [TimerItem] { [] }

    func timer(id: UUID) async throws -> TimerItem {
        try TimerItem.countdown(title: "Recovered", duration: 1, createdAt: .now)
    }
}
