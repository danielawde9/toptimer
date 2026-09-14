import AppKit
import Combine
import SwiftUI
import TopTimerDomain
import TopTimerSystem

@MainActor public final class StatusBarController: NSObject, NSPopoverDelegate {
  private static let quickEntryPopoverSize = NSSize(width: 276, height: 110)
  private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let sounds = SoundCatalogState()
  private let popover = NSPopover()
  private let state: AppState
  private let windows = WindowCoordinator()
  private let updateHotKey: (HotKeySlot, Shortcut?) -> String?
  private let updateLogin: (Bool) -> String?
  private let importSound: (URL) async throws -> String
  private var subscriptions = Set<AnyCancellable>()
  private var showingList = false
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
      PopoverRoot(
        state: state, sounds: sounds, showingList: showingList,
        onListChange: { [weak self] value in self?.showingList = value },
        closePopover: { [weak self] in self?.close() },
        openSettings: { [weak self] in self?.openSettings() },
        openTimerList: { [weak self] in self?.openTimerList() })
      .frame(width: Self.quickEntryPopoverSize.width, height: Self.quickEntryPopoverSize.height,
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
    windows.show(kind: .settings) {
      SettingsWindowRoot(
        state: self.state, updateHotKey: self.updateHotKey, updateLogin: self.updateLogin,
        importSound: self.importSound)
    }
  }
  private func openTimerList() {
    close()
    windows.show(kind: .timerList) { TimerListHost(state: self.state, sounds: self.sounds) }
  }
  private func openHistory() { windows.show(kind: .history) { HistoryView(state: self.state) } }
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
  private var operationMessages: some View {
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
struct PopoverRoot: View {
  @ObservedObject var state: AppState
  @ObservedObject var sounds: SoundCatalogState
  @State var showingList: Bool
  let onListChange: (Bool) -> Void
  let closePopover: () -> Void
  let openSettings: () -> Void
  let openTimerList: () -> Void
  var body: some View {
    VStack(spacing: 0) {
      QuickEntryView(
        state: state, showingList: $showingList, closePopover: closePopover,
        openSettings: openSettings, openTimerList: openTimerList)
      if showingList {
        Divider()
        TimerListHost(state: state, sounds: sounds)
      }
    }.onChange(of: showingList) { value in onListChange(value) }
  }
}

struct TimerListHost: View {
  @ObservedObject var state: AppState
  @ObservedObject var sounds: SoundCatalogState
  @State private var ownsEditor = false
  var openHistory: (() -> Void)? = nil
  var body: some View {
    TimerListView(
      state: state, openHistory: openHistory,
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
