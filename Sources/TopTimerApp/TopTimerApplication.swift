import AppKit
import Foundation
import TopTimerPersistence
import TopTimerSystem
@preconcurrency import Carbon

@MainActor public final class TopTimerApplication: NSObject, NSApplicationDelegate {
    private var statusController: StatusBarController?; private var refreshTimer: Timer?; private var store: CoreDataStore?; private var hotKeys: GlobalHotKeyController?; private var failureController: StartupFailureController?; private var lifecycle = LifecycleCoordinator(); private var terminationTask: Task<Void, Never>?
    public func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.accessory); Task { await start() } }
    public func applicationWillTerminate(_ notification: Notification) { shutdownResources() }
    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let effects = lifecycle.requestTermination(); guard effects.contains(.beginClose) else { return .terminateLater }
        shutdownResources()
        let closingStore = store; store = nil
        terminationTask = Task { [weak self] in
            let result: LifecycleCoordinator.Result
            do { try await closingStore?.close(); result = .success } catch { NSLog("TopTimer store close failed: %@", error.localizedDescription); result = .failure }
            guard let self else { return }
            for effect in self.lifecycle.closeResult(result) { if case .replyToTermination(let shouldTerminate) = effect { sender.reply(toApplicationShouldTerminate: shouldTerminate) } }
            self.terminationTask = nil
        }
        return .terminateLater
    }
    private func start() async { do { let folder = try applicationSupportFolder(); let newStore = try await CoreDataStore.sqlite(at: folder.appendingPathComponent("TopTimer.sqlite")); let state = AppState(repository: TimerCoreDataRepository(store: newStore), notifications: NotificationController(), presets: PresetCoreDataRepository(store: newStore)); await state.load(); let controller = StatusBarController(state: state); let keys = GlobalHotKeyController(quickEntry: { [weak controller] in controller?.openFromShortcut() }, pauseResumePriority: { [weak state] in guard let timer = state?.priorityTimer else { return }; Task { if timer.state == .running { _ = await state?.pause(timer.id) } else { _ = await state?.resume(timer.id) } } }); try keys.register(Shortcut(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(cmdKey | shiftKey)), for: .quickEntry); try keys.register(Shortcut(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(cmdKey | shiftKey)), for: .pauseResumePriority); guard lifecycle.startResult(.success).contains(.createResources) else { try? await newStore.close(); return }; store = newStore; statusController = controller; hotKeys = keys; failureController = nil; refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak state] _ in Task { await state?.refresh(now: .now) } } } catch { _ = lifecycle.startResult(.failure); failureController = StartupFailureController(error: error, retry: { [weak self] in self?.retry() }); failureController?.open() } }
    private func retry() { failureController?.shutdown(); failureController = nil; Task { await start() } }
    private func shutdownResources() { refreshTimer?.invalidate(); refreshTimer = nil; do { try hotKeys?.shutdown() } catch { NSLog("TopTimer hot key shutdown failed: %@", error.localizedDescription) }; hotKeys = nil; statusController?.shutdown(); statusController = nil; failureController?.shutdown(); failureController = nil }
    private func applicationSupportFolder() throws -> URL { let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true); let folder = base.appendingPathComponent("TopTimer", isDirectory: true); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true); return folder }
}
