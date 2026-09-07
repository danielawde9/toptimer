import Combine
import XCTest
@testable import TopTimerApp
import TopTimerDomain
import TopTimerPersistence
import TopTimerSystem

@MainActor
final class AppStateTests: XCTestCase {
    func testObservableStatePublishesTimerErrorAndSuggestionMutationsOnMainActor() async {
        let state = AppState(repository: RecordingRepository(), notifications: RecordingNotifications(), presets: RecordingPresets())
        var publicationCount = 0
        let subscription = state.objectWillChange.sink { _ in
            XCTAssertTrue(Thread.isMainThread)
            publicationCount += 1
        }
        defer { subscription.cancel() }

        await state.create(command: "not a timer command")
        XCTAssertNotNil(state.inlineError)
        await state.create(command: "")
        await state.refreshSuggestions(query: "")

        XCTAssertEqual(state.activeTimers.count, 1)
        XCTAssertLessThanOrEqual(state.suggestions.count, 20)
        XCTAssertGreaterThanOrEqual(publicationCount, 3)
    }

    func testBlankCommandStartsAndPublishesStopwatchAfterPersistence() async throws {
        let repository = RecordingRepository()
        let notifications = RecordingNotifications()
        let now = Date(timeIntervalSince1970: 1_000)
        let state = AppState(
            repository: repository,
            notifications: notifications,
            now: { now },
            parser: { TimerParser(now: $0) }
        )

        await state.create(command: "")

        let repositoryOperations = await repository.recordedOperations()
        let notificationOperations = await notifications.recordedOperations()
        XCTAssertEqual(repositoryOperations, ["insert", "publish"])
        XCTAssertEqual(notificationOperations, [])
        XCTAssertEqual(state.activeTimers.count, 1)
        XCTAssertEqual(state.activeTimers[0].kind, .stopwatch)
        XCTAssertEqual(state.activeTimers[0].state, .running)
        XCTAssertNil(state.inlineError)
    }

    func testSuccessfulCreateRecordsAndPublishesRankedPresetSuggestions() async throws {
        let repository = RecordingRepository()
        let presets = RecordingPresets()
        let state = AppState(repository: repository, notifications: RecordingNotifications(), presets: presets, now: { Date(timeIntervalSince1970: 1_000) })
        await state.create(command: "5m Focus #work")
        let count = await presets.recordCount()
        XCTAssertEqual(count, 1)
        XCTAssertEqual(state.suggestions, ["5m Focus #work"])
        await state.refreshSuggestions(query: "work")
        XCTAssertEqual(state.suggestions.count, 1)
    }

    func testCreatePersistenceFailureDoesNotSchedulePublishOrRecordPreset() async {
        let repository = RecordingRepository(failInsert: true)
        let notifications = RecordingNotifications()
        let presets = RecordingPresets()
        let state = AppState(repository: repository, notifications: notifications, presets: presets)

        await state.create(command: "5m Focus #work")

        XCTAssertTrue(state.activeTimers.isEmpty)
        XCTAssertNotNil(state.inlineError)
        let notificationOperations = await notifications.recordedOperations()
        let presetCount = await presets.recordCount()
        XCTAssertEqual(notificationOperations, [])
        XCTAssertEqual(presetCount, 0)
    }

    func testCountdownCreationPersistsSchedulesThenPublishes() async {
        let repository = RecordingRepository()
        let notifications = RecordingNotifications()
        let state = AppState(repository: repository, notifications: notifications, now: { Date(timeIntervalSince1970: 1_000) })

        await state.create(command: "5m Focus")

        let repositoryOperations = await repository.recordedOperations()
        let notificationOperations = await notifications.recordedOperations()
        XCTAssertEqual(repositoryOperations, ["insert", "publish"])
        XCTAssertEqual(notificationOperations, ["schedule"])
        XCTAssertEqual(state.activeTimers.map(\.title), ["Focus"])
    }

    func testCountdownCreationOrdersPersistenceEffectAndPublishInOneSharedLog() async {
        let recorder = OperationRecorder()
        let repository = RecordingRepository(recorder: recorder)
        let notifications = RecordingNotifications(recorder: recorder)
        let state = AppState(repository: repository, notifications: notifications, now: { Date(timeIntervalSince1970: 1_000) })
        await state.create(command: "5m Focus")
        let operations = await recorder.operations()
        XCTAssertEqual(operations, ["persist", "schedule", "publish"])
    }

