import AppKit
@preconcurrency import Carbon
import Foundation
import TopTimerPersistence
import TopTimerSystem
import UserNotifications

@MainActor public final class TopTimerApplication: NSObject, NSApplicationDelegate {
  private let operations = AppOperationOwner()
  private var starting = false
  private var statusController: StatusBarController?
  private var refreshTimer: Timer?
  private var store: CoreDataStore?
  private var hotKeys: GlobalHotKeyController?
  private let loginItem = LoginItemController()
  private let settingsStore = TopTimerSettingsStore()
  private let sleepController = SleepAssertionController()
  private var failureController: StartupFailureController?
  private var closeFailureController: CloseFailureController?
  private var lifecycle = LifecycleCoordinator()
  private var terminationTask: Task<Void, Never>?
  private var closingStore: CoreDataStore?
  private var notificationDelegate: TimerNotificationDelegate?
  private var notificationCenter: (any NotificationDelegateRegistering)?
  func installNotificationResponses(state: AppState, center: any NotificationDelegateRegistering) {
    notificationCenter?.delegate = nil
    let delegate = TimerNotificationDelegate(state: state)
    notificationDelegate = delegate
    notificationCenter = center
    center.delegate = delegate
  }
  private weak var terminationSender: NSApplication?
  public func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    operations.submit { await self.start() }
  }
  public func applicationWillTerminate(_ notification: Notification) { shutdownResources() }
  public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    let effects = lifecycle.requestTermination()
    guard effects.contains(.beginClose) else { return .terminateLater }
    operations.stopAccepting()
    shutdownResources()
    terminationSender = sender
    terminationTask = Task { [weak self] in
      guard let self else { return }
      await self.operations.drain()
      let closingStore = self.store
      self.store = nil
      self.closingStore = closingStore
      let result: LifecycleCoordinator.Result
      do {
        try await closingStore?.close()
        result = .success
      } catch {
        NSLog("TopTimer store close failed: %@", error.localizedDescription)
        result = .failure
      }
      self.applyCloseEffects(self.lifecycle.closeResult(result))
      self.terminationTask = nil
    }
    return .terminateLater
  }
  private func applyCloseEffects(_ effects: [LifecycleCoordinator.Effect]) {
    for effect in effects {
      switch effect {
      case .reportCloseFailure:
        closeFailureController = CloseFailureController(
          retry: { [weak self] in self?.retryClose() },
          quit: { [weak self] in self?.quitAfterCloseFailure() })
      case .replyToTermination(let value):
        closeFailureController?.shutdown()
        closeFailureController = nil
        terminationSender?.reply(toApplicationShouldTerminate: value)
      default: break
      }
    }
  }
  private func retryClose() {
    guard terminationTask == nil, let closingStore else { return }
    terminationTask = Task { [weak self] in
      guard let self else { return }
      defer { self.terminationTask = nil }
      do {
        try await closingStore.close()
        self.closingStore = nil
        self.applyCloseEffects(self.lifecycle.closeResult(.success))
      } catch {
        self.applyCloseEffects(self.lifecycle.closeResult(.failure))
      }
    }
  }
  private func quitAfterCloseFailure() { applyCloseEffects(lifecycle.quitAfterCloseFailure()) }
  private func start() async {
    guard !starting else { return }
    starting = true
    defer { starting = false }
    do {
      let recovered = settingsStore.loadForStartup()
      let preferences = recovered.settings
      let folder = try applicationSupportFolder()
      let newStore: CoreDataStore
      if let existing = store {
        newStore = existing
      } else {
        newStore = try await CoreDataStore.sqlite(
          at: folder.appendingPathComponent("TopTimer.sqlite"))
      }
      store = newStore
      guard operations.accepting else { return }
      let soundController = AlertSoundController()
      let state = AppState(
        repository: TimerCoreDataRepository(store: newStore),
        notifications: NotificationController(), presets: PresetCoreDataRepository(store: newStore),
        alertSounds: soundController, operations: operations,
        settingsStore: settingsStore, initialPreferences: preferences,
        settingsRecoveryWarning: recovered.warning,
        sleepController: sleepController)
      await state.load()
      guard operations.accepting else { return }
      installNotificationResponses(state: state, center: UNUserNotificationCenter.current())
      let controller = StatusBarController(
        state: state,
        updateHotKey: { [weak self] slot, shortcut in self?.replaceHotKey(shortcut, for: slot) },
        updateLogin: { [weak self] enabled in self?.setLogin(enabled: enabled) },
        importSound: { url in try await soundController.importSound(from: url).lastPathComponent })
      let keys = GlobalHotKeyController(
        quickEntry: { [weak controller] in controller?.openFromShortcut() },
        pauseResumePriority: { [weak state] in
          guard let state else { return }
          state.perform { await state.togglePriorityTimer() }
        })
      try keys.register(
        preferences.quickEntryShortcut
          ?? Shortcut(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(cmdKey | shiftKey)),
        for: .quickEntry)
      try keys.register(
        preferences.pauseResumeShortcut
          ?? Shortcut(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(cmdKey | shiftKey)),
        for: .pauseResumePriority)
      guard lifecycle.startResult(.success).contains(.createResources) else { return }
      statusController = controller
      hotKeys = keys
      if preferences.launchesAtLogin {
        _ = state.changeLogin(true, apply: { self.setLogin(enabled: $0) })
      }
      failureController = nil
      refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak state] _ in
        MainActor.assumeIsolated { state?.perform { await state?.refresh(now: .now) } }
      }
    } catch {
      guard operations.accepting else { return }
      _ = lifecycle.startResult(.failure)
      failureController = StartupFailureController(
        error: error, retry: { [weak self] in self?.retry() })
      failureController?.open()
    }
  }
  private func retry() {
    failureController?.shutdown()
    failureController = nil
    operations.submit { await self.start() }
  }
  private func replaceHotKey(_ shortcut: Shortcut, for slot: HotKeySlot) -> String? {
    guard let hotKeys else {
      return "Shortcuts are unavailable while starting or closing. Try again when ready."
    }
    do {
      try hotKeys.register(shortcut, for: slot)
      return nil
    } catch { return "Could not use that shortcut. The previous shortcut is unchanged." }
  }
  private func setLogin(enabled: Bool) -> String? {
    do {
      try loginItem.setEnabled(enabled)
      return nil
    } catch { return "Could not change launch at login. Open System Settings and try again." }
  }
  private func shutdownResources() {
    notificationCenter?.delegate = nil
    notificationCenter = nil
    notificationDelegate = nil
    do { try sleepController.releaseIfNeeded() } catch {
      NSLog("TopTimer could not release sleep prevention.")
    }
    refreshTimer?.invalidate()
    refreshTimer = nil
    do { try hotKeys?.shutdown() } catch {
      NSLog("TopTimer hot key shutdown failed: %@", error.localizedDescription)
    }
    hotKeys = nil
    statusController?.shutdown()
    statusController = nil
    failureController?.shutdown()
    failureController = nil
  }
  private func applicationSupportFolder() throws -> URL {
    let base = try FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    let folder = base.appendingPathComponent("TopTimer", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }
}
