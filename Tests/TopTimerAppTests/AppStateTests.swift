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
        XCTAssertEqual(repositoryOperations, ["insert"])
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

    func testRefreshUsesItsSuppliedTickRatherThanTheInjectedCreationClock() async throws {
        let repository = RecordingRepository()
        let creation = Date(timeIntervalSince1970: 1_000)
        let state = AppState(repository: repository, notifications: RecordingNotifications(), now: { creation })

        await state.create(command: "1m Focus")
        await state.refresh(now: creation.addingTimeInterval(60))

        XCTAssertTrue(state.activeTimers.isEmpty)
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
    private var timers: [UUID: TimerItem] = [:]
    private let failInsert: Bool
    init(failInsert: Bool = false) { self.failInsert = failInsert }
    func insert(_ timer: TimerItem) async throws -> TimerItem {
        operations.append("insert")
        if failInsert { throw TimerRepositoryError.invalidCreation }
        timers[timer.id] = timer
        return timer
    }
    func update(_ timer: TimerItem) async throws { timers[timer.id] = timer }
    func active(limit: Int) async throws -> [TimerItem] {
        return Array(timers.values.filter { $0.state == .idle || $0.state == .running || $0.state == .paused }.prefix(limit))
    }
    func activePage(limit: Int, after: TimerPageCursor?) async throws -> TimerPage { .init(timers: try await active(limit: limit), nextCursor: nil) }
    func complete(_ id: UUID, at date: Date) async throws -> CompletionOutcome {
        guard let timer = timers[id] else { throw TimerRepositoryError.timerNotFound }
        let outcome = try RecurrenceService().complete(timer, at: date)
        timers[id] = outcome.completed
        return outcome
    }
    func cancel(id: UUID, at: Date) async throws -> TimerItem { fatalError() }
    func softDelete(_ id: UUID, at: Date) async throws {}
    func historyPage(from: Date?, through: Date?, query: String, limit: Int, after: HistoryPageCursor?) async throws -> HistoryPage { .init(entries: [], nextCursor: nil) }
    func updateHistory(_ history: HistoryEntry) async throws {}
    func softDeleteHistory(_ id: UUID, at: Date) async throws {}
    func recoverHistory(_ id: UUID) async throws {}
    func purgeHistory(endedBefore: Date) async throws -> Int { 0 }
    func historyCount(for: UUID, limit: Int) async throws -> Int { 0 }
    func successors(of: UUID, limit: Int) async throws -> [TimerItem] { [] }
    func timer(id: UUID) async throws -> TimerItem { throw TimerRepositoryError.timerNotFound }
    func recordedOperations() -> [String] { operations }
}

actor RecordingNotifications: TimerNotificationScheduling {
    var operations: [String] = []
    func schedule(_ timer: TimerItem) async throws -> NotificationScheduleStatus { operations.append("schedule"); return .scheduled }
    func cancel(timerID: UUID) async throws { operations.append("cancel") }
    func recordedOperations() -> [String] { operations }
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
