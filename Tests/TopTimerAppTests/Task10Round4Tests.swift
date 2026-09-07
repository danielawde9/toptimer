import SwiftUI
import TopTimerDomain
import TopTimerPersistence
import XCTest

@testable import TopTimerApp

@MainActor
final class Task10Round4Tests: XCTestCase {
  func testRestoredRunningCountdownReschedulesItsDurableDeadline() async throws {
    let store = try await CoreDataStore.inMemory()
    let notifications = RecordingNotifications()
    let state = AppState(
      repository: TimerCoreDataRepository(store: store), notifications: notifications)
    await state.create(command: "5m Restore")
    let id = try XCTUnwrap(state.activeTimers.first?.id)
    _ = await state.softDelete(id)
    _ = await state.restore(id)
    let operations = await notifications.recordedOperations()
    XCTAssertEqual(operations, ["schedule", "cancel", "schedule"])
    try await store.close()
  }
  func testLocalCatalogLoadsImportedIdentityAndRejectsLinksAndOtherFiles() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data().write(to: directory.appendingPathComponent("saved.wav"))
    try Data().write(to: directory.appendingPathComponent("notes.txt"))
    try FileManager.default.createSymbolicLink(
      at: directory.appendingPathComponent("link.wav"),
      withDestinationURL: directory.appendingPathComponent("saved.wav"))
    let catalog = try SoundCatalog.local(importedDirectory: directory)
    XCTAssertTrue(catalog.names.contains("saved.wav"))
    XCTAssertTrue(catalog.names.contains("Glass"))
    XCTAssertFalse(catalog.names.contains("link.wav"))
    XCTAssertFalse(catalog.names.contains("notes.txt"))
  }
  func testCatalogRefreshUsesImportedIdentityAndRetainsPreviousOnFailure() throws {
    let catalog = SoundCatalog(names: ["Glass", "imported.wav"])
    let state = SoundCatalogState()
    state.refresh { catalog }
    XCTAssertEqual(state.catalog, catalog)
    state.refresh { throw CocoaError(.fileReadNoPermission) }
    XCTAssertEqual(state.catalog, catalog)
    XCTAssertEqual(
      state.error, "Could not load alert sounds. Your previous selection is unchanged.")
  }
  func testCalendarDraftRejectsInvalidTimeAndWeekdays() throws {
    var draft = EditorDraft()
    draft.recurrenceMode = .daily
    draft.hour = 24
    XCTAssertEqual(
      draft.validationError(), "Choose an hour from 0 to 23 and a minute from 0 to 59.")
    draft.hour = 9
    draft.recurrenceMode = .weekly
    draft.weekday = 0
    XCTAssertEqual(draft.validationError(), "Choose a weekday from Sunday to Saturday.")
    draft.recurrenceMode = .selectedWeekdays
    draft.selectedWeekdays = [8]
    XCTAssertEqual(draft.validationError(), "Choose weekdays from Sunday to Saturday.")
  }

  func testSoundCatalogBoundsAndPreservesDraftOnUnavailableChoice() throws {
    let catalog = SoundCatalog(names: (0..<150).map { "Sound \($0)" })
    XCTAssertEqual(catalog.names.count, 100)
    XCTAssertGreaterThan(SoundCatalog.builtIn.names.count, 1)
    var draft = EditorDraft()
    draft.alertName = "missing.wav"
    let before = draft
    XCTAssertThrowsError(try draft.configuration(catalog: catalog))
    XCTAssertEqual(draft, before)
  }

  func testRowTimingForRunningPausedCompletedAndStopwatch() throws {
    let now = Date(timeIntervalSince1970: 1_000)
    var timer = try TimerItem.countdown(title: "Tea", duration: 120, createdAt: now)
    try timer.start(at: now)
    XCTAssertEqual(
      TimerRowTiming(timer: timer, at: now.addingTimeInterval(10)).text, "01:50 remaining")
    try timer.pause(at: now.addingTimeInterval(10))
    XCTAssertEqual(
      TimerRowTiming(timer: timer, at: now.addingTimeInterval(90)).text, "01:50 remaining")
    try timer.resume(at: now.addingTimeInterval(90))
    try timer.complete(at: now.addingTimeInterval(200))
    XCTAssertEqual(
      TimerRowTiming(timer: timer, at: now.addingTimeInterval(201)).text, "00:00 remaining")
    var watch = try TimerItem.stopwatch(title: "Watch", createdAt: now)
    try watch.start(at: now)
    XCTAssertEqual(
      TimerRowTiming(timer: watch, at: now.addingTimeInterval(65)).text, "01:05 elapsed")
    try watch.pause(at: now.addingTimeInterval(65))
    XCTAssertEqual(
      TimerRowTiming(timer: watch, at: now.addingTimeInterval(100)).text, "01:05 elapsed")
  }

  func testDeletedTimersAreBoundedPublishedAndRestoredWithoutStaleOverwrite() async throws {
    let store = try await CoreDataStore.inMemory()
    let repository = TimerCoreDataRepository(store: store)
    let now = Date(timeIntervalSince1970: 1_000)
    let timer = try TimerItem.countdown(title: "Recover", duration: 60, createdAt: now)
    _ = try await repository.insert(timer)
    let state = AppState(
      repository: repository, notifications: RecordingNotifications(), now: { now })
    await state.load()
    let deleted = await state.softDelete(timer.id)
    XCTAssertTrue(deleted)
    XCTAssertEqual(state.deletedTimers.map(\.id), [timer.id])
    let stale = try await repository.timer(id: timer.id)
    let restored = await state.restore(timer.id)
    XCTAssertTrue(restored)
    XCTAssertTrue(state.deletedTimers.isEmpty)
    XCTAssertEqual(state.activeTimers.map(\.id), [timer.id])
    var overwrite = stale
    try overwrite.updateMetadata(title: "Stale", details: "", tags: [])
    do {
      try await repository.update(overwrite)
      XCTFail("Stale update accepted")
    } catch { XCTAssertEqual(error as? TimerRepositoryError, .staleTimerUpdate) }
    for index in 0..<102 {
      let item = try TimerItem.countdown(title: "Deleted \(index)", duration: 60, createdAt: now)
      _ = try await repository.insert(item)
      try await repository.softDelete(item.id, at: now)
    }
    let items = try await repository.deleted(limit: 1000)
    XCTAssertEqual(items.count, 100)
    try await store.close()
    let failed = await state.softDelete(timer.id)
    XCTAssertFalse(failed)
    XCTAssertTrue(state.deletedTimers.isEmpty)
  }
}
