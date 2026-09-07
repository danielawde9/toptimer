import AppKit
import SwiftUI
import TopTimerDomain

extension HistoryEntry: Identifiable {}

public struct HistoryView: View {
  @ObservedObject private var state: AppState
  @State private var from = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
  @State private var through = Date.now
  @State private var query = ""
  @State private var selected: HistoryEntry?
  @State private var showingDeleted = false
  @State private var editing: HistoryEntry?

  public init(state: AppState) { self.state = state }
  public var body: some View {
    VStack(spacing: 0) {
      HStack {
        DatePicker("From", selection: $from, displayedComponents: .date)
        DatePicker("Through", selection: $through, displayedComponents: .date)
        TextField("Search title, description, or tag", text: $query)
        Button("Apply") { reload() }
        Button("Export CSV…") { exportCSV() }.disabled(state.historyPage.entries.isEmpty)
      }.padding()
      Picker("History collection", selection: $showingDeleted) {
        Text("History").tag(false); Text("Recently Deleted").tag(true)
      }.pickerStyle(.segmented).padding(.horizontal)
      if state.historyLoading {
        VStack { ProgressView(); Text("Loading history…"); Button("Cancel") {} }.frame(maxHeight: .infinity)
      } else if let error = state.inlineError {
        VStack { Text(error); Button("Try again") { reload() } }.frame(maxHeight: .infinity)
      } else if entries.isEmpty {
        VStack { Text(showingDeleted ? "No deleted history" : "No history in this range"); Button("Clear filters") { query = ""; reload() } }.frame(maxHeight: .infinity)
      } else {
        Table(entries, selection: Binding(get: { selected?.id }, set: { id in selected = entries.first { $0.id == id } })) {
          TableColumn("Timer") { Text($0.title.isEmpty ? "Untitled timer" : $0.title) }
          TableColumn("Tags") { Text($0.tags.map { "#\($0)" }.joined(separator: " ")) }
          TableColumn("Ended") { Text($0.endedAt.formatted()) }
          TableColumn("Duration") { Text(Self.duration($0.elapsedSeconds)).monospacedDigit() }
        }
        HStack {
          if let selected {
            if showingDeleted { Button("Recover") { state.perform { _ = await state.recoverHistory(selected.id) } } }
            else { Button("Edit") { editing = selected }; Button("Delete", role: .destructive) { state.perform { _ = await state.deleteHistory(selected) } } }
          }
          Spacer()
          if !showingDeleted, state.historyPage.nextCursor != nil { Button("Load more") { state.perform { await state.loadHistory(from: from, through: through, query: query, append: true) } } }
        }.padding()
      }
    }.frame(minWidth: 680, minHeight: 460).accessibilityIdentifier("history-view")
      .onAppear { reload() }
      .sheet(item: $editing) { entry in HistoryEditor(entry: entry, state: state) { editing = nil } }
  }
  private var entries: [HistoryEntry] { showingDeleted ? state.recentlyDeletedHistory : state.historyPage.entries }
  private func reload() { state.perform { await state.loadHistory(from: from, through: through, query: query) } }
  private func exportCSV() {
    let panel = NSSavePanel(); panel.allowedContentTypes = [.commaSeparatedText]; panel.nameFieldStringValue = "TopTimer History.csv"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do { try CSVExporter().export(Array(state.historyPage.entries.prefix(200))).data(using: .utf8)?.write(to: url, options: .atomic) }
    catch { reload() }
  }
  private static func duration(_ seconds: TimeInterval) -> String { Duration.seconds(seconds).formatted(.time(pattern: .hourMinuteSecond)) }
}

private struct HistoryEditor: View {
  let entry: HistoryEntry
  @ObservedObject var state: AppState
  let close: () -> Void
  @State private var title: String
  @State private var details: String
  @State private var tags: String
  init(entry: HistoryEntry, state: AppState, close: @escaping () -> Void) {
    self.entry = entry; self.state = state; self.close = close
    _title = State(initialValue: entry.title); _details = State(initialValue: entry.details)
    _tags = State(initialValue: entry.tags.joined(separator: ", "))
  }
  var body: some View {
    Form {
      TextField("Title", text: $title)
      TextField("Description", text: $details, axis: .vertical).lineLimit(3...8)
      TextField("Tags (comma separated)", text: $tags)
      HStack { Spacer(); Button("Cancel", action: close); Button("Save changes") { let values = tags.split(separator: ",", maxSplits: 11).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }; state.perform { if await state.editHistory(entry, title: title, details: details, tags: values) { close() } } }.keyboardShortcut(.defaultAction) }
    }.padding().frame(width: 440).accessibilityLabel("Edit history record")
  }
}