    func testTransitionClassesUseOneSharedCrossBoundaryOrderLog() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let cases: [(TimerItem, (AppState, UUID) async -> Bool, [String])] = [
            (try runningCountdown(at: now), { await $0.pause($1) }, ["timer", "update", "cancelNotification", "publish"]),
            (try idleCountdown(at: now), { await $0.start($1) }, ["timer", "update", "schedule", "publish"]),
            (try runningCountdown(at: now), { await $0.edit($1, title: "Edited", details: "", tags: []) }, ["timer", "update", "cancelNotification", "schedule", "publish"]),
            (try pausedCountdown(at: now), { await $0.resume($1) }, ["timer", "update", "schedule", "publish"]),
            (try runningCountdown(at: now), { await $0.restart($1) }, ["timer", "update", "schedule", "publish"]),
            (try completedCountdown(at: now.addingTimeInterval(-300)), { await $0.acknowledge($1) }, ["timer", "update", "cancelNotification", "publish"]),
            (try runningCountdown(at: now), { await $0.softDelete($1) }, ["softDelete", "cancelNotification", "publish"]),
            (try runningCountdown(at: now), { await $0.cancel($1) }, ["cancel", "cancelNotification", "publish"])
        ]
        for (timer, action, expected) in cases {
            let recorder = OperationRecorder(); let repository = RecordingRepository(recorder: recorder); await repository.seed(timer)
            let state = AppState(repository: repository, notifications: RecordingNotifications(recorder: recorder), now: { now })
            let succeeded = await action(state, timer.id)
            XCTAssertTrue(succeeded)
            let operations = await recorder.operations()
            XCTAssertEqual(operations, expected)
        }
        var recurring = try TimerItem.countdown(title: "Recurring", duration: 60, recurrence: .interval(seconds: 300), createdAt: now); try recurring.start(at: now)
        let completeLog = OperationRecorder(); let completeRepository = RecordingRepository(recorder: completeLog); await completeRepository.seed(recurring)
        let completeState = AppState(repository: completeRepository, notifications: RecordingNotifications(recorder: completeLog), now: { now.addingTimeInterval(60) })
        let completed = await completeState.complete(recurring.id)
        XCTAssertTrue(completed)
        let completeOperations = await completeLog.operations()
        XCTAssertEqual(completeOperations, ["complete", "schedule", "publish"])

