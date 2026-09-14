import AppKit
import Carbon
import SwiftUI
import TopTimerSystem

public enum ShortcutRecorder {
  public static func shortcut(keyCode: UInt16?, modifiers: NSEvent.ModifierFlags) throws -> Shortcut {
    guard let keyCode else { throw GlobalHotKeyControllerError.invalidShortcut }
    let allowed: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
    let relevant = modifiers.intersection(.deviceIndependentFlagsMask)
    guard !relevant.isEmpty, relevant.subtracting(allowed).isEmpty else {
      throw GlobalHotKeyControllerError.invalidShortcut
    }
    var carbon: UInt32 = 0
    if relevant.contains(.command) { carbon |= UInt32(cmdKey) }
    if relevant.contains(.shift) { carbon |= UInt32(shiftKey) }
    if relevant.contains(.option) { carbon |= UInt32(optionKey) }
    if relevant.contains(.control) { carbon |= UInt32(controlKey) }
    return try Shortcut(keyCode: UInt32(keyCode), modifiers: carbon)
  }
}

func shortcutDisplay(_ shortcut: Shortcut?) -> String {
  guard let shortcut else { return "Not set" }
  let names: [UInt32: String] = [0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M"]
  var result = ""
  if shortcut.modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
  if shortcut.modifiers & UInt32(optionKey) != 0 { result += "⌥" }
  if shortcut.modifiers & UInt32(controlKey) != 0 { result += "⌃" }
  if shortcut.modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
  return result + (names[shortcut.keyCode] ?? "Key")
}

struct ShortcutCaptureSheet: View {
  let onCapture: (Shortcut) -> Void
  let cancel: () -> Void
  @State private var error: String?
  var body: some View {
    VStack(spacing: 16) {
      Text("Set shortcut").font(.headline)
      Text("Press the shortcut you want to use").foregroundStyle(.secondary)
      if let error { Text(error).font(.caption).foregroundStyle(.red) }
      Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
    }.padding(24).frame(width: 300).background(ShortcutCaptureMonitor { event in
      if event.keyCode == 53 { cancel(); return }
      do { onCapture(try ShortcutRecorder.shortcut(keyCode: event.keyCode, modifiers: event.modifierFlags)) }
      catch { self.error = "Use Command, Shift, Option, or Control with a key." }
    })
  }
}

private struct ShortcutCaptureMonitor: NSViewRepresentable {
  let receive: (NSEvent) -> Void
  func makeCoordinator() -> Coordinator { Coordinator(receive: receive) }
  func makeNSView(context: Context) -> NSView { context.coordinator.start(); return NSView() }
  func updateNSView(_ nsView: NSView, context: Context) {}
  static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.stop() }
  final class Coordinator {
    private let receive: (NSEvent) -> Void
    private var monitor: Any?
    init(receive: @escaping (NSEvent) -> Void) { self.receive = receive }
    func start() { monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in self?.receive(event); return nil } }
    func stop() { if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil } }
    deinit { stop() }
  }
}
