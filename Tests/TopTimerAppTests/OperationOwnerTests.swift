import TopTimerPersistence
import XCTest

@testable import TopTimerApp

@MainActor final class OperationOwnerTests: XCTestCase {
  func testAppStateWorkFinishesRealCoreDataPersistenceBeforeClose() async throws {
    let store = try await CoreDataStore.inMemory()
    let repository = TimerCoreDataRepository(store: store)
    let owner = AppOperationOwner()
    let state = AppState(
      repository: repository, notifications: RecordingNotifications(), operations: owner)
    var release: CheckedContinuation<Void, Never>?
    let started = expectation(description: "UI operation started")
    let cancelled = expectation(description: "shutdown draining UI operation")
    state.perform {
      await withTaskCancellationHandler {
        await withCheckedContinuation {
          release = $0
          started.fulfill()
        }
      } onCancel: {
        cancelled.fulfill()
      }
      await state.create(command: "1m Finish before close")
    }
    XCTAssertEqual(owner.pendingCount, 1)
    await fulfillment(of: [started])
    owner.stopAccepting()
    let closing = Task {
      await owner.drain()
      let saved = try await repository.active(limit: 100)
      XCTAssertEqual(saved.count, 1)
      try await store.close()
    }
    await fulfillment(of: [cancelled])
    state.perform { XCTFail("UI work accepted during close") }
    XCTAssertNotNil(state.inlineError)
    release?.resume()
    try await closing.value
    XCTAssertEqual(owner.pendingCount, 0)
  }
  func testRegisteredButNotStartedWorkCannotStartAfterShutdown() async {
    let owner = AppOperationOwner()
    XCTAssertTrue(owner.submit { XCTFail("queued work started after admission closed") })
    owner.stopAccepting()
    // A FIFO main-actor task lets the queued job attempt to start before drain.
    await Task { @MainActor in }.value
    await owner.drain()
    XCTAssertEqual(owner.pendingCount, 0)
  }
  func testShutdownDrainsBeforeCloseAndRejectsNewWork() async {
    let owner = AppOperationOwner(capacity: 2)
    var release: CheckedContinuation<Void, Never>?
    let started = expectation(description: "started")
    let finished = expectation(description: "drained")
    let cancellation = expectation(description: "shutdown reached barrier")
    XCTAssertTrue(
      owner.submit {
        await withTaskCancellationHandler {
          await withCheckedContinuation {
            release = $0
            started.fulfill()
          }
        } onCancel: {
          cancellation.fulfill()
        }
        finished.fulfill()
      })
    XCTAssertEqual(owner.pendingCount, 1)
    await fulfillment(of: [started])
    owner.stopAccepting()
    XCTAssertFalse(owner.submit { XCTFail("started after shutdown") })
    var closed = false
    let closing = Task {
      await owner.drain()
      closed = true
    }
    await fulfillment(of: [cancellation])
    XCTAssertFalse(closed)
    XCTAssertEqual(owner.pendingCount, 1)
    release?.resume()
    await closing.value
    await fulfillment(of: [finished])
    XCTAssertTrue(closed)
    XCTAssertEqual(owner.pendingCount, 0)
  }

  func testCapacityIsReservedSynchronouslyAndCompletionReleasesIt() async {
    let owner = AppOperationOwner(capacity: 1)
    let completed = expectation(description: "completed")
    XCTAssertTrue(owner.submit { completed.fulfill() })
    XCTAssertFalse(owner.submit { XCTFail("exceeded bound") })
    await fulfillment(of: [completed])
    XCTAssertEqual(owner.pendingCount, 0)
    XCTAssertTrue(owner.submit {})
    await owner.drain()
    XCTAssertEqual(owner.pendingCount, 0)
  }
}