        let recoveryLog = OperationRecorder(); let recoveryState = AppState(repository: RecordingRepository(recorder: recoveryLog), notifications: RecordingNotifications(recorder: recoveryLog))
        let recovered = await recoveryState.recoverHistory(UUID())
        XCTAssertTrue(recovered)
        let recoveryOperations = await recoveryLog.operations()
        XCTAssertEqual(recoveryOperations, ["recover", "publish"])
    }

    func testCreationStillPublishesPersistedTimerWhenSchedulingFails() async {
        let repository = RecordingRepository()
        let notifications = RecordingNotifications(failSchedule: true)
        let state = AppState(repository: repository, notifications: notifications, now: { Date(timeIntervalSince1970: 1_000) })

        await state.create(command: "5m Focus")

        let repositoryOperations = await repository.recordedOperations()
        let notificationOperations = await notifications.recordedOperations()
        XCTAssertEqual(repositoryOperations, ["insert", "publish"])
        XCTAssertEqual(notificationOperations, ["schedule"])
        XCTAssertEqual(state.activeTimers.count, 1)
        XCTAssertEqual(state.inlineError, "Timer saved, but notification scheduling failed.")
    }

    func testFailedTransitionLeavesPublishedTimersAndNotificationsUntouched() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let timer = try runningCountdown(at: now)
        let cases: [(String, (AppState, UUID) async -> Bool)] = [
            ("update", { await $0.pause($1) }),
            ("cancel", { await $0.cancel($1) }),
            ("softDelete", { await $0.softDelete($1) }),
            ("complete", { await $0.complete($1) })
        ]
        for (operation, transition) in cases {
            let repository = RecordingRepository(failing: [operation])
            await repository.seed(timer)
            let notifications = RecordingNotifications()
            let state = AppState(repository: repository, notifications: notifications, now: { now })
            await state.load()
            let before = state.activeTimers
            await repository.resetOperations()

            let succeeded = await transition(state, timer.id)
            let notificationOperations = await notifications.recordedOperations()
            let repositoryOperations = await repository.recordedOperations()
            XCTAssertFalse(succeeded, operation)
            XCTAssertEqual(state.activeTimers, before, operation)
            XCTAssertEqual(notificationOperations, [], operation)
            XCTAssertFalse(repositoryOperations.contains("publish"), operation)
        }
    }

    func testSuccessfulTransitionsPersistApplyNotificationEffectThenPublish() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let cases: [(String, Date, () throws -> TimerItem, String, (AppState, UUID) async -> Bool, String)] = [
            ("pause", now, { try self.runningCountdown(at: now) }, "update", { await $0.pause($1) }, "cancel"),
            ("start", now, { try self.idleCountdown(at: now) }, "update", { await $0.start($1) }, "schedule"),
            ("edit", now, { try self.runningCountdown(at: now) }, "update", { await $0.edit($1, title: "Edited", details: "Details", tags: ["work"]) }, "cancel"),
            ("resume", now, { try self.pausedCountdown(at: now) }, "update", { await $0.resume($1) }, "schedule"),
            ("restart", now, { try self.runningCountdown(at: now) }, "update", { await $0.restart($1) }, "schedule"),
            ("acknowledge", now.addingTimeInterval(300), { try self.completedCountdown(at: now) }, "update", { await $0.acknowledge($1) }, "cancel"),
            ("cancel", now, { try self.runningCountdown(at: now) }, "cancel", { await $0.cancel($1) }, "cancel"),
            ("softDelete", now, { try self.runningCountdown(at: now) }, "softDelete", { await $0.softDelete($1) }, "cancel"),
            ("complete", now.addingTimeInterval(300), { try self.runningCountdown(at: now) }, "complete", { await $0.complete($1) }, "")
        ]
        for (_, transitionDate, makeTimer, operation, transition, notification) in cases {
            let repository = RecordingRepository()
            let timer = try makeTimer()
            await repository.seed(timer)
            let notifications = RecordingNotifications()
            let state = AppState(repository: repository, notifications: notifications, now: { transitionDate })
            await repository.resetOperations()

            let succeeded = await transition(state, timer.id)
            let repositoryOperations = await repository.recordedOperations()
            let notificationOperations = await notifications.recordedOperations()
            XCTAssertTrue(succeeded)
            let expected = ["cancel", "softDelete", "complete"].contains(operation) ? [operation, "publish"] : ["timer", operation, "publish"]
            XCTAssertEqual(repositoryOperations, expected)
            let expectedNotifications = operation == "update" && notification == "cancel" && !state.activeTimers.isEmpty && state.activeTimers[0].kind == .countdown && state.activeTimers[0].state == .running ? ["cancel", "schedule"] : (notification.isEmpty ? [] : [notification])
            XCTAssertEqual(notificationOperations, expectedNotifications)
        }
    }

    private func runningCountdown(at date: Date) throws -> TimerItem {
        var timer = try TimerItem.countdown(title: "Focus", duration: 300, createdAt: date)
        try timer.start(at: date)
        return timer
    }

    private func pausedCountdown(at date: Date) throws -> TimerItem {
        var timer = try runningCountdown(at: date)
        try timer.pause(at: date)
        return timer
    }

    private func idleCountdown(at date: Date) throws -> TimerItem {
        try TimerItem.countdown(title: "Focus", duration: 300, createdAt: date)
    }

    private func completedCountdown(at date: Date) throws -> TimerItem {
        let timer = try runningCountdown(at: date)
        return try RecurrenceService().complete(timer, at: date.addingTimeInterval(300)).completed
    }

    func testNotificationRepeatUsesOriginalFieldsAndDurationButDropsRecurrence() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        var source = try TimerItem.countdown(title: "Focus", duration: 600, details: "Deep work", tags: ["work"], recurrence: .daily(hour: 9, minute: 0), createdAt: now)
        try source.start(at: now)
        let repository = RecordingRepository()
        await repository.seed(source)
        let notifications = RecordingNotifications()
        let state = AppState(repository: repository, notifications: notifications, now: { now })

        await state.handle(notificationAction: .repeatTimer(source.id, duration: 1))

        let created = try XCTUnwrap(state.activeTimers.first { $0.id != source.id })
        XCTAssertEqual(created.title, source.title)
        XCTAssertEqual(created.details, source.details)
        XCTAssertEqual(created.tags, source.tags)
        XCTAssertEqual(created.duration, source.duration)
        XCTAssertEqual(created.recurrence, RecurrenceRule.none)
        let notificationOperations = await notifications.recordedOperations()
        XCTAssertEqual(notificationOperations, ["schedule"])
    }

    func testNotificationSnoozeUsesClampedPreferenceAndInvalidPayloadHasNoEffects() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let source = try runningCountdown(at: now)
        let repository = RecordingRepository()
        await repository.seed(source)
        let notifications = RecordingNotifications()
        let state = AppState(repository: repository, notifications: notifications, now: { now })
        state.preferences = AppPreferences(snoozeSeconds: 5)

        await state.handle(notificationAction: .snooze(source.id, seconds: 999))

        let snoozed = try XCTUnwrap(state.activeTimers.first { $0.id != source.id })
        XCTAssertEqual(snoozed.duration, 60)
        await repository.resetOperations()
        let notificationCount = await notifications.recordedOperations().count
        let before = state.activeTimers
        await state.handle(notificationAction: .invalidPayload)
        let repositoryOperations = await repository.recordedOperations()
        let finalNotificationCount = await notifications.recordedOperations().count
        XCTAssertEqual(repositoryOperations, [])
        XCTAssertEqual(finalNotificationCount, notificationCount)
        XCTAssertEqual(state.activeTimers, before)
    }

    func testRefreshUsesItsSuppliedTickRatherThanTheInjectedCreationClock() async throws {
        let repository = RecordingRepository()
        let creation = Date(timeIntervalSince1970: 1_000)
        let state = AppState(repository: repository, notifications: RecordingNotifications(), now: { creation })

        await state.create(command: "1m Focus")
        await state.refresh(now: creation.addingTimeInterval(60))

        XCTAssertTrue(state.activeTimers.isEmpty)
    }

    func testRefreshIsDueOnlyBoundedAndIdempotentForTheSameTick() async throws {
        let created = Date(timeIntervalSince1970: 1_000)
        let due = try runningCountdown(at: created)
        var later = try TimerItem.countdown(title: "Later", duration: 600, createdAt: created)
        try later.start(at: created)
        let repository = RecordingRepository()
        await repository.seed(due)
        await repository.seed(later)
        let state = AppState(repository: repository, notifications: RecordingNotifications(), now: { created })

        await state.refresh(now: created.addingTimeInterval(300))
        let firstOperations = await repository.recordedOperations()
        await repository.resetOperations()
        await state.refresh(now: created.addingTimeInterval(300))
        let repeatedOperations = await repository.recordedOperations()
        let limits = await repository.activeLimits()

        XCTAssertEqual(firstOperations.filter { $0 == "complete" }.count, 1)
        XCTAssertEqual(state.activeTimers.map(\.title), ["Later"])
        XCTAssertFalse(repeatedOperations.contains("complete"))
        XCTAssertEqual(limits.max(), 100)
    }

    func testOverlappingRefreshesRunOnlyOneRepositoryScan() async throws {
        let repository = RecordingRepository()
        await repository.suspendNextActive()
        let state = AppState(repository: repository, notifications: RecordingNotifications())
        let first = Task { await state.refresh(now: Date(timeIntervalSince1970: 1_000)) }
        await repository.waitForActiveStart()
        await state.refresh(now: Date(timeIntervalSince1970: 1_000))
        await repository.releaseActive()
        await first.value
        let operations = await repository.recordedOperations()
        XCTAssertEqual(operations.filter { $0 == "due" }.count, 1, "only one due scan overlaps")
        XCTAssertEqual(operations.filter { $0 == "publish" }.count, 1, "only the winning refresh publishes")
    }

    func testRecurringDueRefreshPersistsAndSchedulesOneSuccessorIdempotently() async throws {
        let created = Date(timeIntervalSince1970: 1_000)
        var source = try TimerItem.countdown(title: "Focus", duration: 60, recurrence: .interval(seconds: 300), createdAt: created)
        try source.start(at: created)
        let repository = RecordingRepository()
        await repository.seed(source)
        let notifications = RecordingNotifications()
        let state = AppState(repository: repository, notifications: notifications)
        let due = created.addingTimeInterval(60)
        await state.refresh(now: due)
        await state.refresh(now: due)
        let successors = try await repository.successors(of: source.occurrenceID, limit: 10)
        let scheduled = await notifications.recordedOperations()
        XCTAssertEqual(successors.count, 1)
        XCTAssertEqual(scheduled.filter { $0 == "schedule" }.count, 1)
    }

    func testPublishedEditorHistoryAndPreferenceFieldsHaveSafeBounds() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let timer = try runningCountdown(at: now)
        let repository = RecordingRepository()
        await repository.seed(timer)
        let state = AppState(repository: repository, notifications: RecordingNotifications())
        await state.load()
        await state.selectEditor(timer.id)
        state.preferences.snoozeSeconds = -1

        XCTAssertEqual(state.selectedEditorTimer?.id, timer.id)
        XCTAssertEqual(state.historyPage.entries, [])
        XCTAssertEqual(state.preferences.snoozeSeconds, 60)
    }

    func testSQLiteRelaunchRecoversActiveTimerHistoryAndPresetSuggestions() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("TopTimer.sqlite")
        let created = Date(timeIntervalSince1970: 1_000)

        let firstStore = try await CoreDataStore.sqlite(at: url)
        let firstRepository = TimerCoreDataRepository(store: firstStore)
        let first = AppState(
            repository: firstRepository,
            notifications: RecordingNotifications(),
            presets: PresetCoreDataRepository(store: firstStore),
            now: { created }
        )
        await first.create(command: "5m Focus #work")
        await first.create(command: "1m Done #work")
        XCTAssertEqual(first.activeTimers.count, 2)
        let completedID = try XCTUnwrap(first.activeTimers.first { $0.title == "Done" }?.id)
        await first.refresh(now: created.addingTimeInterval(60))
        XCTAssertFalse(first.activeTimers.contains { $0.id == completedID })
        try await firstStore.close()

        let secondStore = try await CoreDataStore.sqlite(at: url)
        defer { Task { try? await secondStore.close() } }
        let secondRepository = TimerCoreDataRepository(store: secondStore)
        let second = AppState(
            repository: secondRepository,
            notifications: RecordingNotifications(),
            presets: PresetCoreDataRepository(store: secondStore),
            now: { created }
        )
        await second.load()

        XCTAssertEqual(second.activeTimers.map(\.title), ["Focus"])
        XCTAssertEqual(second.historyPage.entries.count, 1)
        XCTAssertEqual(second.suggestions, ["1m Done #work", "5m Focus #work"])
        let historyCount = try await secondRepository.historyCount(for: completedID, limit: 100)
        XCTAssertEqual(historyCount, 1)
    }
}

