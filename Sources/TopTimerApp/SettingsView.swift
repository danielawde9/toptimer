import AppKit
import SwiftUI
import TopTimerSystem

public enum HistoryRetention: String, CaseIterable, Sendable, Equatable {
  case sevenDays, thirtyDays, ninetyDays, oneYear, unlimited

  public var days: Int? {
    switch self {
    case .sevenDays: 7
    case .thirtyDays: 30
    case .ninetyDays: 90
    case .oneYear: 365
    case .unlimited: nil
    }
  }

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
  private let updateSound: ((String?) async -> Bool)?
  private let additionalContent: AnyView
  @State private var error: String?
  @State private var quickKeyCode = "17"
  @State private var pauseKeyCode = "35"

  public init(
    settings: Binding<TopTimerSettings>, notificationDenied: Bool = false,
    updateHotKey: @escaping (HotKeySlot, Shortcut) -> String? = { _, _ in nil },
    updateLogin: @escaping (Bool) -> String? = { _ in nil },
    importSound: @escaping (URL) async throws -> String = { _ in
      throw CocoaError(.fileReadUnsupportedScheme)
    },
    operations: AppOperationOwner? = nil,
    updateSound: ((String?) async -> Bool)? = nil,
    additionalContent: AnyView = AnyView(EmptyView())
  ) {
    _settings = settings
    self.notificationDenied = notificationDenied
    self.updateHotKey = updateHotKey
    self.updateLogin = updateLogin
    self.importSound = importSound
    self.operations = operations
    self.updateSound = updateSound
    self.additionalContent = additionalContent
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
        shortcutRow(
          "Pause or resume priority timer", text: $pauseKeyCode, slot: .pauseResumePriority)
      }
      Section("Alerts") {
        Picker(
          "Default sound",
          selection: Binding(
            get: { settings.defaultAlertName ?? "" },
            set: { chooseDefaultSound($0.isEmpty ? nil : $0) })
        ) {
          Text("Default").tag("")
          ForEach(SoundCatalog.builtIn.names, id: \.self) { Text($0).tag($0) }
          if let name = settings.defaultAlertName, !SoundCatalog.builtIn.names.contains(name) {
            Text(name).tag(name)
          }
        }
        Slider(value: $settings.alertVolume, in: 0...1) { Text("Alert volume") }
        Stepper(
          "Snooze: \(Int(settings.snoozeSeconds / 60)) min", value: $settings.snoozeSeconds,
          in: 60...86_400, step: 60)
        Button("Import sound…") { chooseSound() }
        if notificationDenied {
          Text("Notifications are off. Timers continue to run without them.").foregroundStyle(
            .secondary)
          Button("Open Notification Settings") {
            if !NotificationSettingsLink.open() {
              error = "Open System Settings, then Notifications, and select TopTimer."
            }
          }
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
        Section {
          Text(error).foregroundStyle(.red)
          Button("Dismiss message") { self.error = nil }
        }
      }
      additionalContent
    }
    .formStyle(.grouped)
    .padding()
    .frame(minWidth: 460, minHeight: 360)
    .accessibilityIdentifier("settings-view")
    .onAppear {
      quickKeyCode = String(settings.quickEntryShortcut?.keyCode ?? 17)
      pauseKeyCode = String(settings.pauseResumeShortcut?.keyCode ?? 35)
    }
  }

  private func shortcutRow(_ title: String, text: Binding<String>, slot: HotKeySlot) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
        Text("⌘⇧\(keyName(for: text.wrappedValue))").font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      TextField("Key code (0–127)", text: text).frame(width: 100)
      Button("Set") {
        guard let code = UInt32(text.wrappedValue),
          let shortcut = try? Shortcut(keyCode: code, modifiers: 768)
        else {
          error = "Enter a valid key code. The previous shortcut is unchanged."
          return
        }
        if let message = updateHotKey(slot, shortcut) {
          error = message
        } else {
          error = nil
          if slot == .quickEntry {
            settings.quickEntryShortcut = shortcut
          } else {
            settings.pauseResumeShortcut = shortcut
          }
        }
      }
    }
  }

  private func keyName(for value: String) -> String {
    let names: [String: String] = [
      "0": "A", "1": "S", "2": "D", "3": "F", "4": "H", "5": "G", "6": "Z",
      "7": "X", "8": "C", "9": "V", "11": "B", "12": "Q", "13": "W", "14": "E",
      "15": "R", "16": "Y", "17": "T", "31": "O", "32": "U", "34": "I",
      "35": "P", "37": "L", "38": "J", "40": "K", "45": "N", "46": "M"
    ]
    return names[value] ?? "key (value)"
  }

  private func setLogin(_ enabled: Bool) {
    if let message = updateLogin(enabled) {
      error = message
      return
    }
    settings.launchesAtLogin = enabled
    error = nil
  }

  private func chooseSound() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let work: @MainActor @Sendable () async -> Void = {
      do {
        let name = try await importSound(url)
        if let updateSound { _ = await updateSound(name) } else { settings.defaultAlertName = name }
        error = nil
      } catch {
        self.error =
          "Could not import that sound. The previous sound is unchanged. Retry Import sound or choose another file."
      }
    }
    if let operations {
      if !operations.submit(work) {
        error = "Sound import is busy. Retry when the current operation completes."
      }
    } else {
      Task { await work() }
    }
  }

  private func chooseDefaultSound(_ name: String?) {
    guard let updateSound else {
      settings.defaultAlertName = name
      return
    }
    guard let operations, operations.submit({ _ = await updateSound(name) }) else {
      error = "Sound selection is busy. Retry when ready."
      return
    }
  }
}

public enum NotificationSettingsLink {
  @MainActor public static func open(using open: (URL) -> Bool = { NSWorkspace.shared.open($0) })
    -> Bool
  {
    guard
      let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
    else { return false }
    return open(url)
  }
}
