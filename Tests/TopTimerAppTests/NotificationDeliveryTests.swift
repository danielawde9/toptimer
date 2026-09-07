import TopTimerPersistence
import TopTimerSystem
import UserNotifications
import XCTest

@testable import TopTimerApp

@MainActor final class NotificationDeliveryTests: XCTestCase {
  func testCompositionRetainsRegisteredDelegateUntilShutdown() {
    let center = DelegateCenter()
    let application = TopTimerApplication()
    let state = AppState(repository: RecordingRepository(), notifications: RecordingNotifications())
    application.installNotificationResponses(state: state, center: center)
    weak let retained = center.delegate
    XCTAssertNotNil(retained)
    application.applicationWillTerminate(Notification(name: .init("test")))
    XCTAssertNil(center.delegate)
    XCTAssertNil(retained)
  }

  func testDelegateRoutesNativeResponsesAndRejectsMalformedPayloads() async throws {
    let store = try await CoreDataStore.inMemory()
    let repository = TimerCoreDataRepository(store: store)
    let state = AppState(repository: repository, notifications: RecordingNotifications())
    await state.create(command: "1m Boundary")
    let id = try XCTUnwrap(state.priorityTimer?.id)
    let delegate = TimerNotificationDelegate(state: state)
    let request = UNNotificationRequest(
      identifier: NotificationController.identifier(for: id),
      content: UNNotificationCenterAdapter.content(
        for: .init(
          identifier: NotificationController.identifier(for: id), title: "", body: "",
          categoryIdentifier: NotificationController.categoryIdentifier, fireDate: .now),
        preparedSoundName: nil), trigger: nil)
    for action in ["REPEAT", "SNOOZE"] {
      let before = state.activeTimers.count
      delegate.receive(request: request, actionIdentifier: action)
      for _ in 0..<100 {
        if state.operations.pendingCount == 0 { break }
        try await Task.sleep(for: .milliseconds(10))
      }
      XCTAssertEqual(state.activeTimers.count, before + 1)
      XCTAssertTrue(state.activeTimers.contains { $0.duration == (action == "REPEAT" ? 60 : 300) })
    }
    let before = state.activeTimers.count
    let bad = UNMutableNotificationContent()
    bad.categoryIdentifier = NotificationController.categoryIdentifier
    bad.userInfo = ["timerID": UUID().uuidString, "version": 1]
    delegate.receive(
      request: .init(identifier: request.identifier, content: bad, trigger: nil),
      actionIdentifier: "REPEAT")
    delegate.receive(request: request, actionIdentifier: "UNKNOWN")
    XCTAssertEqual(state.operations.pendingCount, 0)
    XCTAssertEqual(state.activeTimers.count, before)
    delegate.receive(request: request, actionIdentifier: "STOP")
    for _ in 0..<100 {
      if state.operations.pendingCount == 0 { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    let completed = try await repository.timer(id: id)
    XCTAssertEqual(completed.state, .cancelled)
    state.operations.stopAccepting()
    delegate.receive(request: request, actionIdentifier: "REPEAT")
    XCTAssertEqual(state.operations.pendingCount, 0)
    try await store.close()
  }
}

@MainActor private final class DelegateCenter: NotificationDelegateRegistering {
  weak var delegate: (any UNUserNotificationCenterDelegate)?
}