actor RecordingRepository: TimerRepository {
    var operations: [String] = []
    var requestedActiveLimits: [Int] = []
    private var timers: [UUID: TimerItem] = [:]
    private var failures: Set<String>
    private var activeDelay: Bool = false
    private var activeContinuation: CheckedContinuation<Void, Never>?
    private var activeStartedContinuation: CheckedContinuation<Void, Never>?
    private let recorder: OperationRecorder?
    init(failInsert: Bool = false, failing: Set<String> = [], recorder: OperationRecorder? = nil) {
        self.recorder = recorder
        failures = failing
        if failInsert { failures.insert("insert") }
    }
    func seed(_ timer: TimerItem) { timers[timer.id] = timer }
    func fail(_ operation: String) { failures.insert(operation) }
    func resetOperations() { operations = [] }
    private func record(_ operation: String) throws {
        operations.append(operation)
        if failures.contains(operation) { throw TimerRepositoryError.invalidCreation }
    }
    func insert(_ timer: TimerItem) async throws -> TimerItem {
        try record("insert")
        await recorder?.record("persist")
        timers[timer.id] = timer
        return timer
    }
    func update(_ timer: TimerItem) async throws { try record("update"); await recorder?.record("update"); timers[timer.id] = timer }
    func active(limit: Int) async throws -> [TimerItem] {
        try record("publish")
        await recorder?.record("publish")
        requestedActiveLimits.append(limit)
        if activeDelay {
            activeDelay = false
            activeStartedContinuation?.resume()
            activeStartedContinuation = nil
            await withCheckedContinuation { activeContinuation = $0 }
        }
        return Array(timers.values.filter { $0.state == .idle || $0.state == .running || $0.state == .paused }.sorted { $0.id.uuidString < $1.id.uuidString }.prefix(limit))
    }
    func due(at date: Date, limit: Int) async throws -> [TimerItem] {
        try record("due")
        return Array(timers.values.filter { $0.kind == .countdown && $0.state == .running && ($0.deadline ?? .distantFuture) <= date }.sorted { ($0.deadline ?? .distantFuture, $0.id.uuidString) < ($1.deadline ?? .distantFuture, $1.id.uuidString) }.prefix(min(100, max(1, limit))))
    }
    func activePage(limit: Int, after: TimerPageCursor?) async throws -> TimerPage { .init(timers: try await active(limit: limit), nextCursor: nil) }
    func complete(_ id: UUID, at date: Date) async throws -> CompletionOutcome {
        try record("complete")
        await recorder?.record("complete")
        guard let timer = timers[id] else { throw TimerRepositoryError.timerNotFound }
        let outcome = try RecurrenceService().complete(timer, at: date)
        timers[id] = outcome.completed
        if let successor = outcome.successor { timers[successor.id] = successor }
        return outcome
    }
    func cancel(id: UUID, at date: Date) async throws -> TimerItem {
        try record("cancel")
        await recorder?.record("cancel")
        guard var timer = timers[id] else { throw TimerRepositoryError.timerNotFound }
        try timer.cancel(at: date); timers[id] = timer; return timer
    }
    func softDelete(_ id: UUID, at date: Date) async throws {
        try record("softDelete")
        await recorder?.record("softDelete")
        guard var timer = timers[id] else { throw TimerRepositoryError.timerNotFound }
        try timer.softDelete(at: date); timers[id] = timer
    }
    func historyPage(from: Date?, through: Date?, query: String, limit: Int, after: HistoryPageCursor?) async throws -> HistoryPage { .init(entries: [], nextCursor: nil) }
    func updateHistory(_ history: HistoryEntry) async throws {}
    func softDeleteHistory(_ id: UUID, at: Date) async throws {}
    func recoverHistory(_ id: UUID) async throws { await recorder?.record("recover") }
    func purgeHistory(endedBefore: Date) async throws -> Int { 0 }
    func historyCount(for: UUID, limit: Int) async throws -> Int { 0 }
    func successors(of occurrenceID: UUID, limit: Int) async throws -> [TimerItem] {
        Array(timers.values.filter { $0.predecessorOccurrenceID == occurrenceID }.prefix(limit))
    }
    func timer(id: UUID) async throws -> TimerItem { try record("timer"); await recorder?.record("timer"); guard let timer = timers[id] else { throw TimerRepositoryError.timerNotFound }; return timer }
    func recordedOperations() -> [String] { operations }
    func activeLimits() -> [Int] { requestedActiveLimits }
    func suspendNextActive() { activeDelay = true }
    func waitForActiveStart() async {
        if activeDelay == false, activeContinuation != nil { return }
        await withCheckedContinuation { activeStartedContinuation = $0 }
    }
    func releaseActive() { activeContinuation?.resume(); activeContinuation = nil }
}

