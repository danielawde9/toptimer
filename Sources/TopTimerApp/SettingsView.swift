import AppKit
import SwiftUI
import TopTimerSystem

public enum HistoryRetention: String, CaseIterable, Sendable, Equatable {
  case sevenDays, thirtyDays, ninetyDays, oneYear, unlimited

  var title: String {
    switch self {
    case .sevenDays: "7 days"
    case .thirtyDays: "30 days"
    case .ninetyDays: "90 days"
    case .oneYear: "1 year"
    case .unlimited: "Unlimited"
    }
  }
}

public struct TopTimerSettings: Equatable, Sendable {
  public static let defaults = TopTimerSettings()
  public var statusDisplayMode: StatusDisplayMode = .compact
  public var showsStatusIcon = true
  public var quickEntryShortcut: Shortcut?
  public var pauseResumeShortcut: Shortcut?
  public var defaultAlertName: String?
  public var alertVolume = 1.0 {
    didSet { alertVolume = min(1, max(0, alertVolume.isFinite ? alertVolume : 1)) }
  }
  public var snoozeSeconds: TimeInterval = 300 {
    didSet { snoozeSeconds = min(86_400, max(60, snoozeSeconds.isFinite ? snoozeSeconds : 300)) }
  }
  public var uses24HourTime = true
  public var launchesAtLogin = false
  public var preventsSleep = false
  public var retention: HistoryRetention = .unlimited
  public var historyPageSize = 100 {
    didSet { historyPageSize = min(200, max(1, historyPageSize)) }
  }

  public init(snoozeSeconds: TimeInterval = 300) {
    self.snoozeSeconds = snoozeSeconds
    normalize()
  }

  public mutating func normalize() {
    snoozeSeconds = min(86_400, max(60, snoozeSeconds.isFinite ? snoozeSeconds : 300))
    historyPageSize = min(200, max(1, historyPageSize))
    alertVolume = min(1, max(0, alertVolume.isFinite ? alertVolume : 1))
  }
}

public typealias AppPreferences = TopTimerSettings

public struct SettingsView: View {
  @Binding private var settings: TopTimerSettings
  private let notificationDenied: Bool
  private let updateHotKey: (HotKeySlot, Shortcut) -> String?
  private let updateLogin: (Bool) -> String?
  private let importSound: (URL) async throws -> String
  private let operations: AppOperationOwner?
  @State private var error: String?
  @State private var quickKeyCode = "17"
  @State private var pauseKeyCode = "35"

  public init(
    settings: Binding<TopTimerSettings>, notificationDenied: Bool = false,
    updateHotKey: @escaping (HotKeySlot, Shortcut) -> String? = { _, _ in nil },
    updateLogin: @escaping (Bool) -> String? = { _ in nil },
    importSound: @escaping (URL) async throws -> String = { _ in throw CocoaError(.fileReadUnsupportedScheme) },
    operations: AppOperationOwner? = nil
  ) {
    _settings = settings
    self.notificationDenied = notificationDenied
    self.updateHotKey = updateHotKey
    self.updateLogin = updateLogin
    self.importSound = importSound
    self.operations = operations
  }

  public var body: some View {
    Form {
      Section("Menu bar") {
        Picker("Timer display", selection: $settings.statusDisplayMode) {
          Text("Compact").tag(StatusDisplayMode.compact)
          Text("Seconds").tag(StatusDisplayMode.seconds)
          Text("Clock").tag(StatusDisplayMode.clock)
        }
        Toggle("Show menu bar icon", isOn: $settings.showsStatusIcon)
        Toggle("Use 24-hour time", isOn: $settings.uses24HourTime)
      }
      Section("Shortcuts") {
        shortcutRow("Open quick entry", text: $quickKeyCode, slot: .quickEntry)
        shortcutRow("Pause or resume priority timer", text: $pauseKeyCode, slot: .pauseResumePriority)
      }
      Section("Alerts") {
        TextField("Sound", text: Binding(get: { settings.defaultAlertName ?? "" }, set: { settings.defaultAlertName = $0.isEmpty ? nil : $0 }))
        Slider(value: $settings.alertVolume, in: 0...1) { Text("Alert volume") }
        Stepper("Snooze: \(Int(settings.snoozeSeconds / 60)) min", value: $settings.snoozeSeconds, in: 60...86_400, step: 60)
        Button("Import sound…") { chooseSound() }
        if notificationDenied {
          Text("Notifications are off. Timers continue to run without them.").foregroundStyle(.secondary)
          Button("Open Notification Settings") { Self.openNotificationSettings() }
        }
      }
      Section("System") {
        Toggle(
          "Launch at login",
          isOn: Binding(
            get: { settings.launchesAtLogin },
            set: { enabled in setLogin(enabled) }))
        Toggle("Prevent sleep while a timer runs", isOn: $settings.preventsSleep)
        Picker("Keep history", selection: $settings.retention) {
          ForEach(HistoryRetention.allCases, id: \.self) { Text($0.title).tag($0) }
        }
      }
      if let error {
        Section { Text(error).foregroundStyle(.red); Button("Try again") { self.error = nil } }
      }
    }
    .formStyle(.grouped)
    .padding()
    .frame(minWidth: 460, minHeight: 520)
    .accessibilityIdentifier("settings-view")
  }

  private func shortcutRow(_ title: String, text: Binding<String>, slot: HotKeySlot) -> some View {
    HStack {
      Text(title)
      Spacer()
      TextField("Key code", text: text).frame(width: 72)
      Button("Set") {
        guard let code = UInt32(text.wrappedValue), let shortcut = try? Shortcut(keyCode: code, modifiers: 768) else {
          error = "Enter a valid key code. The previous shortcut is unchanged."
          return
        }
        if let message = updateHotKey(slot, shortcut) { error = message }
        else if slot == .quickEntry { settings.quickEntryShortcut = shortcut }
        else { settings.pauseResumeShortcut = shortcut }
      }
    }
  }

  private func setLogin(_ enabled: Bool) {
    if let message = updateLogin(enabled) { error = message; return }
    settings.launchesAtLogin = enabled
  }

  private func chooseSound() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let previous = settings.defaultAlertName
    let work: @MainActor @Sendable () async -> Void = {
      do { settings.defaultAlertName = try await importSound(url) }
      catch { settings.defaultAlertName = previous; self.error = "Could not import that sound. The previous sound is unchanged." }
    }
    if let operations { _ = operations.submit(work) } else { Task { await work() } }
  }

  private static func openNotificationSettings() {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
    NSWorkspace.shared.open(url)
  }
}
