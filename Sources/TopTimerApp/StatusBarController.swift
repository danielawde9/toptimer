import AppKit
import Combine
import SwiftUI
import TopTimerDomain

@MainActor public final class StatusBarController: NSObject, NSPopoverDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover(); private let state: AppState; private var subscriptions = Set<AnyCancellable>(); private var showingList = false; private var shortcutOrigin: NSRunningApplication?
    public init(state: AppState) { self.state = state; super.init(); popover.behavior = .transient; popover.delegate = self; item.button?.target = self; item.button?.action = #selector(toggle); item.button?.imagePosition = .imageLeading; state.$priorityTimer.combineLatest(state.$activeTimers).receive(on: RunLoop.main).sink { [weak self] timer, _ in self?.render(timer) }.store(in: &subscriptions); state.$preferences.receive(on: RunLoop.main).sink { [weak self] _ in self?.render(self?.state.priorityTimer) }.store(in: &subscriptions); render(nil) }
    public func shutdown() { subscriptions.removeAll(); NSStatusBar.system.removeStatusItem(item) }
    @objc public func toggle() { popover.isShown ? close() : open() }
    public func open() { let root = AnyView(PopoverRoot(state: state, showingList: showingList, onListChange: { [weak self] value in self?.showingList = value })); popover.contentViewController = NSHostingController(rootView: root); guard let button = item.button else { return }; popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY); NSApp.activate(ignoringOtherApps: true) }
    public func openFromShortcut() { shortcutOrigin = NSWorkspace.shared.frontmostApplication; open() }
    public func close() { popover.performClose(nil) }
    public func popoverDidClose(_ notification: Notification) { if let origin = shortcutOrigin { origin.activate(options: []); shortcutOrigin = nil } }
    private func render(_ timer: TimerItem?) { let title = StatusTitleFormatter.format(timer: timer, now: .now, mode: state.preferences.statusDisplayMode); item.button?.title = title.text; item.button?.image = state.preferences.showsStatusIcon && title.showsIcon ? NSImage(systemSymbolName: "hourglass", accessibilityDescription: "TopTimer") : nil; item.button?.font = .monospacedDigitSystemFont(ofSize: 0, weight: .regular); item.button?.setAccessibilityLabel(title.accessibilityLabel) }
}
private struct PopoverRoot: View { @ObservedObject var state: AppState; @State var showingList: Bool; let onListChange: (Bool) -> Void
    var body: some View { VStack(spacing: 0) { QuickEntryView(state: state, showingList: $showingList); if showingList { Divider(); TimerListView(state: state) } }.onChange(of: showingList) { value in onListChange(value) } }
}
