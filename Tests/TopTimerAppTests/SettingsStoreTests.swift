import XCTest

@testable import TopTimerApp

final class SettingsStoreTests: XCTestCase {
  func testUnsafeSoundAndIncompleteShortcutPayloadAreRejected() throws {
    let unsafe = Data(
      #"{"version":1,"snoozeSeconds":300,"historyPageSize":100,"alertVolume":1,"defaultAlertName":"../secret"}"#
        .utf8)
    let incomplete = Data(
      #"{"version":1,"snoozeSeconds":300,"historyPageSize":100,"alertVolume":1,"quickKey":17}"#.utf8
    )
    XCTAssertThrowsError(try TopTimerSettingsCodec.decode(unsafe))
    XCTAssertThrowsError(try TopTimerSettingsCodec.decode(incomplete))
  }
  func testRelaunchPreservesBothShortcuts() throws {
    var settings = TopTimerSettings.defaults
    settings.quickEntryShortcut = try .init(keyCode: 17, modifiers: 768)
    settings.pauseResumeShortcut = try .init(keyCode: 35, modifiers: 768)
    XCTAssertEqual(
      try TopTimerSettingsCodec.decode(TopTimerSettingsCodec.encode(settings)), settings)
  }
  func testVersionedCodecNormalizesDecodedValuesAndRejectsOversizedPayload() throws {
    let data = Data(#"{"version":1,"snoozeSeconds":0,"historyPageSize":5000,"alertVolume":2}"#.utf8)
    let decoded = try TopTimerSettingsCodec.decode(data)
    XCTAssertEqual(decoded.snoozeSeconds, 60)
    XCTAssertEqual(decoded.historyPageSize, 200)
    XCTAssertEqual(decoded.alertVolume, 1)
    XCTAssertThrowsError(try TopTimerSettingsCodec.decode(Data(repeating: 0, count: 16_385)))
  }

  func testFailedSavePreservesPreviouslyLoadedSettings() throws {
    let storage = SettingsDataStoreSpy()
    let store = TopTimerSettingsStore(storage: storage)
    try store.save(.defaults)
    storage.failWrites = true
    var changed = TopTimerSettings.defaults
    changed.showsStatusIcon = false
    XCTAssertThrowsError(try store.save(changed))
    XCTAssertEqual(try store.load(), .defaults)
  }
}

private final class SettingsDataStoreSpy: SettingsDataStore {
  var data: Data?
  var failWrites = false
  func read() -> Data? { data }
  func write(_ value: Data) throws {
    if failWrites { throw CocoaError(.fileWriteUnknown) }
    data = value
  }
}
