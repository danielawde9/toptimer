import AppKit
import SwiftUI

public struct QuickEntryView: View {
    @ObservedObject var state: AppState; @FocusState private var focused: Bool; @State private var selectedSuggestion = 0; @Binding var showingList: Bool
    public init(state: AppState, showingList: Binding<Bool>) { self.state = state; _showingList = showingList }
    public var body: some View { VStack(alignment: .leading, spacing: 6) { HStack(spacing: 6) { Image(systemName: "hourglass").accessibilityLabel("TopTimer"); TextField("15m Focus", text: $state.quickEntryText).textFieldStyle(.plain).fontDesign(.monospaced).focused($focused).onSubmit(run).accessibilityIdentifier("quick-entry"); Button(action: run) { Text("Run") }.keyboardShortcut(.return, modifiers: []) .accessibilityLabel("Run timer") }.padding(8)
        if let error = state.inlineError { Text(error).font(.caption).foregroundStyle(.red).padding(.horizontal, 8) }
        suggestions
        HStack(spacing: 6) { Button { } label: { Image(systemName: "gearshape") }.help("Settings").accessibilityLabel("Settings"); Button { state.quickEntryText = ""; focused = true } label: { Image(systemName: "plus") }.help("New timer"); Button { showingList.toggle() } label: { Image(systemName: "list.bullet") }.help("Show timers"); Spacer(); if let timer = state.priorityTimer { Button(role: .destructive) { Task { await state.softDelete(timer.id) } } label: { Image(systemName: "trash") }.help("Delete priority timer"); Button { Task { if timer.state == .running { _ = await state.pause(timer.id) } else { _ = await state.resume(timer.id) } } } label: { Image(systemName: timer.state == .running ? "pause.fill" : "play.fill") }.help(timer.state == .running ? "Pause priority timer" : "Resume priority timer") }; Button { NSApplication.shared.terminate(nil) } label: { Image(systemName: "power") }.help("Quit TopTimer") }.buttonStyle(.borderless).padding(8) }.frame(width: 280).onAppear { focused = true }.onChange(of: state.quickEntryText) { text in Task { await state.refreshSuggestions(query: text) } } }
    private func run() { Task { await state.create(command: state.quickEntryText) } }
    @ViewBuilder private var suggestions: some View { if focused && !state.suggestions.isEmpty { ForEach(Array(state.suggestions.prefix(20).enumerated()), id: \.offset) { pair in suggestionButton(index: pair.offset, text: pair.element) } } }
    private func suggestionButton(index: Int, text: String) -> some View { Button(text) { state.quickEntryText = text; run() }.buttonStyle(.plain).padding(.horizontal, 8).background(index == selectedSuggestion ? Color.accentColor.opacity(0.16) : Color.clear) }
}
