import AppKit
import SwiftUI
import TopTimerPersistence
import XCTest

@testable import TopTimerApp

@MainActor final class TimerListHostTests: XCTestCase {
  func testRenderedFinishCreatesHistoryReportsAndCSVWithoutDeletingStopwatch() async throws {
    let store = try await CoreDataStore.inMemory()
    let repository = TimerCoreDataRepository(store: store)
    let state = AppState(repository: repository, notifications: RecordingNotifications())
    await state.create(command: "")
    let id = try XCTUnwrap(state.priorityTimer?.id)
    let host = NSHostingView(rootView: TimerListView(state: state))
    let window = mount(host)
    defer { window.close() }
    try clickAction("Finish", in: host)
    await settle(state)
    let timer = try await repository.timer(id: id)
    XCTAssertEqual(timer.state, .completed)
    XCTAssertNil(timer.deletedAt)
    await state.loadHistory()
    await state.loadReports(from: nil, through: nil)
    XCTAssertEqual(state.historyPage.entries.count, 1)
    XCTAssertEqual(state.reportEntries.count, 1)
    var exported = ""
    await state.exportHistory(to: URL(fileURLWithPath: "/unused")) { data, _ in
      exported = String(decoding: data, as: UTF8.self)
    }
    XCTAssertTrue(exported.contains("stopwatch"))
    try await store.close()
  }

  func testBothListHostsPresentAndDismissEditorFromNativeEditAction() async throws {
    for popover in [false, true] {
      let state = AppState(
        repository: RecordingRepository(), notifications: RecordingNotifications())
      await state.create(command: "5m Editable")
      let root: AnyView =
        popover
        ? AnyView(
          PopoverRoot(
            state: state, sounds: SoundCatalogState(), showingList: true, onListChange: { _ in },
            closePopover: {}, openSettings: {}, openTimerList: {}))
        : AnyView(TimerListHost(state: state, sounds: SoundCatalogState()))
      let host = NSHostingView(rootView: root)
      let window = mount(host)
      let otherWindow = mount(
        NSHostingView(rootView: TimerListHost(state: state, sounds: SoundCatalogState())))
      defer { otherWindow.close() }
      try clickAction("Edit", in: host)
      for _ in 0..<100 {
        if window.attachedSheet != nil { break }
        try await Task.sleep(for: .milliseconds(10))
      }
      let sheet = try XCTUnwrap(window.attachedSheet)
      XCTAssertNil(otherWindow.attachedSheet)
      XCTAssertNotNil(state.selectedEditorTimer)
      sheet.contentView?.layoutSubtreeIfNeeded()
      let content = try XCTUnwrap(sheet.contentView)
      XCTAssertTrue(
        nodes(content).compactMap { $0 as? NSTextField }.contains { $0.stringValue == "Editable" })
      if let directory = ProcessInfo.processInfo.environment["TOPTIMER_FINAL_PROOF"],
        let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds)
      {
        content.cacheDisplay(in: content.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])?.write(
          to: URL(fileURLWithPath: directory).appendingPathComponent(
            popover ? "popover-editor.png" : "window-editor.png"))
      }
      sheet.cancelOperation(nil)
      for _ in 0..<100 {
        if state.selectedEditorTimer == nil && window.attachedSheet == nil { break }
        try await Task.sleep(for: .milliseconds(10))
      }
      XCTAssertNil(state.selectedEditorTimer)
      XCTAssertNil(window.attachedSheet)
      window.close()
      await state.operations.drain()
    }
  }

  private func settle(_ state: AppState) async {
    for _ in 0..<100 {
      if state.operations.pendingCount == 0 { return }
      try? await Task.sleep(for: .milliseconds(10))
    }
    XCTFail("Operation did not finish within bounded wait")
  }
  private func clickAction(_ title: String, in host: NSView) throws {
    let popup = try XCTUnwrap(nodes(host).compactMap { $0 as? NSPopUpButton }.first)
    let trigger = Timer(timeInterval: 0.1, repeats: false) { _ in
      MainActor.assumeIsolated {
        guard let menu = popup.menu else {
          XCTFail("Missing menu")
          return
        }
        defer { menu.cancelTracking() }
        XCTAssertTrue(menu.items.contains { $0.title == "Delete" })
        guard let item = menu.items.first(where: { $0.title == title }) else {
          XCTFail("Missing \(title): \(menu.items.map(\.title))")
          return
        }
        menu.performActionForItem(at: menu.index(of: item))
      }
    }
    RunLoop.main.add(trigger, forMode: .eventTracking)
    RunLoop.main.add(trigger, forMode: .common)
    popup.performClick(nil)
  }
  private func mount<V: View>(_ host: NSHostingView<V>) -> NSWindow {
    _ = NSApplication.shared
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 400, height: 600), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.orderFront(nil)
    host.layoutSubtreeIfNeeded()
    return window
  }
  private func nodes(_ root: NSView) -> [NSView] {
    var queue = [root]
    var result: [NSView] = []
    for _ in 0..<500 {
      guard !queue.isEmpty else { break }
      let view = queue.removeFirst()
      result.append(view)
      queue.append(contentsOf: view.subviews.prefix(100))
    }
    return result
  }
}
