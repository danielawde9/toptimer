import TopTimerDomain
import TopTimerPersistence
import TopTimerSystem
import XCTest

@testable import TopTimerApp

@MainActor final class SequenceActionsTests: XCTestCase {
  func testRefreshAdvancesAndClearEverythingSurvivesReload() async throws {
    let store = try await CoreDataStore.inMemory()
    let repository = TimerCoreDataRepository(store: store)
    let presets = PresetCoreDataRepository(store: store)
    let storage = MemorySequenceStorage()
    var date = Date(timeIntervalSince1970: 1_800_000_000)
    let state = AppState(
      repository: repository, notifications: RecordingNotifications(), presets: presets,
      now: { date }, sequenceStorage: storage)
    let started = await state.startSequence(
      steps: [SequenceStep(title: "One", minutes: 1), SequenceStep(title: "Two", minutes: 2)],
      repeats: true)
    XCTAssertTrue(started)
    date = date.addingTimeInterval(60)
    _ = await state.refresh(now: date)
    XCTAssertEqual(state.sequenceSession?.timer?.title, "Two")
    await state.create(command: "5m Other")
    XCTAssertFalse(state.suggestions.isEmpty)
    let cleared = await state.deleteAllTimers(clearEverything: true)
    XCTAssertTrue(cleared)
    XCTAssertTrue(state.activeTimers.isEmpty)
    XCTAssertTrue(state.historyPage.entries.isEmpty)
    XCTAssertTrue(state.suggestions.isEmpty)
    XCTAssertNil(try storage.load())
    let relaunched = AppState(
      repository: repository, notifications: RecordingNotifications(), presets: presets,
      now: { date }, sequenceStorage: storage)
    await relaunched.load()
    XCTAssertNil(relaunched.sequenceSession)
    XCTAssertTrue(relaunched.activeTimers.isEmpty)
    try await store.close()
  }

  func testRemovingSuggestionsAndTimersPreservesHistory() async throws {
    let store = try await CoreDataStore.inMemory()
    let repository = TimerCoreDataRepository(store: store)
    let state = AppState(
      repository: repository, notifications: RecordingNotifications(),
      presets: PresetCoreDataRepository(store: store))
    await state.create(command: "stopwatch reading")
    _ = await state.complete(try XCTUnwrap(state.displayedTimer?.id))
    await state.create(command: "10m Tea")
    await state.removeSuggestion("10m Tea")
    XCTAssertFalse(state.suggestions.contains("10m Tea"))
    let cleared = await state.deleteAllTimers()
    XCTAssertTrue(cleared)
    XCTAssertEqual(state.historyPage.entries.count, 1)
    XCTAssertTrue(state.suggestions.contains("stopwatch reading"))
    let suggestionsCleared = await state.clearSuggestions()
    XCTAssertTrue(suggestionsCleared)
    XCTAssertTrue(state.suggestions.isEmpty)
    XCTAssertTrue(state.quickEntryExamples.isEmpty, "Clearing suggestions must not restore built-in examples")
    try await store.close()
  }

  func testNotificationFailureRetainsSchedulingObligation() async throws {
    let store = try await CoreDataStore.inMemory()
    let repository = TimerCoreDataRepository(store: store)
    let notifications = RetryingSequenceNotifications()
    await notifications.setFailure(true)
    let storage = MemorySequenceStorage()
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let state = AppState(
      repository: repository, notifications: notifications, now: { date }, sequenceStorage: storage)
    let result = await state.startSequence(
      steps: [SequenceStep(title: "One", minutes: 1)], repeats: true)
    XCTAssertFalse(result)
    XCTAssertTrue(try XCTUnwrap(storage.load()).schedulePending)
    XCTAssertNotNil(state.sequenceError)
    await notifications.setFailure(false)
    _ = await state.refresh(now: date.addingTimeInterval(1))
    XCTAssertFalse(try XCTUnwrap(storage.load()).schedulePending)
    XCTAssertNil(state.sequenceError)
    XCTAssertEqual(state.notificationStatus, .scheduled)
    let active = try await repository.active(limit: 100)
    XCTAssertEqual(active.count, 1)
    try await store.close()
  }
}

private actor RetryingSequenceNotifications: TimerNotificationScheduling {
  private var failing = false
  func setFailure(_ value: Bool) { failing = value }
  func schedule(_ timer: TimerItem) async throws -> NotificationScheduleStatus {
    if failing { throw TimerRepositoryError.invalidCreation }
    return .scheduled
  }
  func cancel(timerID: UUID) async throws {}
}
