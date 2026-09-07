import AppKit
@preconcurrency import Carbon
import Foundation
import TopTimerPersistence
import TopTimerSystem

@MainActor public final class TopTimerApplication: NSObject, NSApplicationDelegate {
  private let operations = AppOperationOwner()
  private var starting = false
  private var statusController: StatusBarController?
  private var refreshTimer: Timer?
  private var store: CoreDataStore?
  private var hotKeys: GlobalHotKeyController?
  private var failureController: StartupFailureController?
  private var closeFailureController: CloseFailureController?
  private var lifecycle = LifecycleCoordinator()
  private var terminationTask: Task<Void, Never>?
  private var closingStore: CoreDataStore?
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
      let folder = try applicationSupportFolder()
      let newStore: CoreDataStore
      if let existing = store { newStore = existing }
      else { newStore = try await CoreDataStore.sqlite(at: folder.appendingPathComponent("TopTimer.sqlite")) }
      store = newStore
      guard operations.accepting else { return }
      let state = AppState(
        repository: TimerCoreDataRepository(store: newStore),
        notifications: NotificationController(), presets: PresetCoreDataRepository(store: newStore),
        alertSounds: AlertSoundController(), operations: operations)
      await state.load()
      guard operations.accepting else { return }
      let controller = StatusBarController(state: state)
      let keys = GlobalHotKeyController(
        quickEntry: { [weak controller] in controller?.openFromShortcut() },
        pauseResumePriority: { [weak state] in
          guard let state, let timer = state.priorityTimer else { return }
          state.perform {
            if timer.state == .running {
              _ = await state.pause(timer.id)
            } else {
              _ = await state.resume(timer.id)
            }
          }
        })
      try keys.register(
        Shortcut(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(cmdKey | shiftKey)),
        for: .quickEntry)
      try keys.register(
        Shortcut(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(cmdKey | shiftKey)),
        for: .pauseResumePriority)
      guard lifecycle.startResult(.success).contains(.createResources) else { return }
      statusController = controller
      hotKeys = keys
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
  private func shutdownResources() {
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
