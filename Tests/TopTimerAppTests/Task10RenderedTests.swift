import AppKit
import SwiftUI
import TopTimerDomain
import TopTimerPersistence
import XCTest

@testable import TopTimerApp

@MainActor
final class Task10RenderedTests: XCTestCase {
  func testEditorDoesNotOfferImmutableKindChanges() {
    let host = NSHostingView(
      rootView: TimerEditorView(draft: .constant(EditorDraft())) { _ in false })
    let window = mount(host)
    defer { window.close() }
    XCTAssertFalse(
      accessibilityNodes(host).compactMap { $0 as? NSPopUpButton }.contains {
        $0.itemTitles.contains("Stopwatch")
      })
  }
  func testSelectedWeekdaysRendersSevenChoices() {
    var draft = EditorDraft()
    draft.recurrenceMode = .selectedWeekdays
    draft.selectedWeekdays = [2, 4]
    let host = NSHostingView(rootView: TimerEditorView(draft: .constant(draft)) { _ in false })
    let window = mount(host)
    defer { window.close() }
    XCTAssertEqual(
      accessibilityNodes(host).compactMap { $0 as? NSButton }.filter { !($0 is NSPopUpButton) }
        .count, 7)
  }
  func testRenderedDurationInputRejectsNonNumericText() throws {
    var draft = EditorDraft()
    let host = NSHostingView(
      rootView: TimerEditorView(draft: Binding(get: { draft }, set: { draft = $0 })) { _ in false })
    let window = mount(host)
    defer { window.close() }
    let field = try XCTUnwrap(
      accessibilityNodes(host).compactMap { $0 as? NSTextField }.first { $0.stringValue == "300" })
    field.stringValue = "abc"
    field.delegate?.controlTextDidChange?(
      Notification(name: NSControl.textDidChangeNotification, object: field))
    XCTAssertEqual(draft.validationError(), "Duration must be between 1 second and 1 year.")
    field.stringValue = "12oops"
    field.delegate?.controlTextDidChange?(
      Notification(name: NSControl.textDidChangeNotification, object: field))
    XCTAssertEqual(draft.validationError(), "Duration must be between 1 second and 1 year.")
  }
  func testTimerRowKeepsKeyboardActionControlMountedWithoutHover() async {
    let state = AppState(repository: RecordingRepository(), notifications: RecordingNotifications())
    await state.create(command: "5m Tea")
    let host = NSHostingView(rootView: TimerListView(state: state))
    let window = mount(host)
    defer { window.close() }
    let menus = accessibilityNodes(host).compactMap { $0 as? NSPopUpButton }
    XCTAssertEqual(menus.count, 1)
    XCTAssertGreaterThanOrEqual(menus.first?.frame.width ?? 0, 28)
    if let menu = menus.first {
      let frame = menu.frame
      XCTAssertTrue(window.makeFirstResponder(menu))
      host.layoutSubtreeIfNeeded()
      XCTAssertEqual(menu.frame, frame)
    }
  }

  func testRecentlyDeletedCollectionOffersWorkingRestore() async throws {
    let store = try await CoreDataStore.inMemory()
    let state = AppState(
      repository: TimerCoreDataRepository(store: store), notifications: RecordingNotifications())
    await state.create(command: "5m Recover")
    let id = try XCTUnwrap(state.activeTimers.first?.id)
    _ = await state.softDelete(id)
    let host = NSHostingView(rootView: TimerListView(state: state, recentlyDeleted: true))
    let window = mount(host)
    defer { window.close() }
    let segment = try XCTUnwrap(
      accessibilityNodes(host).compactMap { $0 as? NSSegmentedControl }.first)
    XCTAssertEqual(segment.label(forSegment: 1), "Recently Deleted")
    XCTAssertEqual(segment.selectedSegment, 1)
    let buttons = accessibilityNodes(host).compactMap { $0 as? NSButton }
    XCTAssertEqual(buttons.count, 1)
    let restore = try XCTUnwrap(buttons.first)
    restore.performClick(nil)
    for _ in 0..<100 {
      if state.deletedTimers.isEmpty { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertTrue(state.deletedTimers.isEmpty)
    XCTAssertEqual(state.activeTimers.first?.id, id)
    try await store.close()
  }
  func testEditorRendersDurationAndRecurrenceInputs() {
    var draft = EditorDraft()
    draft.recurrenceMode = .weekly
    let host = NSHostingView(rootView: TimerEditorView(draft: .constant(draft)) { _ in false })
    let window = mount(host)
    defer { window.close() }
    let nodes = accessibilityNodes(host)
    let fields = nodes.compactMap { $0 as? NSTextField }
    XCTAssertEqual(fields.count, 6, "Title, details, tags, duration, hour, minute")
    XCTAssertEqual(
      nodes.compactMap { $0 as? NSPopUpButton }.count, 3,
      "Recurrence, weekday, sound; kind is read only")
  }

  func testQuickToolbarHasExactlyFourAccessibleControlsWithRunningTimer() async {
    let state = AppState(repository: RecordingRepository(), notifications: RecordingNotifications())
    await state.create(command: "5m Tea")
    let host = NSHostingView(rootView: QuickEntryView(state: state, showingList: .constant(false)))
    let window = mount(host)
    defer { window.close() }
    let buttons = accessibilityNodes(host).compactMap { $0 as? NSButton }
    XCTAssertEqual(buttons.count, 4)
    for button in buttons {
      XCTAssertGreaterThanOrEqual(button.frame.width, 28)
      XCTAssertGreaterThanOrEqual(button.frame.height, 28)
    }
  }

  private func mount<V: View>(_ host: NSHostingView<V>, name: String = #function) -> NSWindow {
    _ = NSApplication.shared
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 400, height: 600), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(
      named: ProcessInfo.processInfo.environment["TOPTIMER_SNAPSHOT_APPEARANCE"] == "dark"
        ? .darkAqua : .aqua)
    host.wantsLayer = true
    host.layer?.backgroundColor =
      ProcessInfo.processInfo.environment["TOPTIMER_SNAPSHOT_APPEARANCE"] == "dark"
      ? NSColor(calibratedWhite: 0.14, alpha: 1).cgColor : NSColor.white.cgColor
    window.contentView = host
    window.orderFront(nil)
    host.layoutSubtreeIfNeeded()
    if let directory = ProcessInfo.processInfo.environment["TOPTIMER_SNAPSHOT_DIRECTORY"],
      let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)
    {
      host.cacheDisplay(in: host.bounds, to: bitmap)
      do {
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try bitmap.representation(using: .png, properties: [:])?.write(
          to: url.appendingPathComponent(name + ".png"))
      } catch { XCTFail("Could not save rendered proof: \(error)") }
    }
    return window
  }

  private func accessibilityNodes(_ root: any NSAccessibilityProtocol)
    -> [any NSAccessibilityProtocol]
  {
    var result: [any NSAccessibilityProtocol] = []
    var queue: [any NSAccessibilityProtocol] = [root]
    for _ in 0..<500 {
      guard !queue.isEmpty else { break }
      let node = queue.removeFirst()
      result.append(node)
      if let view = node as? NSView {
        queue.append(contentsOf: view.subviews)
      } else {
        queue.append(
          contentsOf: (node.accessibilityChildren() ?? []).compactMap {
            $0 as? any NSAccessibilityProtocol
          })
      }
    }
    return result
  }
}
