import AppKit
import Foundation
import TopTimerPersistence
import TopTimerSystem
@preconcurrency import Carbon

@MainActor public final class TopTimerApplication: NSObject, NSApplicationDelegate {
    private var statusController: StatusBarController?; private var refreshTimer: Timer?; private var store: CoreDataStore?; private var hotKeys: GlobalHotKeyController?; private var failureController: StartupFailureController?; private var closeFailureController: CloseFailureController?; private var lifecycle = LifecycleCoordinator(); private var terminationTask: Task<Void, Never>?; private var closingStore: CoreDataStore?; private weak var terminationSender: NSApplication?
    public func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.accessory); Task { await start() } }
    public func applicationWillTerminate(_ notification: Notification) { shutdownResources() }
    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let effects = lifecycle.requestTermination(); guard effects.contains(.beginClose) else { return .terminateLater }
        shutdownResources()
        let closingStore = store; store = nil; self.closingStore = closingStore; terminationSender = sender
        terminationTask = Task { [weak self] in
            let result: LifecycleCoordinator.Result
            do { try await closingStore?.close(); result = .success } catch { NSLog("TopTimer store close failed: %@", error.localizedDescription); result = .failure }
            guard let self else { return }
            self.applyCloseEffects(self.lifecycle.closeResult(result))
            self.terminationTask = nil
        }
        return .terminateLater
    }
    private func applyCloseEffects(_ effects: [LifecycleCoordinator.Effect]) { for effect in effects { switch effect { case .reportCloseFailure: closeFailureController = CloseFailureController(retry: { [weak self] in self?.retryClose() }, quit: { [weak self] in self?.quitAfterCloseFailure() }); case let .replyToTermination(value): closeFailureController?.shutdown(); closeFailureController = nil; terminationSender?.reply(toApplicationShouldTerminate: value); default: break } } }
    private func retryClose() { guard let closingStore else { return }; terminationTask = Task { [weak self] in do { try await closingStore.close(); guard let self else { return }; self.closingStore = nil; self.applyCloseEffects(self.lifecycle.closeResult(.success)) } catch { guard let self else { return }; self.applyCloseEffects(self.lifecycle.closeResult(.failure)) } } }
    private func quitAfterCloseFailure() { applyCloseEffects(lifecycle.quitAfterCloseFailure()) }
    private func start() async { do { let folder = try applicationSupportFolder(); let newStore = try await CoreDataStore.sqlite(at: folder.appendingPathComponent("TopTimer.sqlite")); let state = AppState(repository: TimerCoreDataRepository(store: newStore), notifications: NotificationController(), presets: PresetCoreDataRepository(store: newStore), alertSounds: AlertSoundController()); await state.load(); let controller = StatusBarController(state: state); let keys = GlobalHotKeyController(quickEntry: { [weak controller] in controller?.openFromShortcut() }, pauseResumePriority: { [weak state] in guard let timer = state?.priorityTimer else { return }; Task { if timer.state == .running { _ = await state?.pause(timer.id) } else { _ = await state?.resume(timer.id) } } }); try keys.register(Shortcut(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(cmdKey | shiftKey)), for: .quickEntry); try keys.register(Shortcut(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(cmdKey | shiftKey)), for: .pauseResumePriority); guard lifecycle.startResult(.success).contains(.createResources) else { try? await newStore.close(); return }; store = newStore; statusController = controller; hotKeys = keys; failureController = nil; refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak state] _ in Task { await state?.refresh(now: .now) } } } catch { _ = lifecycle.startResult(.failure); failureController = StartupFailureController(error: error, retry: { [weak self] in self?.retry() }); failureController?.open() } }
    private func retry() { failureController?.shutdown(); failureController = nil; Task { await start() } }
    private func shutdownResources() { refreshTimer?.invalidate(); refreshTimer = nil; do { try hotKeys?.shutdown() } catch { NSLog("TopTimer hot key shutdown failed: %@", error.localizedDescription) }; hotKeys = nil; statusController?.shutdown(); statusController = nil; failureController?.shutdown(); failureController = nil }
    private func applicationSupportFolder() throws -> URL { let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true); let folder = base.appendingPathComponent("TopTimer", isDirectory: true); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true); return folder }
}
