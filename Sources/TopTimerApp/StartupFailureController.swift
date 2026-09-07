import AppKit

@MainActor final class StartupFailureController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let error: Error; private let retry: () -> Void
    init(error: Error, retry: @escaping () -> Void) { self.error = error; self.retry = retry; super.init(); item.button?.title = "TopTimer unavailable"; item.button?.target = self; item.button?.action = #selector(open) }
    func shutdown() { NSStatusBar.system.removeStatusItem(item) }
    @objc func open() { let alert = NSAlert(); alert.messageText = "TopTimer could not start"; alert.informativeText = error.localizedDescription; alert.addButton(withTitle: "Retry"); alert.addButton(withTitle: "Quit"); if alert.runModal() == .alertFirstButtonReturn { retry() } else { NSApp.terminate(nil) } }
}
