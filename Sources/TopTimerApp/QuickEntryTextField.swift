import AppKit
import SwiftUI

@MainActor struct QuickEntryTextField: NSViewRepresentable {
  @Binding var text: String
  @Binding var selectedSuggestion: Int
  let suggestions: [String]
  let focus: Bool
  let command: (QuickEntryEffect) -> Void
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSView(context: Context) -> Field {
    let field = Field()
    field.commandCoordinator = context.coordinator
    field.delegate = context.coordinator
    field.placeholderString = "15m Focus"
    field.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
    field.focusRingType = .default
    field.target = context.coordinator
    field.action = #selector(Coordinator.submit)
    field.setAccessibilityIdentifier("quick-entry")
    return field
  }
  func updateNSView(_ field: Field, context: Context) {
    context.coordinator.parent = self
    if field.stringValue != text { field.stringValue = text }
    if focus, field.window?.firstResponder !== field.currentEditor() {
      field.window?.makeFirstResponder(field)
    }
  }

  final class Field: NSTextField {
    weak var commandCoordinator: Coordinator?
    override func doCommand(by selector: Selector) {
      guard let commandCoordinator else { return super.doCommand(by: selector) }
      if commandCoordinator.handle(selector, field: self) { return }
      super.doCommand(by: selector)
    }
  }
  @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
    var parent: QuickEntryTextField
    init(_ parent: QuickEntryTextField) { self.parent = parent }
    func controlTextDidChange(_ notification: Notification) {
      guard let field = notification.object as? NSTextField else { return }
      parent.text = field.stringValue
    }
    @objc func submit() { parent.command(.run(selectedSuggestion: false)) }
    func handle(_ selector: Selector, field: NSTextField) -> Bool {
      let command: QuickEntryCommand?
      switch selector {
      case #selector(NSResponder.moveUp(_:)): command = .up
      case #selector(NSResponder.moveDown(_:)): command = .down
      case #selector(NSResponder.insertNewline(_:)): command = .return
      case #selector(NSResponder.cancelOperation(_:)): command = .escape
      default: command = selector == NSSelectorFromString("insertSpace:") ? .space : nil
      }
      guard let command else { return false }
      let editor = field.currentEditor() as? NSTextView
      let selection = editor?.selectedRange ?? NSRange(location: 0, length: 0)
      let entire =
        !field.stringValue.isEmpty && selection.location == 0
        && selection.length == (field.stringValue as NSString).length
      let result = QuickEntryCommandReducer.reduce(
        command,
        state: .init(
          suggestionIndex: parent.selectedSuggestion, suggestionCount: parent.suggestions.count,
          text: field.stringValue, selectionIsEntireText: entire,
          isComposing: (editor?.markedRange().location ?? NSNotFound) != NSNotFound))
      parent.selectedSuggestion = result.suggestionIndex
      switch result.effect {
      case .passThrough: return false
      default:
        parent.command(result.effect)
        return true
      }
    }
  }
}
