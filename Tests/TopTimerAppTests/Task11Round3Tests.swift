import AppKit
import SwiftUI
import TopTimerDomain
import TopTimerPersistence
import XCTest

@testable import TopTimerApp

private final class RecoveryData: SettingsDataStore {
  var data: Data?
  var failWrites = false
  func read() -> Data? { data }
  func write(_ data: Data) throws {
    if failWrites { throw CocoaError(.fileWriteNoPermission) }
    self.data = data
  }
}

private actor HistoryQueryRecorder {
  var queries: [HistoryQuery] = []
  func record(from: Date?, through: Date?, query: String) {
    queries.append(HistoryQuery(from: from, through: through, query: query))
  }
  func values() -> [HistoryQuery] { queries }
}

@MainActor final class Task11Round3Tests: XCTestCase {
  func testRecoveredDefaultsPersistAcrossUserDefaultsStoreInstances() throws {
    let suite = "TopTimer.RecoveryTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(Data("corrupt".utf8), forKey: "TopTimer.settings.v1")
    let first = TopTimerSettingsStore(storage: UserDefaultsSettingsDataStore(defaults: defaults))
    XCTAssertNotNil(first.loadForStartup().warning)
    let second = TopTimerSettingsStore(
      storage: UserDefaultsSettingsDataStore(
        defaults: try XCTUnwrap(UserDefaults(suiteName: suite))))
    XCTAssertEqual(try second.load(), .defaults)
    XCTAssertNil(second.loadForStartup().warning)
  }
  func testSettingsWithSimultaneousErrorsFitsAndScrollsAtDefaultWindowSize() async throws {
    let data = RecoveryData()
    data.failWrites = true
    let state = AppState(
      repository: RecordingRepository(), notifications: RecordingNotifications(),
      settingsStore: TopTimerSettingsStore(storage: data),
      settingsRecoveryWarning: "Recovered defaults need review.")
    state.preferences.alertVolume = 0.3
    _ = state.changeLogin(true, apply: { _ in "Login failed. Retry." })
    _ = state.changeHotKey(
      try .init(keyCode: 17, modifiers: 768), slot: .quickEntry,
      apply: { _, _ in "Shortcut failed. Retry." })
    _ = await state.changeDefaultSound("../invalid")
    _ = NSApplication.shared
    let host = NSHostingView(
      rootView: SettingsWindowRoot(
        state: state, updateHotKey: { _, _ in nil }, updateLogin: { _ in nil },
        importSound: { _ in "Glass" }))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 700, height: 520), styleMask: [.titled, .resizable],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: .aqua)
    host.wantsLayer = true
    host.layer?.backgroundColor = NSColor.white.cgColor
    window.contentView = host
    window.orderFront(nil)
    host.layoutSubtreeIfNeeded()
    defer { window.close() }
    XCTAssertLessThanOrEqual(host.fittingSize.height, 520)
    var queue: [NSView] = [host]
    var scrolls: [NSScrollView] = []
    for _ in 0..<1000 {
      guard !queue.isEmpty else { break }
      let view = queue.removeFirst()
      if let scroll = view as? NSScrollView { scrolls.append(scroll) }
      queue.append(contentsOf: view.subviews.prefix(100))
    }
    let scroll = try XCTUnwrap(scrolls.first)
    let document = try XCTUnwrap(scroll.documentView)
    XCTAssertGreaterThan(document.frame.height, scroll.contentView.bounds.height)
    document.scroll(NSPoint(x: 0, y: document.frame.height))
    XCTAssertGreaterThan(scroll.contentView.bounds.origin.y, 0)
    host.layoutSubtreeIfNeeded()
    if let path = ProcessInfo.processInfo.environment["TOPTIMER_TASK11_ROUND3_PROOF"] {
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
        to: URL(fileURLWithPath: path))
    }
  }
  func testShowAllSynchronizesControlsMutationsAndExportQuery() async throws {
    let repo = RecordingRepository()
    let recorded = HistoryQueryRecorder()
    let entry = try HistoryEntry(
      timerID: UUID(), occurrenceID: UUID(), title: "Old", kind: .countdown,
      endedAt: Date(timeIntervalSince1970: 1000), elapsedSeconds: 60, completionReason: .finished)
    await repo.setHistoryHandler { from, through, query, _, _ in
      await recorded.record(from: from, through: through, query: query)
      return .init(entries: [entry], nextCursor: nil)
    }
    let state = AppState(repository: repo, notifications: RecordingNotifications())
    state.historyControls.query = "old query"
    await state.showAllHistory()
    XCTAssertTrue(state.historyControls.allTime)
    XCTAssertEqual(state.historyControls.query, "")
    XCTAssertEqual(state.currentHistoryFilter, .allTime)
    _ = await state.editHistory(entry, title: "New", details: "", tags: [])
    _ = await state.deleteHistory(entry)
    _ = await state.recoverHistory(entry.id)
    await state.exportHistory(to: URL(fileURLWithPath: "/unused"), write: { _, _ in })
    let queries = await recorded.values()
    XCTAssertEqual(queries.count, 5)
    XCTAssertTrue(queries.allSatisfy { $0 == .allTime })
    XCTAssertTrue(state.historyControls.allTime)
  }

  func testStartupResetsMalformedAndUnknownSettingsWithoutThrowingOrLooping() throws {
    for invalid in [
      Data("corrupt".utf8),
      Data(#"{"version":99,"snoozeSeconds":300,"historyPageSize":100,"alertVolume":1}"#.utf8),
      Data(repeating: 0, count: 16385),
    ] {
      let data = RecoveryData()
      data.data = invalid
      let store = TopTimerSettingsStore(storage: data)
      XCTAssertThrowsError(try store.load())
      let recovered = store.loadForStartup()
      XCTAssertEqual(recovered.settings, .defaults)
      XCTAssertNotNil(recovered.warning)
      XCTAssertEqual(try store.load(), .defaults)
      XCTAssertNil(store.loadForStartup().warning)
    }
  }

  func testStartupResetWriteFailureStaysNonfatalAndOffersRetry() throws {
    let data = RecoveryData()
    data.data = Data("corrupt".utf8)
    data.failWrites = true
    let store = TopTimerSettingsStore(storage: data)
    let recovered = store.loadForStartup()
    XCTAssertEqual(recovered.settings, .defaults)
    XCTAssertNotNil(recovered.warning)
    XCTAssertEqual(data.data, Data("corrupt".utf8))
    let state = AppState(
      repository: RecordingRepository(), notifications: RecordingNotifications(),
      settingsStore: store, initialPreferences: recovered.settings,
      settingsRecoveryWarning: recovered.warning)
    data.failWrites = false
    state.saveRecoveredSettings()
    XCTAssertNil(state.settingsRecoveryWarning)
    XCTAssertEqual(try store.load(), .defaults)
  }
}