actor RecordingNotifications: TimerNotificationScheduling {
    var operations: [String] = []
    private let failSchedule: Bool
    private let recorder: OperationRecorder?
    init(failSchedule: Bool = false, recorder: OperationRecorder? = nil) { self.failSchedule = failSchedule; self.recorder = recorder }
    func schedule(_ timer: TimerItem) async throws -> NotificationScheduleStatus { operations.append("schedule"); await recorder?.record("schedule"); if failSchedule { throw TimerRepositoryError.invalidCreation }; return .scheduled }
    func cancel(timerID: UUID) async throws { operations.append("cancel"); await recorder?.record("cancelNotification") }
    func recordedOperations() -> [String] { operations }
}

actor OperationRecorder {
    private var values: [String] = []
    func record(_ value: String) { values.append(value) }
    func operations() -> [String] { values }
}

actor RecordingPresets: PresetRepository {
    private var values: [TimerPreset] = []
    func record(command: String, tags: [String], at: Date) async throws -> TimerPreset {
        let preset = try TimerPreset(command: command, tags: tags, createdAt: at, lastUsed: at)
        values = [preset]
        return preset
    }
    func suggestions(query: String, limit: Int) async throws -> [TimerPreset] { Array(values.prefix(min(20, max(1, limit)))) }
    func softDeletePreset(_ id: UUID, at: Date) async throws {}
    func recoverPreset(_ id: UUID) async throws {}
    func recordCount() -> Int { values.count }
}
