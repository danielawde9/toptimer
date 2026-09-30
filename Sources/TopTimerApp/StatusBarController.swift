import AppKit
import Combine
import SwiftUI
import TopTimerDomain
import TopTimerSystem

@MainActor public final class StatusBarController: NSObject, NSPopoverDelegate {
  private static let quickEntryPopoverSize = NSSize(width: 320, height: 300)
  private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let sounds = SoundCatalogState()
  private let popover = NSPopover()
  private let state: AppState
  private let windows = WindowCoordinator()
  private let updateHotKey: (HotKeySlot, Shortcut?) -> String?
  private let updateLogin: (Bool) -> String?
  private let importSound: (URL) async throws -> String
  private var subscriptions = Set<AnyCancellable>()
  private var shortcutOrigin: NSRunningApplication?
  var popoverForTesting: NSPopover { popover }
  public init(
    state: AppState, updateHotKey: @escaping (HotKeySlot, Shortcut?) -> String? = { _, _ in nil },
    updateLogin: @escaping (Bool) -> String? = { _ in nil },
    importSound: @escaping (URL) async throws -> String = { _ in
      throw CocoaError(.fileReadUnsupportedScheme)
    }
  ) {
    self.state = state
    self.updateHotKey = updateHotKey
    self.updateLogin = updateLogin
    self.importSound = importSound
    super.init()
    windows.navigate = { [weak self] kind in
      guard let self else { return }
      switch kind {
      case .now: self.openNow()
      case .timerList: self.openTimerList()
      case .history: self.openHistory()
      case .reports: self.openReports()
      case .settings: self.openSettings()
      case .sequences: self.openSequences()
      }
    }
    popover.behavior = .transient
    popover.delegate = self
    item.isVisible = true
    item.button?.isHidden = false
    item.button?.target = self
    item.button?.action = #selector(toggle)
    item.button?.imagePosition = .imageLeading
    state.$priorityTimer.combineLatest(state.$activeTimers).receive(on: RunLoop.main).sink {
      [weak self] timer, _ in self?.render(timer)
    }.store(in: &subscriptions)
    state.$preferences.receive(on: RunLoop.main).sink { [weak self] _ in
      self?.render(self?.state.priorityTimer)
    }.store(in: &subscriptions)
    render(nil)
  }
  public func shutdown() {
    subscriptions.removeAll()
    windows.closeAll()
    NSStatusBar.system.removeStatusItem(item)
  }
  @objc public func toggle() { popover.isShown ? close() : open() }
  public func open() {
    sounds.refresh()
    let root = AnyView(
      MenuBarPopoverView(
        state: state,
        openSettings: { [weak self] in self?.openSettings() },
        openTimers: { [weak self] in self?.openTimerList() },
        quit: { NSApp.terminate(nil) },
        openNow: { [weak self] in self?.openNow() },
        openSequences: { [weak self] in self?.openSequences() },
        closePopover: { [weak self] in self?.close() }
      )
      .frame(
        width: Self.quickEntryPopoverSize.width, height: Self.quickEntryPopoverSize.height,
        alignment: .topLeading))
    let host = NSHostingController(rootView: root)
    host.preferredContentSize = Self.quickEntryPopoverSize
    host.view.frame = NSRect(origin: .zero, size: Self.quickEntryPopoverSize)
    popover.contentSize = Self.quickEntryPopoverSize
    popover.contentViewController = host
    guard let button = item.button else { return }
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    NSApp.activate(ignoringOtherApps: true)
  }
  public func openFromShortcut() {
    shortcutOrigin = NSWorkspace.shared.frontmostApplication
    open()
  }
  public func close() { popover.performClose(nil) }
  private func openSettings() {
    close()
    windows.show(kind: .settings) {
      SettingsWindowRoot(
        state: self.state, updateHotKey: self.updateHotKey, updateLogin: self.updateLogin,
        importSound: self.importSound)
    }
  }
  private func openTimerList() {
    close()
    windows.show(kind: .timerList) {
      TimerListHost(state: self.state, sounds: self.sounds)
    }
  }
  private func openNow() {
    close()
    windows.show(kind: .now) {
      NowView(
        state: self.state, focusEntry: true,
        navigate: { [weak self] in self?.windows.navigate?($0) })
    }
  }
  private func openSequences() {
    close()
    windows.show(kind: .sequences) { SequenceView(state: self.state) }
  }
  private func openHistory() {
    windows.show(kind: .history) {
      HistoryView(state: self.state)
    }
  }
  private func openReports() { windows.show(kind: .reports) { ReportsView(state: self.state) } }
  public func popoverDidClose(_ notification: Notification) {
    if let origin = shortcutOrigin {
      origin.activate(options: [])
      shortcutOrigin = nil
    }
  }
  private func render(_ timer: TimerItem?) {
    let title = StatusTitleFormatter.format(
      timer: timer, now: .now, mode: state.preferences.statusDisplayMode,
      uses24HourTime: state.preferences.uses24HourTime)
    item.button?.title =
      title.text.isEmpty && !state.preferences.showsStatusIcon ? "TopTimer" : title.text
    item.button?.image =
      state.preferences.showsStatusIcon && title.showsIcon
      ? NSImage(systemSymbolName: "hourglass", accessibilityDescription: "TopTimer") : nil
    item.button?.font = .monospacedDigitSystemFont(ofSize: 0, weight: .regular)
    item.button?.setAccessibilityLabel(title.accessibilityLabel)
    let name = timer?.title.isEmpty == false ? timer?.title ?? "active timer" : "active timer"
    item.button?.toolTip = timer == nil ? "Open TopTimer" : "Open TopTimer — " + name
  }
}
struct SettingsWindowRoot: View {
  @ObservedObject var state: AppState
  let updateHotKey: (HotKeySlot, Shortcut?) -> String?
  let updateLogin: (Bool) -> String?
  let importSound: (URL) async throws -> String
  var body: some View {
    GeometryReader { geometry in
      SettingsView(
        settings: $state.preferences,
        notificationDenied: state.notificationStatus == .authorizationDenied
          || state.notificationStatus == .notAuthorized(.denied),
        updateHotKey: { state.changeHotKey($1, slot: $0, apply: updateHotKey) },
        updateLogin: { state.changeLogin($0, apply: updateLogin) },
        importSound: importSound, operations: state.operations,
        updateSound: { await state.changeDefaultSound($0) },
        additionalContent: AnyView(operationMessages)
      )
      .frame(width: geometry.size.width, height: geometry.size.height)
    }.frame(minWidth: 460, minHeight: 360)
  }
  @ViewBuilder private var operationMessages: some View {
    if state.settingsRecoveryWarning != nil || state.settingsError != nil || state.soundError != nil
      || state.loginError != nil || state.hotKeyError != nil || state.sleepError != nil
      || state.retentionError != nil
    {
      Section("Status and recovery") {
        if let warning = state.settingsRecoveryWarning {
          Text(warning).fixedSize(horizontal: false, vertical: true)
          Button("Save recovered settings and acknowledge") { state.saveRecoveredSettings() }
        }
        if let error = state.settingsError { Text(error).foregroundStyle(.red) }
        if let error = state.soundError { Text(error).foregroundStyle(.red) }
        if let error = state.loginError { Text(error).foregroundStyle(.red) }
        if let error = state.hotKeyError { Text(error).foregroundStyle(.red) }
        if let error = state.sleepError {
          Text(error).foregroundStyle(.red)
          Button("Retry sleep prevention") { state.updateSleepAssertion() }
        }
        if let error = state.retentionError {
          Text(error).foregroundStyle(.red)
          Button("Retry retention") { state.perform { await state.applyRetention() } }
        }
      }
    }
  }
}
struct TimerListHost: View {
  @ObservedObject var state: AppState
  @ObservedObject var sounds: SoundCatalogState
  @State private var ownsEditor = false
  var body: some View {
    TimerListView(
      state: state,
      editTimer: { id in
        state.perform {
          await state.selectEditor(id)
          ownsEditor = state.selectedEditorTimer != nil
        }
      }
    ).sheet(
      isPresented: Binding(
        get: { ownsEditor && state.selectedEditorTimer != nil },
        set: {
          if !$0 {
            ownsEditor = false
            state.perform { await state.selectEditor(nil) }
          }
        })
    ) {
      if let timer = state.selectedEditorTimer {
        EditorSheet(timer: timer, state: state, sounds: sounds)
      }
    }
  }
}
private struct EditorSheet: View {
  let timer: TimerItem
  @ObservedObject var state: AppState
  @ObservedObject var sounds: SoundCatalogState
  @State private var draft: EditorDraft
  init(timer: TimerItem, state: AppState, sounds: SoundCatalogState) {
    self.timer = timer
    self.state = state
    self.sounds = sounds
    _draft = State(initialValue: EditorDraft(timer: timer))
  }
  var body: some View {
    VStack {
      if let error = sounds.error {
        Text(error).font(.caption).foregroundStyle(.red)
        Button("Retry loading sounds") { sounds.refresh() }
      }
      TimerEditorView(draft: $draft, catalog: sounds.catalog, operations: state.operations) {
        configuration in
        await state.reconfigure(timer.id, configuration: configuration)
      }
    }.onAppear { sounds.refresh() }
  }
}
