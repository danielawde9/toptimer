import SwiftUI
import TopTimerDomain
import TopTimerPersistence
import TopTimerSystem
import XCTest

@testable import TopTimerApp

private final class RuntimeSettingsData: SettingsDataStore {
  var value: Data?
  var fail = false
  func read() -> Data? { value }
  func write(_ value: Data) throws {
    guard !fail else { throw CocoaError(.fileWriteNoPermission) }
    self.value = value
  }
}

private actor HistoryGate {
  private var paused: CheckedContinuation<Void, Never>?
  private var waiter: CheckedContinuation<Void, Never>?
  func pause() async {
    await withCheckedContinuation { continuation in
      paused = continuation
      waiter?.resume()
      waiter = nil
    }
  }
  func started() async {
    if paused != nil { return }
    await withCheckedContinuation { waiter = $0 }
  }
  func release() {
    paused?.resume()
    paused = nil
  }
}

@MainActor private final class RuntimePower: PowerAssertionClient {
  var creates = 0
  var releases = 0
  var fail = false
  func createPreventIdleSleepAssertion() throws -> SleepAssertionID {
    if fail { throw SleepAssertionError.creationFailed(-1) }
    creates += 1
    return 1
  }
  func releaseAssertion(_ id: SleepAssertionID) throws { releases += 1 }
}

