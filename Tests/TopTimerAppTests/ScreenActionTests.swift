import AppKit
import SwiftUI
import TopTimerDomain
import TopTimerPersistence
import Vision
import XCTest

@testable import TopTimerApp

@MainActor final class ScreenActionTests: XCTestCase {
  func testCurrentPopoverPreservesSuggestionReturnSpaceAndEscape() async throws {
    let store = try await CoreDataStore.inMemory()
    let state = AppState(
      repository: TimerCoreDataRepository(store: store), notifications: RecordingNotifications(),
      presets: PresetCoreDataRepository(store: store))
    await state.create(command: "10m Tea")
    _ = await state.cancel(try XCTUnwrap(state.displayedTimer?.id))
    var closed = false
    let host = NSHostingView(
      rootView: MenuBarPopoverView(
        state: state, openSettings: {}, openTimers: {}, quit: {}, closePopover: { closed = true }))
    let window = mount(host, size: NSSize(width: 320, height: 300))
    defer { window.close() }
    let field = try XCTUnwrap(
      nativeViews(host).compactMap { $0 as? QuickEntryTextField.Field }.first)
    field.doCommand(by: #selector(NSResponder.moveDown(_:)))
    XCTAssertTrue(window.makeFirstResponder(field))
    let enter = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
      modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
      windowNumber: window.windowNumber, context: nil, characters: "\r",
      charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
    window.sendEvent(enter)
    await settle(state, host: host)
    XCTAssertEqual(state.displayedTimer?.title, "Tea")
    XCTAssertEqual(state.activeTimers.filter { $0.state == .running }.count, 1)
    field.doCommand(by: NSSelectorFromString("insertSpace:"))
    await settle(state, host: host)
    XCTAssertEqual(state.displayedTimer?.state, .paused)
    field.doCommand(by: NSSelectorFromString("insertSpace:"))
    await settle(state, host: host)
    XCTAssertEqual(state.displayedTimer?.state, .running)
    state.quickEntryText = "draft"
    await settle(state, host: host)
    field.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
    await settle(state, host: host)
    XCTAssertEqual(state.quickEntryText, "")
    XCTAssertFalse(closed)
    field.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
    XCTAssertTrue(closed)
    try await store.close()
  }

  func testRenderedSequenceAddRemoveStartPauseResumeStop() async throws {
    let store = try await CoreDataStore.inMemory()
    let state = AppState(
      repository: TimerCoreDataRepository(store: store), notifications: RecordingNotifications())
    let host = NSHostingView(rootView: SequenceView(state: state))
    let window = mount(host, size: NSSize(width: 620, height: 500))
    defer { window.close() }
    try press("Add task", in: host)
    await settle(state, host: host)
    XCTAssertTrue(
      nativeViews(host).compactMap { $0 as? NSTextField }.contains { $0.stringValue == "Task 4" })
    try press("Remove", in: host, occurrence: 3)
    await settle(state, host: host)
    XCTAssertFalse(
      nativeViews(host).compactMap { $0 as? NSTextField }.contains { $0.stringValue == "Task 4" })
    try press("Start sequence", in: host)
    await settle(state, host: host)
    XCTAssertEqual(state.sequenceSession?.steps.count, 3)
    XCTAssertEqual(state.sequenceSession?.timer?.duration, 900)
    XCTAssertEqual(state.activeTimers.filter { $0.state == .running }.count, 1)
    try press("Pause sequence", in: host)
    await settle(state, host: host)
    XCTAssertEqual(state.activeTimers.first?.state, .paused)
    try press("Resume sequence", in: host)
    await settle(state, host: host)
    XCTAssertEqual(state.activeTimers.first?.state, .running)
    try press("Stop sequence", in: host)
    await settle(state, host: host)
    XCTAssertNil(state.sequenceSession?.timer)
    try await store.close()
  }

  func testRenderedClearEverythingAndDeleteAllCancel() async throws {
    let store = try await CoreDataStore.inMemory()
    let state = AppState(
      repository: TimerCoreDataRepository(store: store), notifications: RecordingNotifications(),
      presets: PresetCoreDataRepository(store: store))
    await state.create(command: "10m Tea")
    let host = NSHostingView(rootView: TimerListHost(state: state, sounds: SoundCatalogState()))
    let window = mount(host, size: NSSize(width: 380, height: 420))
    defer { window.close() }
    try press("Delete all timers", in: host)
    let cancelSheet = try await attachedSheet(window)
    try press("Cancel", in: try XCTUnwrap(cancelSheet.contentView))
    await settle(state, host: host)
    XCTAssertEqual(state.activeTimers.count, 1)
    try press("Delete all timers", in: host)
    let deleteSheet = try await attachedSheet(window)
    try press("Delete all timers", in: try XCTUnwrap(deleteSheet.contentView))
    await settle(state, host: host)
    XCTAssertTrue(state.activeTimers.isEmpty)
    XCTAssertFalse(state.suggestions.isEmpty)
    await state.create(command: "5m Focus")
    await settle(state, host: host)
    try press("Clear everything", in: host)
    let sheet = try await attachedSheet(window)
    try press("Clear everything", in: try XCTUnwrap(sheet.contentView))
    await settle(state, host: host)
    XCTAssertTrue(state.activeTimers.isEmpty)
    XCTAssertTrue(state.suggestions.isEmpty)
    XCTAssertTrue(state.historyPage.entries.isEmpty)
    try await store.close()
  }

  func testRenderedClearSavedSuggestions() async throws {
    let store = try await CoreDataStore.inMemory()
    let state = AppState(
      repository: TimerCoreDataRepository(store: store), notifications: RecordingNotifications(),
      presets: PresetCoreDataRepository(store: store))
    await state.create(command: "10m Tea")
    _ = await state.cancel(try XCTUnwrap(state.displayedTimer?.id))
    let host = NSHostingView(
      rootView: MenuBarPopoverView(state: state, openSettings: {}, openTimers: {}, quit: {}))
    let window = mount(host, size: NSSize(width: 320, height: 300))
    defer { window.close() }
    try press("Remove", in: host)
    await settle(state, host: host)
    XCTAssertFalse(state.suggestions.contains("10m Tea"))
    await state.create(command: "15m Reading")
    _ = await state.cancel(try XCTUnwrap(state.displayedTimer?.id))
    await settle(state, host: host)
    try press("Clear saved suggestions", in: host)
    await settle(state, host: host)
    XCTAssertTrue(state.suggestions.isEmpty)
    let remaining = try await PresetCoreDataRepository(store: store).suggestions(
      query: "", limit: 200)
    XCTAssertTrue(remaining.isEmpty)
    try await store.close()
  }

  func testSettingsCanUnsetTheDefaultRegisteredShortcut() async throws {
    let state = AppState(repository: RecordingRepository(), notifications: RecordingNotifications())
    var changedQuickEntry = false
    let host = NSHostingView(
      rootView: SettingsWindowRoot(
        state: state,
        updateHotKey: { slot, value in
          if slot == .quickEntry && value == nil { changedQuickEntry = true }
          return nil
        }, updateLogin: { _ in nil }, importSound: { _ in "Glass" }))
    let window = mount(host, size: NSSize(width: 620, height: 820))
    defer { window.close() }
    try press("Unset", in: host)
    await settle(state, host: host)
    XCTAssertTrue(changedQuickEntry)
    XCTAssertTrue(state.preferences.quickEntryShortcutIsDisabled)
    XCTAssertNil(state.preferences.quickEntryShortcut)
  }

  func testNativeTimerMenuActionsPersistTheirChanges() async throws {
    for action in [
      "Pause", "Resume", "Restart", "Duplicate", "Stop", "Delete", "Acknowledge", "Start",
    ] {
      let store = try await CoreDataStore.inMemory()
      let repository = TimerCoreDataRepository(store: store)
      var date = Date.now
      let state = AppState(
        repository: repository, notifications: RecordingNotifications(), now: { date })
      let id: UUID
      if action == "Start" {
        let timer = try TimerItem.countdown(title: "Focus", duration: 1500, createdAt: date)
        _ = try await repository.insert(timer)
        id = timer.id
        await state.load()
        date = date.addingTimeInterval(1)
      } else {
        await state.create(command: "25m Focus")
        id = try XCTUnwrap(state.activeTimers.first?.id)
        date = date.addingTimeInterval(1)
        if action == "Resume" {
          _ = await state.pause(id)
          date = date.addingTimeInterval(1)
        }
        if action == "Acknowledge" {
          date = date.addingTimeInterval(1500)
          _ = await state.complete(id)
          date = date.addingTimeInterval(1)
        }
      }
      let host = NSHostingView(rootView: TimerListHost(state: state, sounds: SoundCatalogState()))
      let window = mount(host, size: NSSize(width: 380, height: 420))
      try menuAction(action, in: host)
      for _ in 0..<200 {
        let current = try await repository.timer(id: id)
        let finished: Bool
        switch action {
        case "Pause": finished = current.state == .paused
        case "Resume", "Start":
          finished = current.state == .running
        case "Restart":
          finished =
            current.state == .running
            && abs((current.startedAt ?? .distantPast).timeIntervalSince(date)) < 0.001
        case "Duplicate": finished = state.activeTimers.count == 2
        case "Stop": finished = current.state == .cancelled
        case "Delete": finished = current.deletedAt != nil
        case "Acknowledge": finished = current.state == .acknowledged
        default: finished = false
        }
        if finished { break }
        try await Task.sleep(for: .milliseconds(10))
      }
      await settle(state, host: host)
      let saved = try await repository.timer(id: id)
      switch action {
      case "Pause": XCTAssertEqual(saved.state, .paused)
      case "Resume", "Restart", "Start":
        XCTAssertEqual(saved.state, .running, "\(action): \(state.inlineError ?? "no error")")
      case "Duplicate": XCTAssertEqual(state.activeTimers.count, 2)
      case "Stop": XCTAssertEqual(saved.state, .cancelled)
      case "Delete": XCTAssertNotNil(saved.deletedAt)
      case "Acknowledge": XCTAssertEqual(saved.state, .acknowledged)
      default: XCTFail("Unexpected action")
      }
      if action == "Restart" {
        XCTAssertEqual(try XCTUnwrap(saved.startedAt).timeIntervalSince(date), 0, accuracy: 0.001)
      }
      window.close()
      try await store.close()
    }
  }

  func testNativeEditorSaveAndCancel() async throws {
    let store = try await CoreDataStore.inMemory()
    let repository = TimerCoreDataRepository(store: store)
    let state = AppState(repository: repository, notifications: RecordingNotifications())
    await state.create(command: "25m Focus")
    let id = try XCTUnwrap(state.activeTimers.first?.id)
    let host = NSHostingView(rootView: TimerListHost(state: state, sounds: SoundCatalogState()))
    let window = mount(host, size: NSSize(width: 380, height: 420))
    defer { window.close() }
    try menuAction("Edit", in: host)
    await settle(state, host: host)
    let sheet = try await attachedSheet(window)
    let content = try XCTUnwrap(sheet.contentView)
    content.layoutSubtreeIfNeeded()
    let title = try XCTUnwrap(
      nativeViews(content).compactMap { $0 as? NSTextField }.first { $0.stringValue == "Focus" })
    title.stringValue = "Edited Focus"
    title.delegate?.controlTextDidChange?(
      Notification(name: NSControl.textDidChangeNotification, object: title))
    try press("Save", in: content)
    await settle(state, host: host)
    let saved = try await repository.timer(id: id)
    XCTAssertEqual(saved.title, "Edited Focus")
    XCTAssertNil(state.selectedEditorTimer)
    XCTAssertNil(window.attachedSheet)
    try menuAction("Edit", in: host)
    await settle(state, host: host)
    let second = try await attachedSheet(window)
    let secondContent = try XCTUnwrap(second.contentView)
    let field = try XCTUnwrap(
      nativeViews(secondContent).compactMap { $0 as? NSTextField }.first {
        $0.stringValue == "Edited Focus"
      })
    field.stringValue = "Do not save"
    field.delegate?.controlTextDidChange?(
      Notification(name: NSControl.textDidChangeNotification, object: field))
    try press("Cancel", in: secondContent)
    await settle(state, host: host)
    let unchanged = try await repository.timer(id: id)
    XCTAssertEqual(unchanged.title, "Edited Focus")
    XCTAssertNil(state.selectedEditorTimer)
    try await store.close()
  }

  func testRenderedStopwatchExampleAndFinish() async throws {
    let store = try await CoreDataStore.inMemory()
    let state = AppState(
      repository: TimerCoreDataRepository(store: store), notifications: RecordingNotifications())
    let host = NSHostingView(
      rootView: MenuBarPopoverView(state: state, openSettings: {}, openTimers: {}, quit: {}))
    let window = mount(host, size: NSSize(width: 320, height: 300))
    defer { window.close() }
    try press("stopwatch reading", in: host)
    await settle(state, host: host)
    XCTAssertEqual(state.displayedTimer?.kind, .stopwatch)
    XCTAssertEqual(state.displayedTimer?.title, "reading")
    try press("Finish", in: host)
    await settle(state, host: host)
    XCTAssertNil(state.displayedTimer)
    XCTAssertEqual(state.historyPage.entries.first?.kind, .stopwatch)
    try await store.close()
  }

  func testRenderedHistoryEditDeleteAndRecover() async throws {
    let store = try await CoreDataStore.inMemory()
    let repository = TimerCoreDataRepository(store: store)
    let state = AppState(repository: repository, notifications: RecordingNotifications())
    await state.create(command: "stopwatch reading #books")
    _ = await state.complete(try XCTUnwrap(state.activeTimers.first?.id))
    state.historyControls.allTime = true
    let host = NSHostingView(rootView: HistoryView(state: state))
    let window = mount(host, size: NSSize(width: 700, height: 520))
    defer { window.close() }
    await settle(state, host: host)
    let table = try XCTUnwrap(nativeViews(host).compactMap { $0 as? NSTableView }.first)
    table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    table.delegate?.tableViewSelectionDidChange?(
      Notification(name: NSTableView.selectionDidChangeNotification, object: table))
    await settle(state, host: host)
    try press("Edit", in: host)
    let sheet = try await attachedSheet(window)
    let content = try XCTUnwrap(sheet.contentView)
    content.layoutSubtreeIfNeeded()
    let field = try XCTUnwrap(
      nativeViews(content).compactMap { $0 as? NSTextField }.first { $0.stringValue == "reading" })
    field.stringValue = "Reading notes"
    field.delegate?.controlTextDidChange?(
      Notification(name: NSControl.textDidChangeNotification, object: field))
    try press("Save changes", in: content)
    await settle(state, host: host)
    XCTAssertEqual(state.historyPage.entries.first?.title, "Reading notes")
    XCTAssertNil(window.attachedSheet)
    let refreshedTable = try XCTUnwrap(nativeViews(host).compactMap { $0 as? NSTableView }.first)
    refreshedTable.deselectAll(nil)
    refreshedTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    refreshedTable.delegate?.tableViewSelectionDidChange?(
      Notification(name: NSTableView.selectionDidChangeNotification, object: refreshedTable))
    await settle(state, host: host)
    try press("Delete Selected", in: host)
    await settle(state, host: host)
    XCTAssertTrue(
      state.historyPage.entries.isEmpty, "Delete feedback: \(state.historyError ?? "none")")
    XCTAssertEqual(state.recentlyDeletedHistory.count, 1)
    let tabs = try XCTUnwrap(nativeViews(host).compactMap { $0 as? NSSegmentedControl }.first)
    tabs.selectedSegment = 2
    _ = tabs.sendAction(tabs.action, to: tabs.target)
    await settle(state, host: host)
    let deletedTable = try XCTUnwrap(nativeViews(host).compactMap { $0 as? NSTableView }.first)
    deletedTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    deletedTable.delegate?.tableViewSelectionDidChange?(
      Notification(name: NSTableView.selectionDidChangeNotification, object: deletedTable))
    await settle(state, host: host)
    try press("Recover Selected", in: host)
    await settle(state, host: host)
    XCTAssertTrue(state.recentlyDeletedHistory.isEmpty)
    XCTAssertEqual(state.historyPage.entries.first?.title, "Reading notes")
    try await store.close()
  }

  func testRenderedHistoryDeleteWithoutAnEditorSheet() async throws {
    let store = try await CoreDataStore.inMemory()
    let state = AppState(
      repository: TimerCoreDataRepository(store: store), notifications: RecordingNotifications())
    await state.create(command: "stopwatch reading")
    _ = await state.complete(try XCTUnwrap(state.displayedTimer?.id))
    state.historyControls.allTime = true
    let host = NSHostingView(rootView: HistoryView(state: state))
    let window = mount(host, size: NSSize(width: 700, height: 520))
    defer { window.close() }
    await settle(state, host: host)
    let table = try XCTUnwrap(nativeViews(host).compactMap { $0 as? NSTableView }.first)
    table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    table.delegate?.tableViewSelectionDidChange?(
      Notification(name: NSTableView.selectionDidChangeNotification, object: table))
    await settle(state, host: host)
    try press("Delete Selected", in: host)
    await settle(state, host: host)
    XCTAssertTrue(state.historyPage.entries.isEmpty)
    XCTAssertNil(state.historyError)
    try await store.close()
  }

  func testRenderedHistoryDeleteAllConfirmationAndCancel() async throws {
    let store = try await CoreDataStore.inMemory()
    let state = AppState(
      repository: TimerCoreDataRepository(store: store), notifications: RecordingNotifications())
    await state.create(command: "stopwatch reading")
    _ = await state.complete(try XCTUnwrap(state.displayedTimer?.id))
    state.historyControls.allTime = true
    let host = NSHostingView(rootView: HistoryView(state: state))
    let window = mount(host, size: NSSize(width: 700, height: 520))
    defer { window.close() }
    await settle(state, host: host)
    try press("Delete All", in: host)
    let cancelSheet = try await attachedSheet(window)
    try press("Cancel", in: try XCTUnwrap(cancelSheet.contentView))
    await settle(state, host: host)
    XCTAssertEqual(state.historyPage.entries.count, 1)
    XCTAssertNil(window.attachedSheet)
    try press("Delete All", in: host)
    let confirmation = try await attachedSheet(window)
    try press("Delete All", in: try XCTUnwrap(confirmation.contentView))
    await settle(state, host: host)
    XCTAssertTrue(state.historyPage.entries.isEmpty)
    XCTAssertEqual(state.recentlyDeletedHistory.count, 1)
    try await store.close()
  }

  func testRenderedReportsUpdateAndEmptyRangeAction() async throws {
    let store = try await CoreDataStore.inMemory()
    let state = AppState(
      repository: TimerCoreDataRepository(store: store), notifications: RecordingNotifications())
    let host = NSHostingView(rootView: ReportsView(state: state))
    let window = mount(host, size: NSSize(width: 760, height: 680))
    defer { window.close() }
    await settle(state, host: host)
    try press("Choose last 30 days", in: host)
    await settle(state, host: host)
    XCTAssertNil(state.reportsError)
    await state.create(command: "stopwatch reading")
    _ = await state.complete(try XCTUnwrap(state.displayedTimer?.id))
    try press("Update", in: host)
    await settle(state, host: host)
    XCTAssertEqual(state.reportEntries.count, 1)
    XCTAssertEqual(nativeViews(host).compactMap { $0 as? NSTableView }.count, 2)
    try await store.close()
  }

  func testStoppedTimerRefreshesAlreadyOpenHistoryAndReports() async throws {
    let store = try await CoreDataStore.inMemory()
    let state = AppState(
      repository: TimerCoreDataRepository(store: store), notifications: RecordingNotifications())
    await state.loadHistory()
    await state.loadReports(from: nil, through: nil)
    await state.create(command: "25m Focus")
    let id = try XCTUnwrap(state.activeTimers.first?.id)
    let success = await state.cancel(id)
    XCTAssertTrue(success)
    XCTAssertEqual(state.historyPage.entries.first?.timerID, id)
    XCTAssertEqual(state.reportEntries.first?.timerID, id)
    try await store.close()
  }

  func testFinishingStopwatchRefreshesAlreadyOpenHistoryAndReports() async throws {
    let store = try await CoreDataStore.inMemory()
    let state = AppState(
      repository: TimerCoreDataRepository(store: store), notifications: RecordingNotifications())
    await state.loadHistory()
    await state.loadReports(from: nil, through: nil)
    await state.create(command: "stopwatch reading")
    let id = try XCTUnwrap(state.activeTimers.first?.id)
    let success = await state.complete(id)
    XCTAssertTrue(success)
    XCTAssertEqual(state.historyPage.entries.first?.timerID, id)
    XCTAssertEqual(state.reportEntries.first?.timerID, id)
    try await store.close()
  }

  func testPopoverPauseKeepsResumeAndStopAvailable() async throws {
    let store = try await CoreDataStore.inMemory()
    let state = AppState(
      repository: TimerCoreDataRepository(store: store), notifications: RecordingNotifications())
    await state.create(command: "25m Focus")
    let id = try XCTUnwrap(state.activeTimers.first?.id)
    let host = NSHostingView(
      rootView: MenuBarPopoverView(state: state, openSettings: {}, openTimers: {}, quit: {}))
    let window = mount(host, size: NSSize(width: 320, height: 300))
    defer { window.close() }
    try await Task.sleep(for: .milliseconds(100))
    host.layoutSubtreeIfNeeded()
    try press("Pause", in: host)
    await settle(state, host: host)
    XCTAssertEqual(state.activeTimers.first?.state, .paused)
    try press("Resume", in: host)
    await settle(state, host: host)
    XCTAssertEqual(state.activeTimers.first?.state, .running)
    try press("Stop", in: host)
    await settle(state, host: host)
    let saved = try await TimerCoreDataRepository(store: store).timer(id: id)
    XCTAssertEqual(saved.state, .cancelled)
    try await store.close()
  }

  func testPopoverShowsInvalidEntryFeedbackAndFreshExamples() async throws {
    let state = AppState(repository: RecordingRepository(), notifications: RecordingNotifications())
    let host = NSHostingView(
      rootView: MenuBarPopoverView(state: state, openSettings: {}, openTimers: {}, quit: {}))
    let window = mount(host, size: NSSize(width: 320, height: 300))
    defer { window.close() }
    XCTAssertTrue(try visibleText(in: host).contains("25m focus"))
    state.quickEntryText = "wrong"
    try press("Start", in: host)
    await settle(state, host: host)
    let error = try XCTUnwrap(state.inlineError)
    let text = try visibleText(in: host)
    XCTAssertTrue(
      text.contains("Start with a duration"), "Missing feedback: \(error); visible: \(text)")
    XCTAssertTrue(state.activeTimers.isEmpty)
  }

  func testPopoverCanOpenMainWindowAndNavigateToEveryScreen() async throws {
    let state = AppState(repository: RecordingRepository(), notifications: RecordingNotifications())
    let controller = StatusBarController(state: state)
    defer { controller.shutdown() }
    controller.open()
    let hosting = try XCTUnwrap(
      controller.popoverForTesting.contentViewController as? NSHostingController<AnyView>)
    controller.close()
    let root = NSHostingView(rootView: hosting.rootView)
    let fixture = mount(root, size: NSSize(width: 320, height: 300))
    defer { fixture.close() }
    root.layoutSubtreeIfNeeded()
    try press("Open window", in: root)
    await settle(state, host: root)
    let main = try XCTUnwrap(NSApp.windows.first { $0.title == "TopTimer" && $0.isVisible })
    let content = try XCTUnwrap(main.contentView)
    content.layoutSubtreeIfNeeded()
    let navigation = try XCTUnwrap(
      main.toolbar?.items.compactMap { $0.view as? NSPopUpButton }.first)
    let menu = try XCTUnwrap(navigation.menu)
    for destination in TopTimerWindow.allCases {
      let index = try XCTUnwrap(
        menu.items.firstIndex {
          $0.title == (destination == .now ? "Main window" : destination.title)
        })
      menu.performActionForItem(at: index)
      await settle(state, host: content)
      XCTAssertTrue(NSApp.windows.contains { $0.title == destination.title && $0.isVisible })
    }
    await state.operations.drain()
  }

  private func mount<V: View>(_ host: NSHostingView<V>, size: NSSize) -> NSWindow {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.regular)
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .resizable],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: .aqua)
    window.contentView = host
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    host.layoutSubtreeIfNeeded()
    return window
  }

  private func settle(_ state: AppState, host: NSView) async {
    for _ in 0..<100 {
      if state.operations.pendingCount == 0 { break }
      try? await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertEqual(state.operations.pendingCount, 0)
    try? await Task.sleep(for: .milliseconds(30))
    host.layoutSubtreeIfNeeded()
  }

  private func find(_ label: String, in root: NSView) -> (any NSAccessibilityProtocol)? {
    var queue: [any NSAccessibilityProtocol] = [root]
    var visited = Set<ObjectIdentifier>()
    for _ in 0..<2000 {
      guard !queue.isEmpty else { break }
      let node = queue.removeFirst()
      guard visited.insert(ObjectIdentifier(node)).inserted else { continue }
      if node.accessibilityLabel() == label || node.accessibilityTitle() == label
        || (node as? NSButton)?.title == label || (node as? NSTextField)?.stringValue == label
        || (node as? NSView)?.toolTip == label
      {
        return node
      }
      queue.append(
        contentsOf: (node.accessibilityChildren() ?? []).compactMap {
          $0 as? any NSAccessibilityProtocol
        })
      if let view = node as? NSView { queue.append(contentsOf: view.subviews) }
    }
    return nil
  }

  private func press(_ label: String, in root: NSView, occurrence: Int = 0) throws {
    root.window?.makeKeyAndOrderFront(nil)
    if occurrence == 0, let node = find(label, in: root) {
      if let button = node as? NSButton {
        button.performClick(nil)
        return
      }
      if node.accessibilityPerformPress() { return }
      let frame = node.accessibilityFrame()
      if frame.width > 0, frame.height > 0, let window = root.window {
        let location = window.convertFromScreen(frame)
        try sendClick(at: NSPoint(x: location.midX, y: location.midY), in: window)
        return
      }
    }
    // SwiftUI draws some buttons without exposing native NSButton children in XCTest.
    // Locate their rendered labels and send real mouse events instead of calling closures.
    let observations = try recognizedText(in: root)
    root.layoutSubtreeIfNeeded()
    root.displayIfNeeded()
    let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    let match = try XCTUnwrap(
      observations.filter {
        $0.topCandidates(1).first?.string.lowercased()
          .trimmingCharacters(in: CharacterSet(charactersIn: ".… "))
          .hasSuffix(label.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".… ")))
          == true
      }.dropFirst(occurrence).first, "Missing visible control: \(label); visible text: \(text)")
    let candidate = try XCTUnwrap(match.topCandidates(1).first)
    let range = try XCTUnwrap(candidate.string.range(of: label, options: .caseInsensitive))
    let rect = try candidate.boundingBox(for: range)?.boundingBox ?? match.boundingBox
    let point = NSPoint(
      x: root.bounds.width * rect.midX,
      y: root.bounds.height * (root.isFlipped ? 1 - rect.midY : rect.midY))
    let window = try XCTUnwrap(root.window)
    if let button = nativeViews(root).compactMap({ $0 as? NSButton }).first(where: {
      $0.convert($0.bounds, to: root).contains(point)
    }) {
      button.performClick(nil)
      return
    }
    try sendClick(at: root.convert(point, to: nil), in: window)
  }

  private func sendClick(at location: NSPoint, in window: NSWindow) throws {
    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
      let event = try XCTUnwrap(
        NSEvent.mouseEvent(
          with: type, location: location,
          modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
          windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
          pressure: 1))
      window.sendEvent(event)
      RunLoop.main.run(until: Date().addingTimeInterval(0.03))
    }
  }

  private func visibleText(in root: NSView) throws -> String {
    try recognizedText(in: root).compactMap { $0.topCandidates(1).first?.string }.joined(
      separator: " ")
  }

  private func nativeViews(_ root: NSView) -> [NSView] {
    [root] + root.subviews.flatMap(nativeViews)
  }

  private func attachedSheet(_ window: NSWindow) async throws -> NSWindow {
    for _ in 0..<100 {
      if let sheet = window.attachedSheet { return sheet }
      try await Task.sleep(for: .milliseconds(10))
    }
    return try XCTUnwrap(window.attachedSheet)
  }

  private func menuAction(_ title: String, in host: NSView) throws {
    let popup = try XCTUnwrap(nativeViews(host).compactMap { $0 as? NSPopUpButton }.first)
    let trigger = Timer(timeInterval: 0.1, repeats: false) { _ in
      MainActor.assumeIsolated {
        guard let menu = popup.menu else {
          XCTFail("Missing action menu")
          return
        }
        defer { menu.cancelTracking() }
        guard let item = menu.items.first(where: { $0.title == title }) else {
          XCTFail("Missing action \(title)")
          return
        }
        menu.performActionForItem(at: menu.index(of: item))
      }
    }
    RunLoop.main.add(trigger, forMode: .eventTracking)
    RunLoop.main.add(trigger, forMode: .common)
    popup.performClick(nil)
  }

  private func recognizedText(in root: NSView) throws -> [VNRecognizedTextObservation] {
    root.layoutSubtreeIfNeeded()
    let bitmap = try XCTUnwrap(root.bitmapImageRepForCachingDisplay(in: root.bounds))
    root.cacheDisplay(in: root.bounds, to: bitmap)
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    request.recognitionLanguages = ["en-US"]
    try VNImageRequestHandler(cgImage: try XCTUnwrap(bitmap.cgImage)).perform([request])
    return request.results ?? []
  }
}
