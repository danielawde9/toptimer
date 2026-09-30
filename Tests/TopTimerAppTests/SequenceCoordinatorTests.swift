import TopTimerDomain
import TopTimerPersistence
import XCTest

@testable import TopTimerApp

@MainActor final class SequenceCoordinatorTests: XCTestCase {
  func testFailedNextStepSaveLeavesCompletionRetryable() async throws {
    let store = try await CoreDataStore.inMemory()
    let repository = TimerCoreDataRepository(store: store)
    let storage = FailingSequenceStorage()
    let coordinator = SequenceCoordinator(repository: repository, storage: storage)
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    _ = try await coordinator.start(
      steps: [SequenceStep(title: "One", minutes: 1), SequenceStep(title: "Two", minutes: 1)],
      repeats: true, at: date)
    let old = try XCTUnwrap(coordinator.session?.timer)
    _ = try await repository.complete(old.id, at: date.addingTimeInterval(60))
    storage.failing = true
    do {
      _ = try await coordinator.reconcile(at: date.addingTimeInterval(60))
      XCTFail("Write should fail")
    } catch {}
    XCTAssertEqual(coordinator.session?.timer?.id, old.id)
    let stillCompleted = try await repository.timer(id: old.id)
    XCTAssertEqual(stillCompleted.state, .completed)
    storage.failing = false
    _ = try await coordinator.reconcile(at: date.addingTimeInterval(61))
    XCTAssertEqual(coordinator.session?.timer?.title, "Two")
    let active = try await repository.active(limit: 100)
    XCTAssertEqual(active.filter { $0.state == .running }.count, 1)
    try await store.close()
  }

  func testExistingNextTimerRetainsSchedulingAfterRelaunch() async throws {
    let store = try await CoreDataStore.inMemory()
    let repository = TimerCoreDataRepository(store: store)
    let storage = MemorySequenceStorage()
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    var old = try TimerItem.countdown(title: "One", duration: 60, createdAt: date)
    try old.start(at: date)
    _ = try await repository.insert(old)
    _ = try await repository.complete(old.id, at: date.addingTimeInterval(60))
    var next = try TimerItem.countdown(
      title: "Two", duration: 60, createdAt: date.addingTimeInterval(60))
    try next.start(at: next.createdAt)
    _ = try await repository.insert(next)
    try storage.save(
      SequenceSession(
        steps: [SequenceStep(title: "One", minutes: 1), SequenceStep(title: "Two", minutes: 1)],
        repeats: true, index: 1, cycle: 1, timer: next, previousTimerID: old.id))
    let restored = SequenceCoordinator(repository: repository, storage: storage)
    let toSchedule = try await restored.reconcile(at: next.createdAt)
    XCTAssertEqual(toSchedule.map(\.id), [next.id])
    let acknowledged = try await repository.timer(id: old.id)
    XCTAssertEqual(acknowledged.state, .acknowledged)
    try restored.markScheduled(next.id)
    let relaunch = SequenceCoordinator(repository: repository, storage: storage)
    let retry = try await relaunch.reconcile(at: next.createdAt)
    XCTAssertTrue(retry.isEmpty)
    try await store.close()
  }

  func testFinalAcknowledgmentIsRecoveredAfterRelaunch() async throws {
    let store = try await CoreDataStore.inMemory()
    let repository = TimerCoreDataRepository(store: store)
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    var timer = try TimerItem.countdown(title: "Final", duration: 60, createdAt: date)
    try timer.start(at: date)
    _ = try await repository.insert(timer)
    _ = try await repository.complete(timer.id, at: date.addingTimeInterval(60))
    let storage = MemorySequenceStorage()
    try storage.save(
      SequenceSession(
        steps: [SequenceStep(title: "Final", minutes: 1)], repeats: false, index: 0, cycle: 1,
        timer: nil, previousTimerID: timer.id))
    let restored = SequenceCoordinator(repository: repository, storage: storage)
    _ = try await restored.reconcile(at: date.addingTimeInterval(61))
    let saved = try await repository.timer(id: timer.id)
    XCTAssertEqual(saved.state, .acknowledged)
    XCTAssertNil(restored.session?.previousTimerID)
    try await store.close()
  }

