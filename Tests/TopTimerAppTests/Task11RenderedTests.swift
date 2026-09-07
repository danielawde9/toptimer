import AppKit
import SwiftUI
import TopTimerDomain
import TopTimerPersistence
import XCTest

@testable import TopTimerApp

@MainActor final class Task11RenderedTests: XCTestCase {
  func testReportUsesTwoNativeAccessibleTables() async throws {
    let repo = RecordingRepository()
    let entry = try HistoryEntry(
      timerID: UUID(), occurrenceID: UUID(), title: "Focus", tags: ["work"], kind: .countdown,
      startedAt: .now.addingTimeInterval(-1500), endedAt: .now, elapsedSeconds: 1500,
      completionReason: .finished)
    await repo.setHistoryHandler { _, _, _, _, _ in .init(entries: [entry], nextCursor: nil) }
    let state = AppState(repository: repo, notifications: RecordingNotifications())
    await state.loadReports(from: nil, through: nil)
    let host = NSHostingView(rootView: ReportsView(state: state))
    let window = try mount(host, name: "reports")
    defer { window.close() }
    XCTAssertEqual(descendants(host).compactMap { $0 as? NSTableView }.count, 2)
    await state.operations.drain()
  }

  func testHistoryUsesNativeTableAndSettingsRenderBoundedPickers() async throws {
    let repo = RecordingRepository()
    let entry = try HistoryEntry(
      timerID: UUID(), occurrenceID: UUID(), title: "Focus", tags: ["work"], kind: .countdown,
      startedAt: .now.addingTimeInterval(-1500), endedAt: .now, elapsedSeconds: 1500,
      completionReason: .finished)
    await repo.setHistoryHandler { _, _, _, _, _ in .init(entries: [entry], nextCursor: nil) }
    let state = AppState(repository: repo, notifications: RecordingNotifications())
    await state.loadHistory()
    let history = NSHostingView(rootView: HistoryView(state: state))
    let historyWindow = try mount(history, name: "history")
    defer { historyWindow.close() }
    XCTAssertEqual(descendants(history).compactMap { $0 as? NSTableView }.count, 1)
    let settings = NSHostingView(
      rootView: SettingsView(settings: .constant(.defaults), notificationDenied: true))
    let settingsWindow = try mount(settings, name: "settings")
    defer { settingsWindow.close() }
    XCTAssertEqual(descendants(settings).compactMap { $0 as? NSPopUpButton }.count, 3)
    await state.operations.drain()
  }

  private func descendants(_ root: NSView) -> [NSView] {
    var result: [NSView] = []
    var queue = [root]
    for _ in 0..<1000 {
      guard !queue.isEmpty else { break }
      let node = queue.removeFirst()
      result.append(node)
      queue.append(contentsOf: node.subviews.prefix(100))
    }
    return result
  }

  private func mount<V: View>(_ host: NSHostingView<V>, name: String) throws -> NSWindow {
    _ = NSApplication.shared
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 900, height: 800), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: .aqua)
    host.wantsLayer = true
    host.layer?.backgroundColor = NSColor.white.cgColor
    window.contentView = host
    window.orderFront(nil)
    host.layoutSubtreeIfNeeded()
    if let path = ProcessInfo.processInfo.environment["TOPTIMER_TASK11_PROOF"] {
      let directory = URL(fileURLWithPath: path)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
        to: directory.appendingPathComponent(name + ".png"))
    }
    return window
  }
}
