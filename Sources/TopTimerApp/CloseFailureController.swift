import AppKit

@MainActor final class CloseFailureController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let retry: () -> Void; private let quit: () -> Void
    init(retry: @escaping () -> Void, quit: @escaping () -> Void) { self.retry = retry; self.quit = quit; super.init(); item.button?.title = "TopTimer needs attention"; item.button?.target = self; item.button?.action = #selector(open) }
    func shutdown() { NSStatusBar.system.removeStatusItem(item) }
    @objc private func open() { let alert = NSAlert(); alert.messageText = "TopTimer could not close its timer store"; alert.informativeText = "Retry closing the store, or quit anyway."; alert.addButton(withTitle: "Retry"); alert.addButton(withTitle: "Quit"); alert.runModal() == .alertFirstButtonReturn ? retry() : quit() }
}
