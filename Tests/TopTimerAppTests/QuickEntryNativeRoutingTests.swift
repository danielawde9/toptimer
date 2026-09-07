import AppKit
import SwiftUI
import XCTest
@testable import TopTimerApp

@MainActor final class QuickEntryNativeRoutingTests: XCTestCase {
  func testNativeSpaceTogglesOnlyForBlankOrFullySelectedInput() throws {
    var effects: [QuickEntryEffect] = []
    let host = NSHostingView(rootView: QuickEntryTextField(
      text: .constant(""), selectedSuggestion: .constant(-1), suggestions: [],
      focus: true, command: { effects.append($0) }))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 260, height: 60),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.orderFront(nil)
    defer { window.close() }
    host.layoutSubtreeIfNeeded()
    let field = try XCTUnwrap(descendants(host).compactMap { $0 as? QuickEntryTextField.Field }.first)
    window.makeFirstResponder(field)
    let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
    editor.insertText(" ", replacementRange: NSRange(location: 0, length: 0))
    XCTAssertEqual(effects, [.togglePriority])
    XCTAssertEqual(editor.string, "")
    effects.removeAll()
    editor.string = "15m Tea"
    editor.setSelectedRange(NSRange(location: 7, length: 0))
    editor.insertText(" ", replacementRange: NSRange(location: 7, length: 0))
    XCTAssertTrue(effects.isEmpty)
    XCTAssertEqual(editor.string, "15m Tea ")
    editor.setSelectedRange(NSRange(location: 0, length: 8))
    editor.insertText(" ", replacementRange: NSRange(location: 0, length: 8))
    XCTAssertEqual(effects, [.togglePriority])
    XCTAssertEqual(editor.string, "15m Tea ")
  }
  func testQuickEntryUpdatesDoNotStealFocusFromAnotherControl() throws {
    let model = InputModel()
    let host = NSHostingView(rootView: InputHost(model: model))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 260, height: 120),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.orderFront(nil)
    defer { window.close() }
    host.layoutSubtreeIfNeeded()
    let fields = descendants(host).compactMap { $0 as? NSTextField }
    let second = try XCTUnwrap(fields.first { !($0 is QuickEntryTextField.Field) })
    let quick = try XCTUnwrap(fields.first { $0 is QuickEntryTextField.Field })
    XCTAssertFalse(quick.isBordered, "Compact quick entry is borderless")
    XCTAssertTrue(window.makeFirstResponder(second))
    model.text = "15m Tea"
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.03))
    XCTAssertTrue(second.currentEditor() === window.firstResponder)
  }

  func testFieldEditorDelegateRoutesEscapeAndReturnWithoutReplacingBlankEntry() {
    var effects: [QuickEntryEffect] = []
    let bridge = QuickEntryTextField(
      text: .constant(""), selectedSuggestion: .constant(-1),
      suggestions: ["15m Tea"], focus: false, command: { effects.append($0) })
    let coordinator = bridge.makeCoordinator()
    let field = QuickEntryTextField.Field()
    field.delegate = coordinator
    let editor = NSTextView()
    let handledReturn = field.delegate?.control?(
      field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:)))
    XCTAssertEqual(handledReturn, true)
    XCTAssertEqual(effects, [.run(selectedSuggestion: false)])
    effects.removeAll()
    let handledEscape = field.delegate?.control?(
      field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:)))
    XCTAssertEqual(handledEscape, true)
    XCTAssertEqual(effects, [.close])
  }

  func testUnselectedSuggestionsDoNotOverrideTypedOrBlankReturn() {
    for text in ["", "30m New task"] {
      let result = QuickEntryCommandReducer.reduce(.return, state: .init(
        suggestionIndex: -1, suggestionCount: 2, text: text,
        selectionIsEntireText: false, isComposing: false))
      XCTAssertEqual(result.effect, .run(selectedSuggestion: false))
    }
    let result = QuickEntryCommandReducer.reduce(.down, state: .init(
      suggestionIndex: -1, suggestionCount: 2, text: "", selectionIsEntireText: false,
      isComposing: false))
    XCTAssertEqual(result.suggestionIndex, 0)
  }

  private func descendants(_ root: NSView) -> [NSView] {
    var queue = [root], result: [NSView] = []
    for _ in 0..<100 {
      guard !queue.isEmpty else { break }
      let view = queue.removeFirst()
      result.append(view)
      queue.append(contentsOf: view.subviews)
    }
    return result
  }
}

@MainActor private final class InputModel: ObservableObject {
  @Published var text = ""
}
private struct InputHost: View {
  @ObservedObject var model: InputModel
  var body: some View {
    VStack {
      QuickEntryTextField(text: $model.text, selectedSuggestion: .constant(-1),
        suggestions: [], focus: true, command: { _ in })
      TextField("Other control", text: .constant("Other"))
    }
  }
}
