import AppKit
import SwiftUI
import TopTimerDomain
import TopTimerPersistence
import TopTimerSystem
import XCTest

@testable import TopTimerApp

@MainActor
final class Task10Round5BoundaryTests: XCTestCase {
  func testFailedSoundPreparationPreservesPersistedChoiceAndSuccessfulChoiceReachesRequest()
    async throws
  {
    let store = try await CoreDataStore.inMemory()
    let repository = TimerCoreDataRepository(store: store)
    let now = Date(timeIntervalSince1970: 1_000)
    var timer = try TimerItem.countdown(
      title: "Tea", duration: 60, alertName: "Glass", createdAt: now)
    try timer.start(at: now)
    _ = try await repository.insert(timer)
    let center = ConfiguredSoundCenter()
    let state = AppState(
      repository: repository, notifications: NotificationController(center: center))
    let configuration = TimerConfiguration(
      kind: .countdown, title: "Tea", details: "", tags: [], duration: 60, recurrence: .none,
      alertName: "Ping", alertVolume: 0.4)
    let failed = await state.reconfigure(timer.id, configuration: configuration)
    XCTAssertFalse(failed)
    let unchanged = try await repository.timer(id: timer.id)
    XCTAssertEqual(unchanged, timer)
    await center.allowSound()
    let succeeded = await state.reconfigure(timer.id, configuration: configuration)
    XCTAssertTrue(succeeded)
    assertEqual(await center.request?.soundName, "Ping")
    try await store.close()
  }
  func testDueAndExplicitCompletionPlaySelectedSoundAtConfiguredVolumeAfterPersistence()
    async throws
  {
    let store = try await CoreDataStore.inMemory()
    let repository = TimerCoreDataRepository(store: store)
    let now = Date(timeIntervalSince1970: 1_000)
    let player = CompletionPlayerSpy(repository: repository)
    let state = AppState(
      repository: repository, notifications: RecordingNotifications(),
      alertSounds: AlertSoundController(player: player), now: { now.addingTimeInterval(60) })
    for manual in [false, true] {
      var timer = try TimerItem.countdown(
        title: "Audible", duration: 60, alertName: "Ping", alertVolume: 0.3, createdAt: now)
      try timer.start(at: now)
      _ = try await repository.insert(timer)
      if manual {
        _ = await state.complete(timer.id)
        _ = await state.complete(timer.id)
      } else {
        await state.refresh(now: now.addingTimeInterval(60))
        await state.refresh(now: now.addingTimeInterval(61))
      }
    }
    assertEqual(await player.volumes, [0.3, 0.3])
    assertEqual(await player.names, ["Ping.aiff", "Ping.aiff"])
    assertEqual(await player.sawPersistedCompletion, [true, true])
    try await store.close()
  }
  func testNativeCoordinatorConsumesSuggestionNavigationOnlyWhenAvailable() {
    var selected = 0
    let input = QuickEntryTextField(
      text: .constant("5"), selectedSuggestion: Binding(get: { selected }, set: { selected = $0 }),
      suggestions: ["5m", "5h"], focus: false
    ) { _ in }
    let field = CompositionField()
    XCTAssertTrue(input.makeCoordinator().handle(#selector(NSResponder.moveDown(_:)), field: field))
    XCTAssertEqual(selected, 1)
  }
  func testNativeCoordinatorPassesArrowCommandsThroughWithoutSuggestionsOrDuringComposition() {
    for composing in [false, true] {
      var emitted: [QuickEntryEffect] = []
      let input = QuickEntryTextField(
        text: .constant("abc"), selectedSuggestion: .constant(0),
        suggestions: composing ? ["5m"] : [], focus: false
      ) { emitted.append($0) }
      let coordinator = input.makeCoordinator()
      let field = CompositionField()
      field.stringValue = "abc"
      field.composition = composing
      XCTAssertFalse(coordinator.handle(#selector(NSResponder.moveUp(_:)), field: field))
      XCTAssertFalse(coordinator.handle(#selector(NSResponder.moveDown(_:)), field: field))
      XCTAssertTrue(emitted.isEmpty)
    }
  }
  func testRealNotificationControllerRequestsOnlyAfterCountdownPersistence() async throws {
    let store = try await CoreDataStore.inMemory()
    let repository = TimerCoreDataRepository(store: store)
    let center = CreationAuthorizationCenter(repository: repository)
    let firstFailure = AppState(
      repository: RecordingRepository(failInsert: true),
      notifications: NotificationController(center: center))
    await firstFailure.create(command: "5m Cannot persist")
    assertEqual(await center.authorizationCalls, 0)
    let state = AppState(
      repository: repository, notifications: NotificationController(center: center))
    await state.create(command: "")
    assertEqual(await center.authorizationCalls, 0)
    await state.create(command: "5m Tea")
    assertEqual(await center.authorizationCalls, 1)
    assertEqual(await center.persistedCountdownsAtAuthorization, 1)
    XCTAssertEqual(state.notificationStatus, .authorizationDenied)
    let failedState = AppState(
      repository: RecordingRepository(failInsert: true),
      notifications: NotificationController(center: center))
    await failedState.create(command: "5m Failed")
    assertEqual(await center.authorizationCalls, 1)
    try await store.close()
  }
}

actor ConfiguredSoundCenter: NotificationCenterClient {
  var fail = true
  var request: NotificationRequest?
  func allowSound() { fail = false }
  func authorizationStatus() async -> NotificationAuthorizationStatus { .authorized }
  func requestAuthorization() async throws -> Bool { true }
  func prepareSound(named name: String?) async throws -> String? {
    if fail { throw NotificationSoundError.unsupportedAudio }
    return name
  }
  func setCategories(_ categories: [NotificationCategory]) async {}
  func pendingRequests(limit: Int) async -> [PendingNotification] { [] }
  func add(_ request: NotificationRequest) async throws { self.request = request }
  func removePendingRequests(identifiers: [String]) async {}
}

actor CompletionPlayerSpy: SoundPlayer {
  let repository: any TimerRepository
  var volumes: [Double] = []
  var names: [String] = []
  var sawPersistedCompletion: [Bool] = []
  init(repository: any TimerRepository) { self.repository = repository }
  func play(url: URL?, volume: Double) async -> Bool {
    volumes.append(volume)
    names.append(url?.lastPathComponent ?? "default")
    do {
      sawPersistedCompletion.append(
        try await repository.active(limit: 100).contains { $0.state == .completed })
    } catch { sawPersistedCompletion.append(false) }
    return true
  }
}

@MainActor private final class CompositionField: NSTextField {
  var composition = false
  private let editor = NSTextView()
  override func currentEditor() -> NSText? {
    if composition {
      editor.setMarkedText("a", selectedRange: NSRange(location: 1, length: 0),
        replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
    } else { editor.unmarkText() }
    return editor
  }
}

extension XCTestCase {
  fileprivate func assertEqual<T: Equatable>(
    _ value: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertEqual(value, expected, file: file, line: line)
  }
}

actor CreationAuthorizationCenter: NotificationCenterClient {
  let repository: any TimerRepository
  var authorizationCalls = 0
  var persistedCountdownsAtAuthorization = 0
  init(repository: any TimerRepository) { self.repository = repository }
  func authorizationStatus() async -> NotificationAuthorizationStatus {
    authorizationCalls == 0 ? .notDetermined : .denied
  }
  func requestAuthorization() async throws -> Bool {
    persistedCountdownsAtAuthorization = try await repository.active(limit: 100).filter {
      $0.kind == .countdown
    }.count
    authorizationCalls += 1
    return false
  }
  func setCategories(_ categories: [NotificationCategory]) async {}
  func pendingRequests(limit: Int) async -> [PendingNotification] { [] }
  func add(_ request: NotificationRequest) async throws {}
  func removePendingRequests(identifiers: [String]) async {}
}
