import Foundation
import TopTimerSystem

public enum SettingsStoreError: Error, Equatable { case oversized, malformed, unsupportedVersion }

public protocol SettingsDataStore: AnyObject {
  func read() -> Data?
  func write(_ value: Data) throws
}

public final class UserDefaultsSettingsDataStore: SettingsDataStore {
  private let defaults: UserDefaults
  private let key: String
  public init(defaults: UserDefaults = .standard, key: String = "TopTimer.settings.v1") {
    self.defaults = defaults
    self.key = key
  }
  public func read() -> Data? { defaults.data(forKey: key) }
  public func write(_ value: Data) throws { defaults.set(value, forKey: key) }
}

public enum TopTimerSettingsCodec {
  public static let maximumBytes = 16_384
  private struct Payload: Codable {
    let version: Int
    var snoozeSeconds: Double
    var historyPageSize: Int
    var alertVolume: Double
    var showsStatusIcon: Bool?
    var uses24HourTime: Bool?
    var launchesAtLogin: Bool?
    var preventsSleep: Bool?
    var defaultAlertName: String?
    var statusDisplayMode: String?
    var retention: String?
    var quickKey: UInt32?
    var quickModifiers: UInt32?
    var pauseKey: UInt32?
    var pauseModifiers: UInt32?
  }
  public static func encode(_ settings: TopTimerSettings) throws -> Data {
    var value = settings
    value.normalize()
    try validateSound(value.defaultAlertName)
    let payload = Payload(
      version: 1, snoozeSeconds: value.snoozeSeconds, historyPageSize: value.historyPageSize,
      alertVolume: value.alertVolume, showsStatusIcon: value.showsStatusIcon,
      uses24HourTime: value.uses24HourTime, launchesAtLogin: value.launchesAtLogin,
      preventsSleep: value.preventsSleep, defaultAlertName: value.defaultAlertName,
      statusDisplayMode: String(describing: value.statusDisplayMode),
      retention: value.retention.rawValue, quickKey: value.quickEntryShortcut?.keyCode,
      quickModifiers: value.quickEntryShortcut?.modifiers,
      pauseKey: value.pauseResumeShortcut?.keyCode,
      pauseModifiers: value.pauseResumeShortcut?.modifiers)
    let data = try JSONEncoder().encode(payload)
    guard data.count <= maximumBytes else { throw SettingsStoreError.oversized }
    return data
  }
  public static func decode(_ data: Data) throws -> TopTimerSettings {
    guard data.count <= maximumBytes else { throw SettingsStoreError.oversized }
    let payload: Payload
    do { payload = try JSONDecoder().decode(Payload.self, from: data) } catch {
      throw SettingsStoreError.malformed
    }
    guard payload.version == 1 else { throw SettingsStoreError.unsupportedVersion }
    guard (payload.quickKey == nil) == (payload.quickModifiers == nil),
      (payload.pauseKey == nil) == (payload.pauseModifiers == nil)
    else { throw SettingsStoreError.malformed }
    try validateSound(payload.defaultAlertName)
    var value = TopTimerSettings(snoozeSeconds: payload.snoozeSeconds)
    value.historyPageSize = payload.historyPageSize
    value.alertVolume = payload.alertVolume
    value.showsStatusIcon = payload.showsStatusIcon ?? true
    value.uses24HourTime = payload.uses24HourTime ?? true
    value.launchesAtLogin = payload.launchesAtLogin ?? false
    value.preventsSleep = payload.preventsSleep ?? false
    value.defaultAlertName = payload.defaultAlertName
    value.statusDisplayMode =
      payload.statusDisplayMode == "seconds"
      ? .seconds : payload.statusDisplayMode == "clock" ? .clock : .compact
    value.retention = payload.retention.flatMap(HistoryRetention.init(rawValue:)) ?? .unlimited
    if let key = payload.quickKey, let modifiers = payload.quickModifiers {
      value.quickEntryShortcut = try Shortcut(keyCode: key, modifiers: modifiers)
    }
    if let key = payload.pauseKey, let modifiers = payload.pauseModifiers {
      value.pauseResumeShortcut = try Shortcut(keyCode: key, modifiers: modifiers)
    }
    value.normalize()
    return value
  }
  private static func validateSound(_ name: String?) throws {
    guard let name else { return }
    let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
    guard name.count <= 128, !name.isEmpty, name != ".", name != "..",
      name.unicodeScalars.allSatisfy(safe.contains)
    else { throw SettingsStoreError.malformed }
  }
}

public final class TopTimerSettingsStore {
  private let storage: any SettingsDataStore
  public init(storage: any SettingsDataStore = UserDefaultsSettingsDataStore()) {
    self.storage = storage
  }
  public func load() throws -> TopTimerSettings {
    guard let data = storage.read() else { return .defaults }
    return try TopTimerSettingsCodec.decode(data)
  }
  public func save(_ settings: TopTimerSettings) throws {
    try storage.write(TopTimerSettingsCodec.encode(settings))
  }
  public func loadForStartup() -> SettingsStartupRecovery {
    do { return SettingsStartupRecovery(settings: try load(), warning: nil) } catch {
      do {
        try save(.defaults)
        return SettingsStartupRecovery(
          settings: .defaults,
          warning:
            "Saved settings could not be read and were reset to safe defaults. Review Settings, then acknowledge recovery."
        )
      } catch {
        return SettingsStartupRecovery(
          settings: .defaults,
          warning:
            "Saved settings could not be read. Safe defaults are active, but could not be saved. Retry saving recovered settings."
        )
      }
    }
  }
}

public struct SettingsStartupRecovery: Equatable, Sendable {
  public let settings: TopTimerSettings
  public let warning: String?
}
