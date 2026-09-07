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

    func testPresetsDeduplicateAndSurviveSQLiteRelaunch() async throws {
        let fixture = try await sqliteFixture()
        defer { fixture.removeFiles() }
        let presets = PresetCoreDataRepository(store: fixture.store)
        let first = try await presets.record(command: "  Focus 25m ", tags: ["Work", " work "], at: created)
        let second = try await presets.record(command: "focus 25m", tags: ["WORK"], at: completed)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(second.useCount, 2)
        try await fixture.store.close()
        let reopened = try await CoreDataStore.sqlite(at: fixture.directory.appendingPathComponent("TopTimer.sqlite"))
        let recovered = try await PresetCoreDataRepository(store: reopened).suggestions(query: "work", limit: 20)
        XCTAssertEqual(recovered, [second])
    }

    func testPresetSuggestionsCapAtTwentyAndPreferNormalizedTagPrefixBeforeRecency() async throws {
        let fixture = try await sqliteFixture()
        defer { fixture.removeFiles() }
        let presets = PresetCoreDataRepository(store: fixture.store)
        for index in 0 ..< 25 {
            _ = try await presets.record(
                command: "Timer \(index)",
                tags: index == 0 ? ["WÓRK"] : ["other"],
                at: created.addingTimeInterval(TimeInterval(index))
            )
        }

        let values = try await presets.suggestions(query: "work", limit: 100)

        XCTAssertEqual(values.count, 20)
        XCTAssertEqual(values.first?.command, "Timer 0")
    }

    func testPresetCodecRejectsMalformedEnvelopeUnknownVersionAndSemanticCorruption() throws {
        let date = created
        let preset = try TimerPreset(command: "Focus", tags: ["work"], createdAt: date, lastUsed: date)
        let encoded = try PresetPayloadCodec.encode(preset)
        XCTAssertEqual(try PresetPayloadCodec.decode(encoded), preset)
        XCTAssertThrowsError(try PresetPayloadCodec.decode(Data("not json".utf8)), "malformed envelope")

        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        envelope["version"] = 99
        XCTAssertThrowsError(try PresetPayloadCodec.decode(JSONSerialization.data(withJSONObject: envelope))) { XCTAssertEqual($0 as? TimerRepositoryError, .unsupportedPayloadVersion(99)) }
        envelope["version"] = 1
        envelope["unexpected"] = true
        XCTAssertThrowsError(try PresetPayloadCodec.decode(JSONSerialization.data(withJSONObject: envelope))) { XCTAssertEqual($0 as? TimerRepositoryError, .malformedPayload) }
        envelope.removeValue(forKey: "unexpected")

        let corruptions: [(String, (inout [String: Any]) -> Void)] = [
            ("empty command", { $0["command"] = "   " }),
            ("wrong key", { $0["commandKey"] = "wrong" }),
            ("unnormalized tags", { $0["tags"] = ["Work", "work"] }),
            ("zero uses", { $0["useCount"] = 0 }),
            ("last used before creation", { $0["lastUsed"] = 0 }),
            ("delete before use", { $0["deletedAt"] = 0 }),
            ("unknown field", { $0["extra"] = true })
        ]
        let payload = try XCTUnwrap(envelope["payload"] as? String)
        for (name, mutate) in corruptions {
            var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(Data(base64Encoded: payload))) as? [String: Any])
            mutate(&raw)
            var badEnvelope = envelope
            badEnvelope["version"] = 1
            badEnvelope["payload"] = try JSONSerialization.data(withJSONObject: raw).base64EncodedString()
            XCTAssertThrowsError(try PresetPayloadCodec.decode(JSONSerialization.data(withJSONObject: badEnvelope)), name) { XCTAssertEqual($0 as? TimerRepositoryError, .malformedPayload, name) }
        }
    }

    func testPresetUpsertOverflowRollsBackRawRecord() async throws {
        let fixture = try await sqliteFixture()
        defer { fixture.removeFiles() }
        let preset = try TimerPreset(command: "Focus", tags: ["work"], useCount: UInt.max, createdAt: created, lastUsed: created)
        try await fixture.store.perform { context in
            let record = PresetRecord(context: context)
            record.id = preset.id; record.createdAt = preset.createdAt; record.deletedAt = nil; record.payload = try PresetPayloadCodec.encode(preset)
            try context.save()
        }
        let repository = PresetCoreDataRepository(store: fixture.store)
        do {
            _ = try await repository.record(command: "focus", tags: ["work"], at: completed)
            XCTFail("Expected overflow")
        } catch { XCTAssertEqual(error as? TimerRepositoryError, .presetUseCountOverflow) }
        let values = try await repository.suggestions(query: "work", limit: 20)
        XCTAssertEqual(values, [preset])
    }

    func testPresetNormalizationIsSortedAndLocaleIndependent() throws {
        let preset = try TimerPreset(command: "  İSTANBUL  ", tags: ["Zebra", "ápple", "zebra"], createdAt: created, lastUsed: created)
        XCTAssertEqual(preset.command, "İSTANBUL")
        XCTAssertEqual(preset.commandKey, TimerPreset.key("İSTANBUL"))
        XCTAssertEqual(preset.tags, ["apple", "zebra"])
    }

    func testPresetSoftDeleteAndRecoveryAreIdempotent() async throws {
        let repository = PresetCoreDataRepository(store: try await CoreDataStore.inMemory())
        let preset = try await repository.record(command: "Focus", tags: ["work"], at: created)
        try await repository.softDeletePreset(preset.id, at: completed)
        try await repository.softDeletePreset(preset.id, at: completed.addingTimeInterval(1))
        let deletedSuggestions = try await repository.suggestions(query: "", limit: 20)
        XCTAssertTrue(deletedSuggestions.isEmpty)
        try await repository.recoverPreset(preset.id)
        try await repository.recoverPreset(preset.id)
        let values = try await repository.suggestions(query: "", limit: 20)
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values.first?.id, preset.id)
    }

    func testDeletingAndCleaningHistoryNeverRemovesItsPreset() async throws {
        let store = try await CoreDataStore.inMemory()
        let timers = TimerCoreDataRepository(store: store, calendar: utcCalendar)
        let presets = PresetCoreDataRepository(store: store)
        var timer = try countdown()
        try timer.start(at: created)
        _ = try await timers.insert(timer)
        _ = try await timers.complete(timer.id, at: completed)
        let preset = try await presets.record(command: "Focus 1m", tags: ["work"], at: created)
        let historyPage = try await timers.historyPage(from: nil, through: nil, query: "", limit: 1, after: nil)
        let history = try XCTUnwrap(historyPage.entries.first)
        try await timers.softDeleteHistory(history.id, at: completed)
        let deletedPage = try await timers.historyPage(from: nil, through: nil, query: "", limit: 10, after: nil)
        XCTAssertTrue(deletedPage.entries.isEmpty)
        let purged = try await timers.purgeHistory(endedBefore: completed.addingTimeInterval(1))
        XCTAssertEqual(purged, 1)
        let suggested = try await presets.suggestions(query: "work", limit: 20)
        XCTAssertEqual(suggested, [preset])
    }

    func testPresetRankingUsesPrefixThenCountThenRecencyThenStableIdentity() async throws {
        let store = try await CoreDataStore.inMemory()
        let presets = PresetCoreDataRepository(store: store)
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let values = [
            try TimerPreset(command: "Zed", tags: ["work"], useCount: 1, createdAt: created, lastUsed: completed),
            try TimerPreset(command: "Alpha", tags: ["other"], useCount: 99, createdAt: created, lastUsed: completed),
            try TimerPreset(id: secondID, command: "Same", tags: ["work"], useCount: 3, createdAt: created, lastUsed: completed),
            try TimerPreset(id: firstID, command: "Same", tags: ["work"], useCount: 3, createdAt: created, lastUsed: completed),
            try TimerPreset(command: "Recent", tags: ["work"], useCount: 3, createdAt: created, lastUsed: completed.addingTimeInterval(1))
        ]
        try await store.perform { context in
            for preset in values { let record = PresetRecord(context: context); record.id = preset.id; record.createdAt = preset.createdAt; record.deletedAt = nil; record.payload = try PresetPayloadCodec.encode(preset) }
            try context.save()
        }
        let ranked = try await presets.suggestions(query: "wo", limit: 20)
        XCTAssertEqual(ranked.map(\.command), ["Recent", "Same", "Same", "Zed", "Alpha"])
        XCTAssertEqual(ranked[1].id, firstID)
        XCTAssertEqual(ranked[2].id, secondID)
    }

    func testInsertAcceptsOnlyIdleRootsAndFreshlyStartedRoots() async throws {
        let repository = try await repository()
        let idle = try countdown()
        var countdown = try countdown()
        try countdown.start(at: created)
        var stopwatch = try TimerItem.stopwatch(title: "Watch", createdAt: created)
        try stopwatch.start(at: created)

        let insertedIdle = try await repository.insert(idle)
        let insertedCountdown = try await repository.insert(countdown)
        let insertedStopwatch = try await repository.insert(stopwatch)
        XCTAssertEqual(insertedIdle, idle)
        XCTAssertEqual(insertedCountdown, countdown)
        XCTAssertEqual(insertedStopwatch, stopwatch)
    }

    func testInsertRejectsSnapshotsThatAreNotLegitimateCreationShapes() async throws {
        let repository = try await repository()
        var running = try countdown()
        try running.start(at: created)
        var paused = running
        try paused.pause(at: created.addingTimeInterval(10))
        var completedTimer = running
        try completedTimer.complete(at: created.addingTimeInterval(60))
        var cancelled = running
        try cancelled.cancel(at: created.addingTimeInterval(10))
        var acknowledged = completedTimer
        try acknowledged.acknowledge(at: created.addingTimeInterval(61))
        var deleted = try countdown()
        try deleted.softDelete(at: completed)
        var revisedIdle = try countdown()
        try revisedIdle.updateMetadata(title: "Revised", details: "", tags: [])
        let predecessor = try timerWithPredecessor(UUID(), occurrenceID: UUID())
        let successor = try timerWithSuccessor(UUID())

        for timer in [paused, completedTimer, cancelled, acknowledged, deleted, revisedIdle, predecessor, successor] {
            await XCTAssertThrowsErrorAsync({ _ = try await repository.insert(timer) }, matching: .invalidCreation)
        }
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

    func testCancelIsAtomicAndRetryCreatesOneCancelledHistoryEntry() async throws {
        let fixture = try await sqliteFixture()
        defer { fixture.removeFiles() }
        let repository = fixture.repository
        var timer = try countdown()
        try timer.start(at: created)
        _ = try await repository.insert(timer)

        let first = try await repository.cancel(id: timer.id, at: completed)
        let second = try await repository.cancel(id: timer.id, at: completed)

        XCTAssertEqual(first.state, .cancelled)
        XCTAssertEqual(first.revision, timer.revision + 1)
        XCTAssertEqual(second, first)
        let historyCount = try await repository.historyCount(for: timer.id)
        XCTAssertEqual(historyCount, 1)
        let history = try await history(for: timer.id, in: fixture.store)
        XCTAssertEqual(history.completionReason, .cancelled)
        XCTAssertEqual(history.endedAt, completed)
        XCTAssertEqual(history.elapsedSeconds, 60)
    }

    func testCancelWritesAccurateStopwatchHistory() async throws {
        let fixture = try await sqliteFixture()
        defer { fixture.removeFiles() }
        var timer = try TimerItem.stopwatch(title: "Watch", createdAt: created)
        try timer.start(at: created)
        _ = try await fixture.repository.insert(timer)

        _ = try await fixture.repository.cancel(id: timer.id, at: completed)

        let history = try await history(for: timer.id, in: fixture.store)
        XCTAssertEqual(history.completionReason, .cancelled)
        XCTAssertEqual(history.endedAt, completed)
        XCTAssertEqual(history.elapsedSeconds, completed.timeIntervalSince(created))
    }

    func testCancelConstraintFailureRollsBackTimerStateAndHistory() async throws {
        let fixture = try await sqliteFixture()
        defer { fixture.removeFiles() }
        var timer = try countdown()
        try timer.start(at: created)
        _ = try await fixture.repository.insert(timer)
        let conflictingHistory = try HistoryEntry(
            timerID: timer.id,
            occurrenceID: timer.occurrenceID,
            title: timer.title,
            kind: timer.kind,
            endedAt: completed,
            elapsedSeconds: 60,
            completionReason: .cancelled
        )
        try await fixture.repository.insertHistory(conflictingHistory)

        await XCTAssertThrowsErrorAsync { _ = try await fixture.repository.cancel(id: timer.id, at: self.completed) }

        let persisted = try await fixture.repository.timer(id: timer.id)
        XCTAssertEqual(persisted, timer)
        let historyCount = try await fixture.repository.historyCount(for: timer.id)
        XCTAssertEqual(historyCount, 1)
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

    func testUpdateRejectsAConcurrentSameBaseMetadataSnapshot() async throws {
        let repository = try await repository()
        let timer = try countdown()
        _ = try await repository.insert(timer)
        var first = try await repository.timer(id: timer.id)
        var second = try await repository.timer(id: timer.id)

        try first.updateMetadata(title: "First", details: "", tags: [])
        try second.updateMetadata(title: "Second", details: "", tags: [])
        try await repository.update(first)
        await XCTAssertThrowsErrorAsync({ try await repository.update(second) }, matching: .staleTimerUpdate)

        let persisted = try await repository.timer(id: timer.id)
        XCTAssertEqual(persisted, first)
    }

    func testUpdateRejectsSnapshotThatPredatesSoftDelete() async throws {
        let repository = try await repository()
        let timer = try countdown()
        _ = try await repository.insert(timer)
        var stale = try await repository.timer(id: timer.id)
        try stale.updateMetadata(title: "Stale", details: "", tags: [])

        try await repository.softDelete(timer.id, at: completed)
        await XCTAssertThrowsErrorAsync({ try await repository.update(stale) }, matching: .staleTimerUpdate)

        let persisted = try await repository.timer(id: timer.id)
        XCTAssertEqual(persisted.deletedAt, completed)
    }

    func testUpdateRejectsCraftedAcknowledgementOfAnActiveTimer() async throws {
        let repository = try await repository()
        var timer = try countdown()
        try timer.start(at: created)
        _ = try await repository.insert(timer)
        var crafted = timer
        try crafted.complete(at: created.addingTimeInterval(60))
        try crafted.acknowledge(at: created.addingTimeInterval(60))
        var craftedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(crafted)) as? [String: Any]
        )
        craftedObject["revision"] = timer.revision + 1
        crafted = try JSONDecoder().decode(TimerItem.self, from: JSONSerialization.data(withJSONObject: craftedObject))

        await XCTAssertThrowsErrorAsync({ try await repository.update(crafted) }, matching: .staleTimerUpdate)
        let persisted = try await repository.timer(id: timer.id)
        XCTAssertEqual(persisted, timer)
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
        try timer.restart(at: created.addingTimeInterval(30))
        try await repository.update(timer)
        let persisted = try await repository.timer(id: timer.id)
        XCTAssertEqual(persisted, timer)
    }

    func testSecondSuccessorForOnePredecessorIsRejectedByDatabase() async throws {
        let fixture = try await sqliteFixture()
        defer { fixture.removeFiles() }
        let predecessor = UUID()
        let first = try timerWithPredecessor(predecessor, occurrenceID: UUID())
        let second = try timerWithPredecessor(predecessor, occurrenceID: UUID())
        try await fixture.store.perform { context in
            try insertRawTimer(first, predecessor: predecessor, in: context)
            try context.save()
        }

        await XCTAssertThrowsErrorAsync {
            try await fixture.store.perform { context in
                try insertRawTimer(second, predecessor: predecessor, in: context)
                try context.save()
            }
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
        let sourceOccurrenceID = source.occurrenceID
        try await fixture.store.perform { context in
            try insertRawTimer(existingSuccessor, predecessor: sourceOccurrenceID, in: context)
            try context.save()
        }

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

    func testActivePageHasNoCursorWhenExactlyFull() async throws {
        let repository = try await repository()
        for offset in 0..<200 {
            let timer = try TimerItem.countdown(
                title: "\(offset)",
                duration: 60,
                createdAt: created.addingTimeInterval(TimeInterval(offset))
            )
            _ = try await repository.insert(timer)
        }

        let page = try await repository.activePage(limit: 200)
        XCTAssertEqual(page.timers.count, 200)
        XCTAssertNil(page.nextCursor)
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

        var source = try countdown(recurrence: .interval(seconds: 300))
        try source.start(at: created)
        _ = try await repository.insert(source)
        _ = try await repository.complete(source.id, at: created.addingTimeInterval(60))
        let predecessor = source.occurrenceID
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
            "{\"accumulatedPause\":0,\"alertVolume\":1,\"createdAt\":978308200000,\"details\":\"\",\"duration\":60,\"id\":\"00000000-0000-4000-8000-000000000001\",\"kind\":\"countdown\",\"occurrenceID\":\"00000000-0000-4000-8000-000000000002\",\"recurrence\":{\"selectedWeekdays\":{\"hour\":9,\"minute\":30,\"weekdays\":[2,4,6]}},\"remaining\":60,\"revision\":0,\"state\":\"idle\",\"tags\":[],\"title\":\"Focus\"}"
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

        let legacyTimer = try legacyEnvelope(payload: try payloadWithoutRevision(timer))
        let legacyHistory = try legacyEnvelope(payload: JSONEncoder().encode(history))

        XCTAssertEqual(try TimerPayloadCodec.decodeTimer(legacyTimer), timer)
        XCTAssertEqual(try TimerPayloadCodec.decodeHistory(legacyHistory), history)
    }

    func testVersionTwoTimerPayloadWithoutRevisionRemainsReadable() throws {
        let timer = try countdown()
        let encoded = try TimerPayloadCodec.encodeTimer(timer)
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let payload = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(envelope["payload"] as? String)))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        object.removeValue(forKey: "revision")
        envelope["payload"] = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).base64EncodedString()
        let legacyVersionTwo = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])

        XCTAssertEqual(try TimerPayloadCodec.decodeTimer(legacyVersionTwo), timer)
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

    func testSoftDeleteRetryPreservesTheOriginalTombstoneAndRevision() async throws {
        let repository = try await repository()
        let timer = try countdown()
        _ = try await repository.insert(timer)

        try await repository.softDelete(timer.id, at: completed)
        let first = try await repository.timer(id: timer.id)
        try await repository.softDelete(timer.id, at: completed.addingTimeInterval(10))
        let second = try await repository.timer(id: timer.id)

        XCTAssertEqual(second, first)
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
        _ = try await repository.cancel(id: timer.id, at: completed)
        try await repository.softDelete(timer.id, at: completed)
        _ = try await repository.historyPage(from: nil, through: nil, query: "", limit: 1, after: nil)
        try await repository.updateHistory(try historyEntry(id: "00000000-0000-0000-0000-000000000099", title: "History"))
        try await repository.softDeleteHistory(timer.id, at: completed)
        try await repository.recoverHistory(timer.id)
        _ = try await repository.purgeHistory(endedBefore: completed)
        _ = try await repository.historyCount(for: timer.id, limit: 1)
        _ = try await repository.successors(of: timer.occurrenceID, limit: 1)
        _ = try await repository.timer(id: timer.id)
    }

    func testHistoryPageUsesDateBoundsSearchAndDescendingCursorTies() async throws {
        let repository = try await repository()
        let ended = completed
        let first = try historyEntry(id: "00000000-0000-0000-0000-000000000001", title: "Other", endedAt: ended)
        let second = try historyEntry(id: "00000000-0000-0000-0000-000000000002", title: "Focus", details: "CLIENT notes", endedAt: ended)
        let third = try historyEntry(id: "00000000-0000-0000-0000-000000000003", title: "Focus", tags: ["client-work"], endedAt: ended)
        let outside = try historyEntry(id: "00000000-0000-0000-0000-000000000004", title: "CLIENT old", endedAt: created)
        for entry in [first, second, third, outside] {
            try await repository.insertHistory(entry)
        }

        let firstPage = try await repository.historyPage(
            from: ended,
            through: ended,
            query: "client",
            limit: 2,
            after: nil
        )
        XCTAssertEqual(firstPage.entries.map(\.id), [third.id, second.id])
        XCTAssertEqual(firstPage.nextCursor, HistoryPageCursor(endedAt: ended, id: second.id))

        let secondPage = try await repository.historyPage(
            from: ended,
            through: ended,
            query: "client",
            limit: 2,
            after: firstPage.nextCursor
        )
        XCTAssertEqual(secondPage.entries, [])
        XCTAssertNil(secondPage.nextCursor)
    }

    func testHistoryPageClampsLimitsAndSearchesDecodedTagValuesCaseInsensitively() async throws {
        let repository = try await repository()
        let first = try historyEntry(id: "00000000-0000-0000-0000-000000000001", title: "First", tags: ["CLIENT"])
        let second = try historyEntry(id: "00000000-0000-0000-0000-000000000002", title: "Second", tags: ["client"])
        try await repository.insertHistory(first)
        try await repository.insertHistory(second)

        let page = try await repository.historyPage(from: nil, through: nil, query: "ClIeNt", limit: 0, after: nil)

        XCTAssertEqual(page.entries.map(\.id), [second.id])
        XCTAssertEqual(page.nextCursor, HistoryPageCursor(endedAt: second.endedAt, id: second.id))
    }

    func testHistoryPageScansPastNewerNonmatchingRows() async throws {
        let repository = try await repository()
        for offset in 1...201 {
            let entry = try historyEntry(
                id: String(format: "00000000-0000-0000-0000-%012d", offset),
                title: "unrelated",
                endedAt: completed.addingTimeInterval(Double(201 - offset + 1))
            )
            try await repository.insertHistory(entry)
        }
        let match = try historyEntry(
            id: "00000000-0000-0000-0000-000000000999",
            title: "needle",
            endedAt: completed
        )
        try await repository.insertHistory(match)

        let page = try await repository.historyPage(from: nil, through: nil, query: "needle", limit: 1, after: nil)

        XCTAssertEqual(page.entries.map(\.id), [match.id])
    }

    func testHistoryMetadataEditPreservesIdentityAndSystemTimestamps() async throws {
        let repository = try await repository()
        let original = try historyEntry(id: "00000000-0000-0000-0000-000000000001", title: "Original")
        try await repository.insertHistory(original)
        var edited = original
        try edited.updateMetadata(title: "Edited", details: "Details", tags: ["work"])

        try await repository.updateHistory(edited)
        let savedPage = try await repository.historyPage(from: nil, through: nil, query: "", limit: 1, after: nil)
        let saved = try XCTUnwrap(savedPage.entries.first)
        XCTAssertEqual(saved, edited)

        let changedTimestamp = try HistoryEntry(
            id: edited.id,
            timerID: edited.timerID,
            occurrenceID: edited.occurrenceID,
            title: edited.title,
            details: edited.details,
            tags: edited.tags,
            kind: edited.kind,
            startedAt: edited.startedAt,
            endedAt: edited.endedAt.addingTimeInterval(1),
            elapsedSeconds: edited.elapsedSeconds,
            completionReason: edited.completionReason
        )
        await XCTAssertThrowsErrorAsync({ try await repository.updateHistory(changedTimestamp) }, matching: .staleHistoryUpdate)
        let unchangedPage = try await repository.historyPage(from: nil, through: nil, query: "", limit: 1, after: nil)
        XCTAssertEqual(try XCTUnwrap(unchangedPage.entries.first), edited)
    }

    func testHistorySoftDeleteRecoveryAndRetentionCleanupRespectCutoff() async throws {
        let repository = try await repository()
        let old = try historyEntry(id: "00000000-0000-0000-0000-000000000001", title: "Old", endedAt: created)
        let cutoff = completed
        let atCutoff = try historyEntry(id: "00000000-0000-0000-0000-000000000002", title: "At cutoff", endedAt: cutoff)
        try await repository.insertHistory(old)
        try await repository.insertHistory(atCutoff)

        try await repository.softDeleteHistory(atCutoff.id, at: completed)
        let deletedPage = try await repository.historyPage(from: nil, through: nil, query: "", limit: 10, after: nil)
        XCTAssertEqual(deletedPage.entries, [old])
        try await repository.recoverHistory(atCutoff.id)
        let recoveredPage = try await repository.historyPage(from: nil, through: nil, query: "", limit: 10, after: nil)
        XCTAssertEqual(recoveredPage.entries.map(\.id), [atCutoff.id, old.id])

        let purgedCount = try await repository.purgeHistory(endedBefore: cutoff)
        XCTAssertEqual(purgedCount, 1)
        let remainingPage = try await repository.historyPage(from: nil, through: nil, query: "", limit: 10, after: nil)
        XCTAssertEqual(remainingPage.entries, [atCutoff])
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

    private func historyEntry(
        id: String,
        title: String,
        details: String = "",
        tags: [String] = [],
        endedAt: Date? = nil
    ) throws -> HistoryEntry {
        let value = try XCTUnwrap(UUID(uuidString: id))
        return try HistoryEntry(
            id: value,
            timerID: UUID(),
            occurrenceID: UUID(),
            title: title,
            details: details,
            tags: tags,
            kind: .countdown,
            startedAt: created,
            endedAt: endedAt ?? completed,
            elapsedSeconds: 60,
            completionReason: .finished
        )
    }

    private func timerWithPredecessor(_ predecessor: UUID, occurrenceID: UUID) throws -> TimerItem {
        let timer = try countdown(occurrenceID: occurrenceID)
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(timer)) as? [String: Any])
        object["predecessorOccurrenceID"] = predecessor.uuidString
        return try JSONDecoder().decode(TimerItem.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func timerWithSuccessor(_ successor: UUID) throws -> TimerItem {
        let timer = try countdown()
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(timer)) as? [String: Any])
        object["successorID"] = successor.uuidString
        return try JSONDecoder().decode(TimerItem.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func envelopePayload(_ data: Data) throws -> Data {
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(object["payload"] as? String)))
    }

    private func history(for timerID: UUID, in store: CoreDataStore) async throws -> HistoryEntry {
        try await store.perform { context in
            let request = NSFetchRequest<HistoryRecord>(entityName: "HistoryRecord")
            request.predicate = NSPredicate(format: "timerID == %@", timerID as NSUUID)
            request.sortDescriptors = [NSSortDescriptor(key: "endedAt", ascending: true), NSSortDescriptor(key: "id", ascending: true)]
            request.fetchLimit = 1
            return try TimerPayloadCodec.decodeHistory(try XCTUnwrap(context.fetch(request).first?.payload))
        }
    }

    private func legacyEnvelope(payload: Data) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: ["version": 1, "payload": payload.base64EncodedString()],
            options: [.sortedKeys]
        )
    }

    private func payloadWithoutRevision(_ timer: TimerItem) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(timer)) as? [String: Any])
        object.removeValue(forKey: "revision")
        return try JSONSerialization.data(withJSONObject: object)
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

    func cancel(id: UUID, at date: Date) async throws -> TimerItem {
        try TimerItem.countdown(title: "Cancelled", duration: 1, createdAt: date)
    }

    func softDelete(_ id: UUID, at date: Date) async throws {}

    func historyPage(
        from: Date?,
        through: Date?,
        query: String,
        limit: Int,
        after cursor: HistoryPageCursor?
    ) async throws -> HistoryPage {
        HistoryPage(entries: [], nextCursor: nil)
    }

    func updateHistory(_ history: HistoryEntry) async throws {}

    func softDeleteHistory(_ id: UUID, at date: Date) async throws {}

    func recoverHistory(_ id: UUID) async throws {}

    func purgeHistory(endedBefore cutoff: Date) async throws -> Int { 0 }

    func activePage(limit: Int, after cursor: TimerPageCursor?) async throws -> TimerPage {
        TimerPage(timers: [], nextCursor: nil)
    }

    func historyCount(for timerID: UUID, limit: Int) async throws -> Int { 0 }

    func successors(of occurrenceID: UUID, limit: Int) async throws -> [TimerItem] { [] }

    func timer(id: UUID) async throws -> TimerItem {
        try TimerItem.countdown(title: "Recovered", duration: 1, createdAt: .now)
    }
}
