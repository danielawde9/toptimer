import TopTimerDomain
import TopTimerPersistence
import XCTest

@testable import TopTimerApp

@MainActor final class FinalIntegrationTests: XCTestCase {
  func testNotificationStopCancelsRunningAndPausedRunsWithDurableHistory() async throws {
    for paused in [false, true] {
      let store = try await CoreDataStore.inMemory()
      let repository = TimerCoreDataRepository(store: store)
      let state = AppState(repository: repository, notifications: RecordingNotifications())
      await state.create(command: "5m Stop")
      let id = try XCTUnwrap(state.priorityTimer?.id)
      if paused { _ = await state.pause(id) }
      await state.handle(notificationAction: .stop(id))
      let timer = try await repository.timer(id: id)
      XCTAssertEqual(timer.state, .cancelled)
      await state.loadHistory()
      XCTAssertEqual(state.historyPage.entries.first?.completionReason, .cancelled)
      XCTAssertEqual(state.historyPage.entries.count, 1)
      XCTAssertNil(state.inlineError)
      try await store.close()
    }
  }

  func testCompletedShortcutTargetIsDiscarded() async throws {
    let store = try await CoreDataStore.inMemory()
    let state = AppState(
      repository: TimerCoreDataRepository(store: store), notifications: RecordingNotifications())
    await state.create(command: "")
    let id = try XCTUnwrap(state.priorityTimer?.id)
    await state.togglePriorityTimer()
    _ = await state.complete(id)
    await state.togglePriorityTimer()
    XCTAssertNil(state.priorityTimer)
    XCTAssertEqual(state.activeTimers.first?.state, .completed)
    await state.create(command: "5m Next")
    await state.togglePriorityTimer()
    XCTAssertNil(state.priorityTimer)
    await state.togglePriorityTimer()
    XCTAssertEqual(state.priorityTimer?.title, "Next")
    try await store.close()
  }
  func testNotificationStopAcknowledgesCompletedOccurrenceAndPreservesHistory() async throws {
    let store = try await CoreDataStore.inMemory()
    let repository = TimerCoreDataRepository(store: store)
    let date = Date(timeIntervalSince1970: 1_000)
    var timer = try TimerItem.countdown(title: "Done", duration: 60, createdAt: date)
    try timer.start(at: date)
    _ = try await repository.insert(timer)
    _ = try await repository.complete(timer.id, at: date.addingTimeInterval(60))
    let state = AppState(
      repository: repository, notifications: RecordingNotifications(),
      now: { date.addingTimeInterval(70) })
    await state.handle(notificationAction: .stop(timer.id))
    let saved = try await repository.timer(id: timer.id)
    XCTAssertEqual(saved.state, .acknowledged)
    await state.loadHistory()
    XCTAssertEqual(state.historyPage.entries.count, 1)
    XCTAssertEqual(state.historyPage.entries.first?.completionReason, .finished)
    XCTAssertNil(state.inlineError)
    try await store.close()
  }

  func testShortcutResumesItsPausedTargetBeforeOtherRunningPriority() async throws {
    let store = try await CoreDataStore.inMemory()
    let repository = TimerCoreDataRepository(store: store)
    let date = Date(timeIntervalSince1970: 1_000)
    let state = AppState(
      repository: repository, notifications: RecordingNotifications(), now: { date })
    await state.create(command: "1m First")
    let first = try XCTUnwrap(state.priorityTimer?.id)
    await state.create(command: "2m Second")
    await state.togglePriorityTimer()
    XCTAssertNotEqual(state.priorityTimer?.id, first)
    await state.togglePriorityTimer()
    XCTAssertEqual(state.priorityTimer?.id, first)
    XCTAssertEqual(state.priorityTimer?.state, .running)
    await state.togglePriorityTimer()
    _ = await state.softDelete(first)
    await state.togglePriorityTimer()
    XCTAssertNil(state.priorityTimer)
    await state.togglePriorityTimer()
    XCTAssertEqual(state.priorityTimer?.title, "Second")
    try await store.close()
  }

  func testShortcutResumesWhenNoRunningPriorityRemains() async throws {
    let store = try await CoreDataStore.inMemory()
    let state = AppState(
      repository: TimerCoreDataRepository(store: store), notifications: RecordingNotifications())
    await state.create(command: "")
    let id = try XCTUnwrap(state.priorityTimer?.id)
    await state.togglePriorityTimer()
    XCTAssertNil(state.priorityTimer)
    await state.togglePriorityTimer()
    XCTAssertEqual(state.priorityTimer?.id, id)
    try await store.close()
  }
}
