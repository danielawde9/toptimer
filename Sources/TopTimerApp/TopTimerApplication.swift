import AppKit
import Foundation
import TopTimerPersistence
import TopTimerSystem
@preconcurrency import Carbon

@MainActor public final class TopTimerApplication: NSObject, NSApplicationDelegate {
    private var statusController: StatusBarController?; private var refreshTimer: Timer?; private var store: CoreDataStore?; private var hotKeys: GlobalHotKeyController?
    public func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.accessory); Task { await start() } }
    public func applicationWillTerminate(_ notification: Notification) { refreshTimer?.invalidate(); refreshTimer = nil; try? hotKeys?.shutdown(); statusController?.shutdown() }
    private func start() async { do { let folder = try applicationSupportFolder(); let store = try await CoreDataStore.sqlite(at: folder.appendingPathComponent("TopTimer.sqlite")); self.store = store; let state = AppState(repository: TimerCoreDataRepository(store: store), notifications: NotificationController(), presets: PresetCoreDataRepository(store: store)); await state.load(); let controller = StatusBarController(state: state); statusController = controller; let keys = GlobalHotKeyController(quickEntry: { [weak controller] in controller?.openFromShortcut() }, pauseResumePriority: { [weak state] in guard let timer = state?.priorityTimer else { return }; Task { if timer.state == .running { _ = await state?.pause(timer.id) } else { _ = await state?.resume(timer.id) } } }); try keys.register(Shortcut(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(cmdKey | shiftKey)), for: .quickEntry); try keys.register(Shortcut(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(cmdKey | shiftKey)), for: .pauseResumePriority); hotKeys = keys; refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak state] _ in Task { await state?.refresh(now: .now) } } } catch { let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength); item.button?.title = "TopTimer unavailable"; item.button?.toolTip = "Could not open local timer storage. \(error.localizedDescription)" } }
    private func applicationSupportFolder() throws -> URL { let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true); let folder = base.appendingPathComponent("TopTimer", isDirectory: true); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true); return folder }
}
