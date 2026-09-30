import AppKit
import SwiftUI
import TopTimerDomain
import TopTimerPersistence
import XCTest

@testable import TopTimerApp

@MainActor final class ScreenSnapshotTests: XCTestCase {
  func testCaptureImplementedScreensWithSyntheticData() async throws {
    guard let path = ProcessInfo.processInfo.environment["TOPTIMER_SCREENSHOTS"] else {
      throw XCTSkip("Set TOPTIMER_SCREENSHOTS to save native screen previews")
    }
    let directory = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let store = try await CoreDataStore.inMemory()
    let repository = TimerCoreDataRepository(store: store)
    let date = Date(timeIntervalSince1970: floor(Date.now.timeIntervalSince1970))
    for (title, duration, elapsed, tags) in [
      ("Focus", 1500.0, 378.0, ["work"]), ("Tea", 1800.0, 345.0, ["break"]),
    ] {
      var timer = try TimerItem.countdown(
        title: title, duration: duration, tags: tags, createdAt: date.addingTimeInterval(-elapsed))
      try timer.start(at: timer.createdAt)
      _ = try await repository.insert(timer)
    }
    var reading = try TimerItem.stopwatch(
      title: "Reading", tags: ["books"], createdAt: date.addingTimeInterval(-728))
    try reading.start(at: reading.createdAt)
    _ = try await repository.insert(reading)
    try reading.pause(at: date)
    try await repository.update(reading)
    for day in 1...7 {
      let start = date.addingTimeInterval(-Double(day) * 86400)
      var timer = try TimerItem.countdown(
        title: "Focus", duration: Double(day) * 300, tags: ["work"], createdAt: start)
      try timer.start(at: start)
      _ = try await repository.insert(timer)
      let outcome = try await repository.complete(
        timer.id, at: start.addingTimeInterval(Double(day) * 300))
      var completed = outcome.completed
      try completed.acknowledge(at: start.addingTimeInterval(Double(day) * 300 + 1))
      try await repository.update(completed)
    }
    let state = AppState(repository: repository, notifications: RecordingNotifications())
    await state.load()
    state.dismissStartupRecovery()
    state.historyControls.allTime = true
    await state.applyHistoryControls()
    await state.loadReports(from: nil, through: nil)

    let idle = AppState(repository: RecordingRepository(), notifications: RecordingNotifications())
    let paused = AppState(
      repository: RecordingRepository(), notifications: RecordingNotifications())
    await paused.create(command: "25m Focus")
    _ = await paused.pause(try XCTUnwrap(paused.activeTimers.first?.id))
    let sequence = AppState(
      repository: RecordingRepository(), notifications: RecordingNotifications())
    _ = await sequence.startSequence(
      steps: [
        SequenceStep(title: "Task 1", minutes: 15), SequenceStep(title: "Task 2", minutes: 15),
        SequenceStep(title: "Task 3", minutes: 30),
      ], repeats: true)
    var draft = EditorDraft()
    draft.title = "Focus"
    draft.details = "Deep work session"
    draft.tags = ["work", "study"]
    draft.duration = 1500
    draft.recurrenceMode = .weekdays

    for dark in [false, true] {
      let suffix = dark ? "dark" : "light"
      let screens: [(String, AnyView, NSSize)] = [
        (
          "popover-idle",
          AnyView(
            MenuBarPopoverView(
              state: idle, openSettings: {}, openTimers: {}, quit: {}, openNow: {},
              openSequences: {})
          ), .init(width: 320, height: 300)
        ),
        (
          "popover-running",
          AnyView(
            MenuBarPopoverView(
              state: state, openSettings: {}, openTimers: {}, quit: {}, openNow: {},
              openSequences: {})),
          .init(width: 320, height: 300)
        ),
        (
          "popover-paused",
          AnyView(
            MenuBarPopoverView(
              state: paused, openSettings: {}, openTimers: {}, quit: {}, openNow: {},
              openSequences: {})),
          .init(width: 320, height: 300)
        ),
        (
          "now-idle", AnyView(NowView(state: idle)), .init(width: 620, height: 560)
        ),
        (
          "now-active", AnyView(NowView(state: state)),
          .init(width: 620, height: 560)
        ),
        (
          "timers",
          AnyView(
            TimerListHost(
              state: state, sounds: SoundCatalogState())), .init(width: 380, height: 420)
        ),
        (
          "history", AnyView(HistoryView(state: state)),
          .init(width: 700, height: 520)
        ),
        ("sequences", AnyView(SequenceView(state: idle)), .init(width: 620, height: 500)),
        (
          "sequences-running", AnyView(SequenceView(state: sequence)),
          .init(width: 620, height: 500)
        ),
        ("reports", AnyView(ReportsView(state: state)), .init(width: 760, height: 680)),
        ("reports-empty", AnyView(ReportsView(state: idle)), .init(width: 760, height: 680)),
        ("history-empty", AnyView(HistoryView(state: idle)), .init(width: 700, height: 520)),
        (
          "settings", AnyView(SettingsView(settings: .constant(.defaults))),
          .init(width: 620, height: 820)
        ),
        (
          "editor", AnyView(TimerEditorView(draft: .constant(draft)) { _ in false }),
          .init(width: 440, height: 520)
        ),
        (
          "shortcut", AnyView(ShortcutCaptureSheet(onCapture: { _ in }, cancel: {})),
          .init(width: 350, height: 180)
        ),
      ]
      for (name, root, size) in screens {
        let host = NSHostingView(rootView: root)
        let window = NSWindow(
          contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .resizable],
          backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(
          host.fittingSize.width, size.width + 1, "\(name) must fit its window")
        try save(host, dark: dark, to: directory.appendingPathComponent("\(name)-\(suffix).png"))
        window.close()
      }
    }
    await state.operations.drain()
    await idle.operations.drain()
    await paused.operations.drain()
    await sequence.operations.drain()
    try await store.close()
  }

  private func save(_ host: NSView, dark: Bool, to url: URL) throws {
    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let raw = try XCTUnwrap(bitmap.cgImage)
    let context = try XCTUnwrap(
      CGContext(
        data: nil, width: raw.width, height: raw.height,
        bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(
      dark
        ? NSColor(calibratedWhite: 0.14, alpha: 1).cgColor
        : NSColor(calibratedWhite: 0.96, alpha: 1).cgColor)
    context.fill(CGRect(x: 0, y: 0, width: raw.width, height: raw.height))
    context.draw(raw, in: CGRect(x: 0, y: 0, width: raw.width, height: raw.height))
    let image = NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage()))
    try XCTUnwrap(image.representation(using: .png, properties: [:])).write(to: url)
  }
}
