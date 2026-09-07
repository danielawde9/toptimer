import AVFAudio
import UserNotifications
import XCTest

@testable import TopTimerSystem

final class NotificationSoundBoundaryTests: XCTestCase {
  func testConcurrentPreparationsCannotExceedCacheCapacity() async throws {
    let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: output) }
    for index in 0..<99 {
      try Data().write(to: output.appendingPathComponent("TopTimer-existing-\(index).caf"))
    }
    let preparer = LocalNotificationSoundPreparer(notificationDirectory: output)
    let successes = await withTaskGroup(of: Bool.self) { group in
      for name in ["Glass", "Ping"] {
        group.addTask {
          do {
            _ = try await preparer.prepare(name: name)
            return true
          } catch { return false }
        }
      }
      var count = 0
      for await success in group { if success { count += 1 } }
      return count
    }
    XCTAssertEqual(successes, 1)
    XCTAssertLessThanOrEqual(
      try FileManager.default.contentsOfDirectory(atPath: output.path).count, 100)
  }
  func testPreparerRejectsOverlongAudioAndNeverOverwritesExistingNotificationSound() async throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let imported = base.appendingPathComponent("Imported")
    let output = base.appendingPathComponent("Sounds")
    try FileManager.default.createDirectory(at: imported, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: base) }
    let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1))
    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8_000))
    buffer.frameLength = 8_000
    var settings = format.settings
    settings[AVLinearPCMIsNonInterleaved] = false
    do {
      let writer = try AVAudioFile(
        forWriting: imported.appendingPathComponent("long.wav"), settings: settings)
      for _ in 0..<31 { try writer.write(from: buffer) }
    }
    let preparer = LocalNotificationSoundPreparer(
      importedDirectory: imported, notificationDirectory: output)
    do {
      _ = try await preparer.prepare(name: "long.wav")
      XCTFail("Overlong notification sound accepted")
    } catch { XCTAssertEqual(error as? NotificationSoundError, .unsupportedAudio) }
    let first = try await preparer.prepare(name: "Glass")
    let file = output.appendingPathComponent(try XCTUnwrap(first))
    let before = try Data(contentsOf: file)
    let second = try await preparer.prepare(name: "Glass")
    XCTAssertEqual(first, second)
    XCTAssertEqual(try Data(contentsOf: file), before)
  }
  func testPreparedNamedSoundReachesActualUNContent() async throws {
    let center = SoundRequestCenter()
    let controller = NotificationController(center: center)
    _ = try await controller.schedule(
      timerID: UUID(), title: "Tea", details: "", fireDate: .now, alertName: "Glass")
    let captured = await center.lastRequest()
    let request = try XCTUnwrap(captured)
    XCTAssertEqual(request.soundName, "Glass")
    let content = UNNotificationCenterAdapter.content(
      for: request, preparedSoundName: "TopTimer-Glass.caf")
    XCTAssertEqual(
      content.sound, UNNotificationSound(named: UNNotificationSoundName("TopTimer-Glass.caf")))
    XCTAssertNotEqual(content.sound, .default)
  }

  func testLocalPreparerProducesBoundedPlayableCAFForBuiltInAndImportedSound() async throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let imported = base.appendingPathComponent("Imported")
    let output = base.appendingPathComponent("Library/Sounds")
    try FileManager.default.createDirectory(at: imported, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: base) }
    let source = imported.appendingPathComponent("chosen.wav")
    let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1))
    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8_000))
    buffer.frameLength = 8_000
    var settings = format.settings
    settings[AVLinearPCMIsNonInterleaved] = false
    do {
      let writer = try AVAudioFile(forWriting: source, settings: settings)
      try writer.write(from: buffer)
    }
    let preparer = LocalNotificationSoundPreparer(
      importedDirectory: imported, notificationDirectory: output)
    for name in ["Glass", "chosen.wav"] {
      let result = try await preparer.prepare(name: name)
      let prepared = try XCTUnwrap(result)
      XCTAssertEqual(URL(fileURLWithPath: prepared).pathExtension, "caf")
      let audio = try AVAudioFile(forReading: output.appendingPathComponent(prepared))
      XCTAssertGreaterThan(audio.length, 0)
      XCTAssertLessThanOrEqual(Double(audio.length) / audio.processingFormat.sampleRate, 30)
    }
    do {
      _ = try await preparer.prepare(name: "../secret.wav")
      XCTFail("Traversal accepted")
    } catch { XCTAssertEqual(error as? NotificationSoundError, .invalidIdentity) }
    try FileManager.default.createSymbolicLink(
      at: imported.appendingPathComponent("link.wav"), withDestinationURL: source)
    do {
      _ = try await preparer.prepare(name: "link.wav")
      XCTFail("Link accepted")
    } catch { XCTAssertNotNil(error as? AlertSoundError) }
  }
}

actor SoundRequestCenter: NotificationCenterClient {
  var request: NotificationRequest?
  func lastRequest() -> NotificationRequest? { request }
  func authorizationStatus() async -> NotificationAuthorizationStatus { .authorized }
  func requestAuthorization() async throws -> Bool { true }
  func setCategories(_ categories: [NotificationCategory]) async {}
  func pendingRequests(limit: Int) async -> [PendingNotification] { [] }
  func add(_ request: NotificationRequest) async throws { self.request = request }
  func removePendingRequests(identifiers: [String]) async {}
}
