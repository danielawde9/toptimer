import AppKit
import SwiftUI

public enum TopTimerWindow: CaseIterable, Hashable, Sendable {
  case timerList, history, reports, settings

  var title: String {
    switch self {
    case .timerList: "Timers"
    case .history: "History"
    case .reports: "Reports"
    case .settings: "Settings"
    }
  }
}

/// Retains at most one controller for each auxiliary window. Closing a window
/// tears down only its hosted hierarchy; application state remains externally owned.
@MainActor public final class WindowCoordinator: NSObject, NSWindowDelegate {
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
    let size = kind == .timerList ? NSSize(width: 380, height: 420) : NSSize(width: 700, height: 520)
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered,
      defer: false)
    window.title = kind.title
    window.contentViewController = NSHostingController(rootView: AnyView(content()))
    window.delegate = self
    window.setFrameAutosaveName("TopTimer.\(kind.title)")
    let controller = NSWindowController(window: window)
    controllers[kind] = controller
    controller.showWindow(nil)
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    return controller
  }

  public func closeAll() {
    for controller in controllers.values { controller.close() }
    controllers.removeAll()
  }

  public func windowWillClose(_ notification: Notification) {
    guard let window = notification.object as? NSWindow else { return }
    window.contentViewController = nil
    controllers = controllers.filter { $0.value.window !== window }
  }
}
