import AppKit
import SwiftUI

public struct QuickEntryView: View {
  @ObservedObject var state: AppState
  @State private var focused = false
  @State private var selectedSuggestion = 0
  @Binding var showingList: Bool
  let closePopover: () -> Void
  let openSettings: (() -> Void)?
  let openTimerList: (() -> Void)?
  public init(state: AppState, showingList: Binding<Bool>, closePopover: @escaping () -> Void = {}, openSettings: (() -> Void)? = nil, openTimerList: (() -> Void)? = nil)
  {
    self.state = state
    _showingList = showingList
    self.closePopover = closePopover
    self.openSettings = openSettings
    self.openTimerList = openTimerList
  }
  public var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        Image(systemName: "hourglass").accessibilityLabel("TopTimer")
        QuickEntryTextField(
          text: $state.quickEntryText, selectedSuggestion: $selectedSuggestion,
          suggestions: state.suggestions, focus: focused, command: handle
        ).frame(minHeight: 28)
      }.padding(8)
      if let error = state.inlineError {
        Text(error).font(.caption).foregroundStyle(.red).padding(.horizontal, 8)
      }
      suggestions
      HStack(spacing: 6) {
        Button {
          openSettings?()
        } label: {
          Image(systemName: "gearshape").frame(width: 28, height: 28).contentShape(Rectangle())
        }.help("Settings").accessibilityLabel("Settings")
        Button(action: run) {
          Image(systemName: "play.fill").frame(width: 28, height: 28).contentShape(Rectangle())
        }.keyboardShortcut(.return, modifiers: []).help("Run timer (Return)").accessibilityLabel(
          "Run timer")
        Button {
          if let openTimerList { openTimerList() } else { showingList.toggle() }
        } label: {
          Image(systemName: "list.bullet").frame(width: 28, height: 28).contentShape(Rectangle())
        }.help("Show timers").accessibilityLabel("Show timers")
        Spacer()
        Button {
          NSApplication.shared.terminate(nil)
        } label: {
          Image(systemName: "power").frame(width: 28, height: 28).contentShape(Rectangle())
        }.help("Quit TopTimer").accessibilityLabel("Quit TopTimer")
      }.buttonStyle(.borderless).padding(8)
    }.frame(width: 260).onAppear { focused = true }.onChange(of: state.quickEntryText) { text in
      selectedSuggestion = 0
      state.perform { await state.refreshSuggestions(query: text) }
    }
  }
  private func handle(_ effect: QuickEntryEffect) {
    switch effect {
    case .run(let selected) where selected:
      state.quickEntryText =
        state.suggestions.indices.contains(selectedSuggestion)
        ? state.suggestions[selectedSuggestion] : state.quickEntryText
      run()
    case .run: run()
    case .clear:
      state.quickEntryText = ""
      selectedSuggestion = 0
    case .close: closePopover()
    case .togglePriority: togglePriority()
    case .passThrough, .selectSuggestion: break
    }
  }
  /// Selecting a suggestion and pressing Return runs it immediately, exactly like clicking Run.
  private func run() { let command = state.quickEntryText; state.perform { await state.create(command: command) } }
  private func togglePriority() {
    guard let timer = state.priorityTimer else { return }
    state.perform {
      if timer.state == .running {
        _ = await state.pause(timer.id)
      } else {
        _ = await state.resume(timer.id)
      }
    }
  }
  @ViewBuilder private var suggestions: some View {
    if focused && !state.suggestions.isEmpty {
      ForEach(Array(state.suggestions.prefix(20).enumerated()), id: \.offset) { pair in
        suggestionButton(index: pair.offset, text: pair.element)
      }
    }
  }
  private func suggestionButton(index: Int, text: String) -> some View {
    Button(text) {
      state.quickEntryText = text
      run()
    }.buttonStyle(.plain).padding(.horizontal, 8).background(
      index == selectedSuggestion ? Color.accentColor.opacity(0.16) : Color.clear)
  }
}
