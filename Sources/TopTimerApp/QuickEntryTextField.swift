import AppKit
import SwiftUI

@MainActor struct QuickEntryTextField: NSViewRepresentable {
  @Binding var text: String
  @Binding var selectedSuggestion: Int
  let suggestions: [String]
  let focus: Bool
  let command: (QuickEntryEffect) -> Void
  var focusRequest = 0
  var placeholder = "15m Focus"
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSView(context: Context) -> Field {
    let field = Field()
    field.cell = EntryCell(textCell: "")
    field.isEditable = true
    field.isSelectable = true
    field.isBordered = false
    field.drawsBackground = false
    field.commandCoordinator = context.coordinator
    field.delegate = context.coordinator
    field.placeholderString = placeholder
    field.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
    field.focusRingType = .default
    field.target = context.coordinator
    field.action = #selector(Coordinator.submit)
    field.setAccessibilityLabel("Start a timer")
    field.setAccessibilityIdentifier("quick-entry")
    return field
  }
  func updateNSView(_ field: Field, context: Context) {
    context.coordinator.parent = self
    if field.stringValue != text { field.stringValue = text }
    field.requestsInitialFocus = focus
    field.updateFocusRequest(focusRequest)
    field.focusIfNeeded()
  }

  final class Field: NSTextField {
    var requestsInitialFocus = false
    private var didFocus = false
    private var lastFocusRequest = 0
    func updateFocusRequest(_ request: Int) {
      if request != lastFocusRequest {
        didFocus = false
        lastFocusRequest = request
      }
    }
    weak var commandCoordinator: Coordinator?
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      focusIfNeeded()
    }
    func focusIfNeeded() {
      guard requestsInitialFocus else {
        didFocus = false
        return
      }
      guard !didFocus, let window else { return }
      didFocus = window.makeFirstResponder(self)
    }
    override func doCommand(by selector: Selector) {
      guard let commandCoordinator else { return super.doCommand(by: selector) }
      if commandCoordinator.handle(selector, field: self) { return }
      super.doCommand(by: selector)
    }
  }
  final class EntryCell: NSTextFieldCell {
    private let editor = EntryEditor()
    override func fieldEditor(for controlView: NSView) -> NSTextView? {
      editor.isFieldEditor = true
      editor.field = controlView as? Field
      return editor
    }
  }
  final class EntryEditor: NSTextView {
    weak var field: Field?
    override func insertText(_ insertString: Any, replacementRange: NSRange) {
      let inserted = (insertString as? String) ?? (insertString as? NSAttributedString)?.string
      if inserted == " ", !hasMarkedText(), let field,
        field.commandCoordinator?.handle(
          NSSelectorFromString("insertSpace:"), field: field,
          editor: self) == true
      {
        return
      }
      super.insertText(insertString, replacementRange: replacementRange)
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
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool
    {
      guard let field = control as? NSTextField else { return false }
      return handle(selector, field: field, editor: textView)
    }
    func handle(_ selector: Selector, field: NSTextField, editor suppliedEditor: NSTextView? = nil)
      -> Bool
    {
      let command: QuickEntryCommand?
      switch selector {
      case #selector(NSResponder.moveUp(_:)): command = .up
      case #selector(NSResponder.moveDown(_:)): command = .down
      case #selector(NSResponder.insertNewline(_:)): command = .return
      case #selector(NSResponder.cancelOperation(_:)): command = .escape
      default: command = selector == NSSelectorFromString("insertSpace:") ? .space : nil
      }
      guard let command else { return false }
      let editor = suppliedEditor ?? field.currentEditor() as? NSTextView
      let selection = editor?.selectedRange ?? NSRange(location: 0, length: 0)
      let entire =
        !(editor?.string ?? field.stringValue).isEmpty && selection.location == 0
        && selection.length == ((editor?.string ?? field.stringValue) as NSString).length
      let result = QuickEntryCommandReducer.reduce(
        command,
        state: .init(
          suggestionIndex: parent.selectedSuggestion, suggestionCount: parent.suggestions.count,
          text: editor?.string ?? field.stringValue, selectionIsEntireText: entire,
          isComposing: editor?.hasMarkedText() ?? false))
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
