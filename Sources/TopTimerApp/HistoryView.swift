import AppKit
import SwiftUI
import TopTimerDomain

extension HistoryEntry: Identifiable {}

public struct HistoryView: View {
  @ObservedObject private var state: AppState
  @State private var selected: HistoryEntry?
  @State private var selectedTab: HistoryTab = .history
  @State private var editing: HistoryEntry?

  public init(state: AppState) { self.state = state }
  public var body: some View {
    VStack(spacing: 0) {
      Picker("History section", selection: $selectedTab) {
        Text("Active").tag(HistoryTab.active)
        Text("History").tag(HistoryTab.history)
        Text("Recently Deleted").tag(HistoryTab.deleted)
      }.pickerStyle(.segmented).padding()
      switch selectedTab {
      case .active: activeContent
      case .history: historyContent(showingDeleted: false)
      case .deleted: historyContent(showingDeleted: true)
      }
      if let error = state.exportError { Text(error).foregroundStyle(.red).padding() }
    }.frame(minWidth: 680, minHeight: 460).accessibilityIdentifier("history-view")
      .onAppear { reload() }
      .sheet(item: $editing) { entry in HistoryEditor(entry: entry, state: state) { editing = nil }
      }
  }
  private var activeContent: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 8) {
        if state.activeTimers.isEmpty {
          Text("No active timers").foregroundStyle(.secondary).padding()
        } else {
          ForEach(state.activeTimers.prefix(100), id: \.id) { timer in
            ActiveHistoryTimerRow(timer: timer, state: state)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal)
          }
        }
      }.padding(.bottom)
    }
  }
  @ViewBuilder private func historyContent(showingDeleted: Bool) -> some View {
    if !showingDeleted {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Toggle("All time", isOn: $state.historyControls.allTime)
          Spacer()
          Button("Export CSV…") { exportCSV() }.disabled(state.historyPage.entries.isEmpty)
        }
        if !state.historyControls.allTime {
          HStack {
            DatePicker("From", selection: $state.historyControls.from, displayedComponents: .date)
            DatePicker("Through", selection: $state.historyControls.through, displayedComponents: .date)
          }
        }
        HStack {
          TextField("Search title, description, or tag", text: $state.historyControls.query)
          Button("Apply") { reload() }.keyboardShortcut(.defaultAction)
        }
      }.padding(.horizontal).padding(.bottom, 8)
    }
    if state.historyLoading {
      VStack { ProgressView(); Text("Loading history…"); Button("Cancel") { state.cancelHistoryLoad() } }
        .frame(maxHeight: .infinity)
    } else if let error = state.historyError {
      VStack { Text(error); Button("Try again") { reload() } }.frame(maxHeight: .infinity)
    } else if entries(showingDeleted: showingDeleted).isEmpty {
      VStack {
        Text(showingDeleted ? "No deleted history" : "No history in this range")
        if !showingDeleted { Button("Show all history") { state.perform { await state.showAllHistory() } } }
      }.frame(maxHeight: .infinity)
    } else {
      historyTable(showingDeleted: showingDeleted)
    }
  }
  private func historyTable(showingDeleted: Bool) -> some View {
    let values = entries(showingDeleted: showingDeleted)
    return VStack(spacing: 0) {
      Table(values, selection: Binding(
        get: { selected?.id }, set: { id in selected = values.first { $0.id == id } })) {
        TableColumn("Timer") { Text($0.title.isEmpty ? "Untitled timer" : $0.title) }
        TableColumn("Tags") { Text($0.tags.map { "#\($0)" }.joined(separator: " ")) }
        TableColumn("Ended") { Text(WallClockDisplay.string($0.endedAt, uses24HourTime: state.preferences.uses24HourTime, includesDate: true)) }
        TableColumn("Duration") { Text(Self.duration($0.elapsedSeconds)).monospacedDigit() }
      }.frame(maxHeight: .infinity)
      HStack {
        if let selected {
          if showingDeleted { Button("Recover") { state.perform { _ = await state.recoverHistory(selected.id) } } }
          else {
            Button("Edit") { editing = selected }
            Button("Delete", role: .destructive) { state.perform { _ = await state.deleteHistory(selected) } }
          }
        }
        Spacer()
        if !showingDeleted, state.historyPage.nextCursor != nil {
          Button("Next page") { state.perform { await state.loadNextHistoryPage() } }
        }
      }.padding()
    }
  }
  private func entries(showingDeleted: Bool) -> [HistoryEntry] {
    showingDeleted ? state.recentlyDeletedHistory : state.historyPage.entries
  }
  private func reload() {
    state.perform { await state.applyHistoryControls() }
  }
  private func exportCSV() {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.commaSeparatedText]
    panel.nameFieldStringValue = "TopTimer History.csv"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    state.perform { await state.exportHistory(to: url) }
  }
  private static func duration(_ seconds: TimeInterval) -> String {
    Duration.seconds(seconds).formatted(.time(pattern: .hourMinuteSecond))
  }
}

private enum HistoryTab: Hashable { case active, history, deleted }

private struct ActiveHistoryTimerRow: View {
  let timer: TimerItem
  @ObservedObject var state: AppState
  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      let timing = TimerRowTiming(timer: timer, at: context.date)
      HStack {
        VStack(alignment: .leading) {
          Text(timer.title.isEmpty ? (timer.kind == .stopwatch ? "Stopwatch" : "Timer") : timer.title)
          Text(timer.state == .paused ? "Paused" : "Running").font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        Text(timing.text).monospacedDigit()
        if timer.state == .paused {
          Button("Resume") { state.perform { _ = await state.resume(timer.id) } }.buttonStyle(.borderless)
        } else {
          Button("Pause") { state.perform { _ = await state.pause(timer.id) } }.buttonStyle(.borderless)
        }
        Button(timer.kind == .stopwatch ? "Finish" : "Stop") {
          state.perform { _ = await (timer.kind == .stopwatch ? state.complete(timer.id) : state.cancel(timer.id)) }
        }.buttonStyle(.borderless)
      }.frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
    }
  }
}

private struct HistoryEditor: View {
  let entry: HistoryEntry
  @ObservedObject var state: AppState
  let close: () -> Void
  @State private var title: String
  @State private var details: String
  @State private var tags: String
  init(entry: HistoryEntry, state: AppState, close: @escaping () -> Void) {
    self.entry = entry
    self.state = state
    self.close = close
    _title = State(initialValue: entry.title)
    _details = State(initialValue: entry.details)
    _tags = State(initialValue: entry.tags.joined(separator: ", "))
  }
  var body: some View {
    Form {
      TextField("Title", text: $title)
      TextField("Description", text: $details, axis: .vertical).lineLimit(3...8)
      TextField("Tags (comma separated)", text: $tags)
      if let error = state.historyError { Text(error).foregroundStyle(.red) }
      HStack {
        Spacer()
        Button("Cancel", action: close)
        Button("Save changes") {
          let values = tags.split(separator: ",", maxSplits: 11).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
          }
          state.perform {
            if await state.editHistory(entry, title: title, details: details, tags: values) {
              close()
            }
          }
        }.keyboardShortcut(.defaultAction)
      }
    }.padding().frame(width: 440).accessibilityLabel("Edit history record")
  }
}