  func testStepsAdvanceInOrderAndWrapWithoutParallelTimers() async throws {
    let store = try await CoreDataStore.inMemory()
    let repository = TimerCoreDataRepository(store: store)
    let storage = MemorySequenceStorage()
    let coordinator = SequenceCoordinator(repository: repository, storage: storage)
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let steps = [
      SequenceStep(title: "Task 1", minutes: 15), SequenceStep(title: "Task 2", minutes: 15),
      SequenceStep(title: "Task 3", minutes: 30),
    ]
    _ = try await coordinator.start(steps: steps, repeats: true, at: date)
    for (index, expected) in ["Task 2", "Task 3", "Task 1", "Task 2"].enumerated() {
      let timer = try XCTUnwrap(coordinator.session?.timer)
      let end = try XCTUnwrap(timer.deadline)
      _ = try await repository.complete(timer.id, at: end)
      _ = try await coordinator.reconcile(at: end)
      XCTAssertEqual(coordinator.session?.timer?.title, expected)
      let active = try await repository.active(limit: 100)
      XCTAssertEqual(active.filter { $0.state == .running }.count, 1)
      XCTAssertEqual(coordinator.session?.cycle, index < 2 ? 1 : 2)
    }
    let history = try await repository.historyPage(
      from: nil, through: nil, query: "", limit: 100, after: nil)
    XCTAssertEqual(history.entries.count, 4)
    try await store.close()
  }

  func testPauseStopAndRelaunchRecovery() async throws {
    let store = try await CoreDataStore.inMemory()
    let repository = TimerCoreDataRepository(store: store)
    let storage = MemorySequenceStorage()
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let first = SequenceCoordinator(repository: repository, storage: storage)
    _ = try await first.start(
      steps: [SequenceStep(title: "One", minutes: 1)], repeats: true, at: date)
    var timer = try XCTUnwrap(first.session?.timer)
    try timer.pause(at: date.addingTimeInterval(10))
    try await repository.update(timer)
    let restored = SequenceCoordinator(repository: repository, storage: storage)
    _ = try await restored.reconcile(at: date.addingTimeInterval(500))
    XCTAssertEqual(restored.session?.timer?.id, timer.id)
    XCTAssertEqual(restored.session?.timer?.state, .paused)
    _ = try await restored.stop(at: date.addingTimeInterval(501))
    let relaunch = SequenceCoordinator(repository: repository, storage: storage)
    _ = try await relaunch.reconcile(at: date.addingTimeInterval(600))
    XCTAssertNil(relaunch.session?.timer)
    XCTAssertEqual(relaunch.session?.steps.count, 1)
    try await store.close()
  }

  func testOnePassAndValidation() async throws {
    let store = try await CoreDataStore.inMemory()
    let repository = TimerCoreDataRepository(store: store)
    let coordinator = SequenceCoordinator(repository: repository, storage: MemorySequenceStorage())
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    do {
      _ = try await coordinator.start(
        steps: [SequenceStep(title: "Bad", minutes: 0)], repeats: true, at: date)
      XCTFail("Invalid duration accepted")
    } catch {}
    _ = try await coordinator.start(
      steps: [SequenceStep(title: "Once", minutes: 1)], repeats: false, at: date)
    let timer = try XCTUnwrap(coordinator.session?.timer)
    _ = try await repository.complete(timer.id, at: date.addingTimeInterval(60))
    _ = try await coordinator.reconcile(at: date.addingTimeInterval(60))
    XCTAssertNil(coordinator.session?.timer)
    try await store.close()
  }

  func testRecoversPlannedTimerAndJSONSession() async throws {
    let store = try await CoreDataStore.inMemory()
    let repository = TimerCoreDataRepository(store: store)
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let storage = JSONSequenceStorage(url: folder.appendingPathComponent("sequence.json"))
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    var timer = try TimerItem.countdown(title: "Recover", duration: 60, createdAt: date)
    try timer.start(at: date)
    try storage.save(
      SequenceSession(
        steps: [SequenceStep(title: "Recover", minutes: 1)], repeats: true, index: 0, cycle: 1,
        timer: timer, previousTimerID: nil))
    let coordinator = SequenceCoordinator(repository: repository, storage: storage)
    _ = try await coordinator.reconcile(at: date)
    let saved = try await repository.timer(id: timer.id)
    XCTAssertEqual(saved.id, timer.id)
    _ = try await coordinator.reconcile(at: date)
    let active = try await repository.active(limit: 100)
    XCTAssertEqual(active.count, 1)
    try await store.close()
  }
}

@MainActor private final class FailingSequenceStorage: SequenceStorage {
  private var value: SequenceSession?
  var failing = false
  func load() throws -> SequenceSession? { value }
  func save(_ session: SequenceSession?) throws {
    if failing { throw SequenceError.busy }
    value = session
  }
}
