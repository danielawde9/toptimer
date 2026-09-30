import AppKit
import SwiftUI

public enum TopTimerWindow: CaseIterable, Hashable, Sendable {
  case now, timerList, history, reports, settings, sequences

  var title: String {
    switch self {
    case .now: "TopTimer"
    case .timerList: "Timers"
    case .history: "History"
    case .reports: "Reports"
    case .settings: "Settings"
    case .sequences: "Sequences"
    }
  }
}

/// Retains at most one controller for each auxiliary window. Closing a window
/// tears down only its hosted hierarchy; application state remains externally owned.
@MainActor public final class WindowCoordinator: NSObject, NSWindowDelegate, NSToolbarDelegate {
  public var navigate: ((TopTimerWindow) -> Void)?
  private let navigationID = NSToolbarItem.Identifier("TopTimer.navigation")
  private var controllers: [TopTimerWindow: NSWindowController] = [:]
  public override init() { super.init() }
  public var windowCount: Int { controllers.count }

  @discardableResult public func show<Content: View>(
    kind: TopTimerWindow, @ViewBuilder content: () -> Content
  ) -> NSWindowController {
    if let existing = controllers[kind] {
      existing.showWindow(nil)
      existing.window?.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return existing
    }
    let size: NSSize
    switch kind {
    case .now: size = NSSize(width: 620, height: 560)
    case .timerList: size = NSSize(width: 380, height: 420)
    case .reports: size = NSSize(width: 760, height: 680)
    case .sequences: size = NSSize(width: 620, height: 500)
    case .settings: size = NSSize(width: 620, height: 820)
    default: size = NSSize(width: 700, height: 520)
    }
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered,
      defer: false)
    window.title = kind.title
    if kind == .sequences { window.contentMinSize = NSSize(width: 560, height: 440) }
    if kind == .now { window.contentMinSize = NSSize(width: 460, height: 360) }
    if kind == .reports { window.contentMinSize = NSSize(width: 680, height: 580) }
    if kind == .history { window.contentMinSize = NSSize(width: 680, height: 460) }
    if kind == .timerList { window.contentMinSize = NSSize(width: 340, height: 260) }
    window.contentViewController = NSHostingController(rootView: AnyView(content()))
    window.delegate = self
    if navigate != nil {
      let toolbar = NSToolbar(identifier: "TopTimer.\(kind.title).navigation")
      toolbar.delegate = self
      toolbar.displayMode = .iconOnly
      toolbar.allowsUserCustomization = false
      window.toolbar = toolbar
    }
    window.setFrameAutosaveName("TopTimer.\(kind.title)")
    let controller = NSWindowController(window: window)
    controllers[kind] = controller
    controller.showWindow(nil)
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    return controller
  }

  public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [navigationID, .flexibleSpace]
  }
  public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [navigationID, .flexibleSpace]
  }
  public func toolbar(
    _ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
    willBeInsertedIntoToolbar flag: Bool
  ) -> NSToolbarItem? {
    guard identifier == navigationID else { return nil }
    let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 110, height: 28), pullsDown: true)
    let menu = NSMenu()
    menu.addItem(NSMenuItem(title: "Go to", action: nil, keyEquivalent: ""))
    for (index, kind) in TopTimerWindow.allCases.enumerated() {
      let item = NSMenuItem(
        title: kind == .now ? "Main window" : kind.title, action: #selector(navigateToScreen(_:)),
        keyEquivalent: "")
      item.tag = index
      item.target = self
      menu.addItem(item)
    }
    popup.menu = menu
    popup.setAccessibilityLabel("Go to")
    popup.toolTip = "Switch to any TopTimer screen"
    let item = NSToolbarItem(itemIdentifier: navigationID)
    item.label = "Go to"
    item.view = popup
    return item
  }
  @objc private func navigateToScreen(_ item: NSMenuItem) {
    guard TopTimerWindow.allCases.indices.contains(item.tag) else { return }
    navigate?(TopTimerWindow.allCases[item.tag])
  }

  public func closeAll() {
    let owned = Array(controllers.values)
    controllers.removeAll()
    for controller in owned { controller.close() }
  }

  public func windowWillClose(_ notification: Notification) {
    guard let window = notification.object as? NSWindow else { return }
    window.contentViewController = nil
    controllers = controllers.filter { $0.value.window !== window }
  }
}