@MainActor final class Task11BehaviorTests: XCTestCase {
  func testDateOnlyQueryIncludesLastInstantAndExcludesNextMidnight() async throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
    let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8)))
    let range = try HistoryDateRange(from: day, through: day, calendar: calendar)
    let store = try await CoreDataStore.inMemory()
    let repo = TimerCoreDataRepository(store: store)
    for (name, end) in [("Included", range.before.addingTimeInterval(-0.001)), ("Excluded", range.before)] {
      let start = end.addingTimeInterval(-60)
      var timer = try TimerItem.countdown(title: name, duration: 60, createdAt: start)
      try timer.start(at: start)
      _ = try await repo.insert(timer)
      _ = try await repo.cancel(id: timer.id, at: end)
    }
    let page = try await repo.historyPage(from: range.from, through: range.inclusiveUpperBound, query: "", limit: 200)
    XCTAssertEqual(page.entries.map(\.title), ["Included"])
    try await store.close()
  }
  func testReportSummaryHasStableAccessibleTotalsAndRejectsOversize() throws {
    let entry = try makeHistory()
    let summary = try ReportSummary(entries: [entry])
    XCTAssertEqual(summary.timerTotals.first?.name, "History")
    XCTAssertEqual(summary.timerTotals.first?.seconds, 60)
    XCTAssertEqual(summary.daily.first?.seconds, 60)
    XCTAssertEqual(summary.weekly.first?.seconds, 60)
    XCTAssertThrowsError(try ReportSummary(entries: Array(repeating: entry, count: 10001)))
  }
  func testNotificationActionPreservesConfiguredSound() async throws {
    let repo = RecordingRepository()
    let source = try TimerItem.countdown(
      title: "Sound", duration: 60, alertName: "Glass", alertVolume: 0.3, createdAt: .now)
    await repo.seed(source)
    let state = AppState(repository: repo, notifications: RecordingNotifications())
    await state.handle(notificationAction: .snooze(source.id, seconds: 300))
    let copy = try XCTUnwrap(state.activeTimers.first { $0.id != source.id })
    XCTAssertEqual(copy.alertName, "Glass")
    XCTAssertEqual(copy.alertVolume, 0.3)
  }
  func testSleepAssertionTracksRunningTimersAndRetryClearsFailure() async throws {
    let power = RuntimePower()
    let state = AppState(
      repository: RecordingRepository(), notifications: RecordingNotifications(),
      sleepController: SleepAssertionController(client: power))
    state.preferences.preventsSleep = true
    power.fail = true
    await state.create(command: "1m")
    XCTAssertNotNil(state.sleepError)
    power.fail = false
    state.updateSleepAssertion()
    XCTAssertNil(state.sleepError)
    XCTAssertEqual(power.creates, 1)
    _ = await state.pause(try XCTUnwrap(state.priorityTimer?.id))
    XCTAssertEqual(power.releases, 1)
  }

  func testRetentionPurgesExpiredHistoryAtLoad() async throws {
    let store = try await CoreDataStore.inMemory()
    let repo = TimerCoreDataRepository(store: store)
    let start = Date(timeIntervalSince1970: 1000)
    var timer = try TimerItem.countdown(title: "Old", duration: 60, createdAt: start)
    try timer.start(at: start)
    _ = try await repo.insert(timer)
    _ = try await repo.cancel(id: timer.id, at: start.addingTimeInterval(30))
    var prefs = TopTimerSettings.defaults
    prefs.retention = .sevenDays
    let state = AppState(
      repository: repo, notifications: RecordingNotifications(), initialPreferences: prefs,
      now: { start.addingTimeInterval(30 * 86400) })
    await state.load()
    XCTAssertTrue(state.historyPage.entries.isEmpty)
    XCTAssertNil(state.retentionError)
    try await store.close()
  }

  func testHotkeyFailurePreservesBothSavedShortcuts() throws {
    let data = RuntimeSettingsData()
    let store = TopTimerSettingsStore(storage: data)
    let state = AppState(
      repository: RecordingRepository(), notifications: RecordingNotifications(),
      settingsStore: store)
    let first = try Shortcut(keyCode: 17, modifiers: 768)
    let second = try Shortcut(keyCode: 35, modifiers: 768)
    XCTAssertNil(state.changeHotKey(first, slot: .quickEntry, apply: { _, _ in nil }))
    XCTAssertNil(state.changeHotKey(second, slot: .pauseResumePriority, apply: { _, _ in nil }))
    XCTAssertNotNil(
      state.changeHotKey(first, slot: .pauseResumePriority, apply: { _, _ in "Conflict" }))
    XCTAssertEqual(try store.load().pauseResumeShortcut, second)
    XCTAssertEqual(state.preferences.quickEntryShortcut, first)
    data.fail = true
    var applied = false
    XCTAssertNotNil(
      state.changeHotKey(
        second, slot: .quickEntry,
        apply: { _, _ in
          applied = true
          return nil
        }))
    XCTAssertFalse(applied)
  }
  func testReportsReadAllPagesAndRejectOversizeWithoutReplacingPriorReport() async throws {
    let repo = RecordingRepository()
    let entry = try makeHistory()
    await repo.setHistoryHandler { _, _, _, _, cursor in
      HistoryPage(
        entries: Array(repeating: entry, count: cursor == nil ? 200 : 1),
        nextCursor: cursor == nil ? .init(endedAt: entry.endedAt, id: entry.id) : nil)
    }
    let state = AppState(repository: repo, notifications: RecordingNotifications())
    await state.loadReports(from: nil, through: nil)
    XCTAssertEqual(state.reportEntries.count, 201)
    await repo.setHistoryHandler { _, _, _, _, cursor in
      let next = (cursor?.endedAt ?? entry.endedAt).addingTimeInterval(-1)
      return HistoryPage(
        entries: Array(repeating: entry, count: 200), nextCursor: .init(endedAt: next, id: UUID()))
    }
    await state.loadReports(from: nil, through: nil)
    XCTAssertEqual(state.reportEntries.count, 201)
    XCTAssertNotNil(state.reportsError)
  }

  func testConcurrentConsumersLatestWinsAndCancelInvalidatesLoad() async throws {
    let repo = RecordingRepository()
    let gate = HistoryGate()
    let entry = try makeHistory()
    await repo.setHistoryHandler { _, _, query, _, _ in
      if query == "slow" { await gate.pause() }
      return HistoryPage(entries: query == "latest" ? [] : [entry], nextCursor: nil)
    }
    let state = AppState(repository: repo, notifications: RecordingNotifications())
    let slow = Task { await state.loadHistory(from: nil, through: nil, query: "slow") }
    await gate.started()
    await state.loadReports(from: nil, through: nil)
    XCTAssertEqual(state.reportEntries.count, 1)
    XCTAssertTrue(state.historyLoading)
    await state.loadHistory(from: nil, through: nil, query: "latest")
    await gate.release()
    await slow.value
    XCTAssertTrue(state.historyPage.entries.isEmpty)
    let cancelled = Task { await state.loadHistory(from: nil, through: nil, query: "slow") }
    await gate.started()
    state.cancelHistoryLoad()
    await gate.release()
    await cancelled.value
    XCTAssertFalse(state.historyLoading)
    XCTAssertTrue(state.historyPage.entries.isEmpty)
    XCTAssertEqual(state.reportEntries.count, 1)
  }

  private func makeHistory() throws -> HistoryEntry {
    try HistoryEntry(
      timerID: UUID(), occurrenceID: UUID(), title: "History", kind: .countdown,
      startedAt: Date(timeIntervalSince1970: 1000), endedAt: Date(timeIntervalSince1970: 1060),
      elapsedSeconds: 60, completionReason: .cancelled)
  }
  func testLoginFailureRollsBackSettingsAndSuccessfulRetryClearsOnlyLoginError() throws {
    let state = AppState(repository: RecordingRepository(), notifications: RecordingNotifications())
    XCTAssertNotNil(state.changeLogin(true, apply: { _ in "Denied" }))
    XCTAssertFalse(state.preferences.launchesAtLogin)
    XCTAssertNil(state.changeLogin(true, apply: { _ in nil }))
    XCTAssertTrue(state.preferences.launchesAtLogin)
  }

  func testFailedSoundValidationPreservesPreviousSelection() async {
    let state = AppState(repository: RecordingRepository(), notifications: RecordingNotifications())
    state.preferences.defaultAlertName = "Glass"
    let accepted = await state.changeDefaultSound("../invalid")
    XCTAssertFalse(accepted)
    XCTAssertEqual(state.preferences.defaultAlertName, "Glass")
  }

  func testNotificationSettingsDeepLinkHasActionAndReportsOpenFailure() {
    var opened: URL?
    XCTAssertTrue(
      NotificationSettingsLink.open {
        opened = $0
        return true
      })
    XCTAssertEqual(
      opened?.absoluteString, "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
    )
    XCTAssertFalse(NotificationSettingsLink.open { _ in false })
  }
  func testClockPreferenceControlsParserAndDisplay() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let date = Date(timeIntervalSince1970: 13 * 3600)
    XCTAssertEqual(
      WallClockDisplay.string(date, uses24HourTime: true, timeZone: calendar.timeZone), "13:00")
    XCTAssertEqual(
      WallClockDisplay.string(date, uses24HourTime: false, timeZone: calendar.timeZone), "1:00 PM")
    XCTAssertThrowsError(
      try TimerParser(calendar: calendar, now: date, uses24HourTime: false).parse("@14:30"))
    XCTAssertNoThrow(
      try TimerParser(calendar: calendar, now: date, uses24HourTime: false).parse("@2:30pm"))
  }
  func testSettingsSaveFailureKeepsRuntimeValueAndRelaunchRestoresSavedValue() async throws {
    let data = RuntimeSettingsData()
    let settings = TopTimerSettingsStore(storage: data)
    let state = AppState(
      repository: RecordingRepository(), notifications: RecordingNotifications(),
      settingsStore: settings)
    state.preferences.alertVolume = 0.4
    XCTAssertEqual(try settings.load().alertVolume, 0.4)
    data.fail = true
    state.preferences.alertVolume = 0.8
    XCTAssertEqual(state.preferences.alertVolume, 0.4)
    XCTAssertNotNil(state.settingsError)
    let relaunched = AppState(
      repository: RecordingRepository(), notifications: RecordingNotifications(),
      initialPreferences: try settings.load())
    XCTAssertEqual(relaunched.preferences.alertVolume, 0.4)
  }
  func testDeletedHistorySurvivesRelaunchAndRecovers() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("history.sqlite")
    let first = try await CoreDataStore.sqlite(at: url)
    let repo = TimerCoreDataRepository(store: first)
    var timer = try TimerItem.countdown(
      title: "Deleted", duration: 60, createdAt: Date(timeIntervalSince1970: 1000))
    try timer.start(at: timer.createdAt)
    _ = try await repo.insert(timer)
    _ = try await repo.cancel(id: timer.id, at: timer.createdAt.addingTimeInterval(30))
    let page = try await repo.historyPage(from: nil, through: nil, query: "", limit: 200)
    let entry = try XCTUnwrap(page.entries.first)
    try await repo.softDeleteHistory(entry.id, at: timer.createdAt.addingTimeInterval(40))
    try await first.close()
    let second = try await CoreDataStore.sqlite(at: url)
    let state = AppState(
      repository: TimerCoreDataRepository(store: second), notifications: RecordingNotifications())
    await state.load()
    XCTAssertEqual(state.recentlyDeletedHistory.map(\.id), [entry.id])
    _ = await state.recoverHistory(entry.id)
    XCTAssertEqual(state.historyPage.entries.map(\.id), [entry.id])
    XCTAssertTrue(state.recentlyDeletedHistory.isEmpty)
    try await second.close()
  }

  func testCSVFailureDoesNotReplacePageOrHistoryError() async throws {
    let state = AppState(repository: RecordingRepository(), notifications: RecordingNotifications())
    await state.loadHistory()
    let page = state.historyPage
    await state.exportHistory(
      to: URL(fileURLWithPath: "/unused"),
      write: { _, _ in throw CocoaError(.fileWriteNoPermission) })
    XCTAssertNotNil(state.exportError)
    XCTAssertNil(state.historyError)
    XCTAssertEqual(state.historyPage, page)
  }
  func testNewTimersUseDefaultAlertAndVolume() async throws {
    let state = AppState(repository: RecordingRepository(), notifications: RecordingNotifications())
    state.preferences.defaultAlertName = "Glass"
    state.preferences.alertVolume = 0.25
    await state.create(command: "1m Focus")
    XCTAssertEqual(state.activeTimers.first?.alertName, "Glass")
    XCTAssertEqual(state.activeTimers.first?.alertVolume, 0.25)
  }

  func testReportsDoNotReplaceHistoryAndHistoryEditPreservesSearch() async throws {
    let store = try await CoreDataStore.inMemory()
    let state = AppState(
      repository: TimerCoreDataRepository(store: store), notifications: RecordingNotifications())
    await state.create(command: "1m Work")
    let id = try XCTUnwrap(state.activeTimers.first?.id)
    _ = await state.cancel(id)
    await state.loadHistory(from: nil, through: nil, query: "Work")
    let entry = try XCTUnwrap(state.historyPage.entries.first)
    await state.loadReports(from: nil, through: nil)
    XCTAssertEqual(state.historyPage.entries, [entry])
    _ = await state.editHistory(entry, title: "Other", details: "", tags: [])
    XCTAssertTrue(state.historyPage.entries.isEmpty)
    XCTAssertEqual(state.reportEntries.first?.title, "Other")
    try await store.close()
  }

  func testDateOnlyBoundsIncludeWholeDSTDay() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
    for (month, day, hours) in [(3, 8, 23), (11, 1, 25)] {
      let date = try XCTUnwrap(
        calendar.date(from: DateComponents(year: 2026, month: month, day: day)))
      let range = try HistoryDateRange(from: date, through: date, calendar: calendar)
      XCTAssertEqual(range.before.timeIntervalSince(range.from), Double(hours * 3600))
    }
  }

  func testCloseAllClosesEveryRealWindowAndReleasesContent() {
    let coordinator = WindowCoordinator()
    let controllers = TopTimerWindow.allCases.map { kind in
      coordinator.show(kind: kind) { Text("Test") }
    }
    coordinator.closeAll()
    XCTAssertEqual(coordinator.windowCount, 0)
    XCTAssertTrue(
      controllers.allSatisfy {
        $0.window?.isVisible == false && $0.window?.contentViewController == nil
      })
  }
}
