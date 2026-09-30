import AppKit
import SwiftUI
import TopTimerDomain

extension HistoryEntry: Identifiable {}

public struct HistoryView: View {
  @ObservedObject private var state: AppState
  @State private var selectedIDs: Set<UUID> = []
  @State private var selectedTab: HistoryTab = .history
  @State private var editing: HistoryEntry?
  @State private var showingDeleteAllConfirmation = false
  public init(state: AppState) { self.state = state }
  public var body: some View {
    VStack(spacing: 0) {
      Picker("History section", selection: $selectedTab) {
        Text("Active").tag(HistoryTab.active)
        Text("History").tag(HistoryTab.history)
        Text("Recently Deleted").tag(HistoryTab.deleted)
      }.pickerStyle(.segmented).labelsHidden().padding()
      switch selectedTab {
      case .active: activeContent
      case .history: historyContent(showingDeleted: false)
      case .deleted: historyContent(showingDeleted: true)
      }
      if let error = state.exportError { Text(error).foregroundStyle(.red).padding() }
    }.frame(minWidth: 680, minHeight: 460).background(Color(nsColor: .windowBackgroundColor))
      .accessibilityIdentifier("history-view")
      .onAppear { reload() }
      .onChange(of: selectedTab) { _ in selectedIDs.removeAll() }
      .alert("Delete all history?", isPresented: $showingDeleteAllConfirmation) {
        Button("Cancel", role: .cancel) {}
        Button("Delete All", role: .destructive) {
          state.perform {
            if await state.deleteAllHistory() { selectedIDs.removeAll() }
          }
        }
      } message: {
        Text("All completed history will move to Recently Deleted. Active timers are not affected.")
      }
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
          Button("Export CSV…") { exportCSV() }.disabled(state.historyPage.entries.isEmpty).help(
            "Export CSV")
        }
        if !state.historyControls.allTime {
          HStack {
            DatePicker("From", selection: $state.historyControls.from, displayedComponents: .date)
            DatePicker(
              "Through", selection: $state.historyControls.through, displayedComponents: .date)
          }
        }
        HStack {
          TextField("Search title, description, or tag", text: $state.historyControls.query)
            .textFieldStyle(.roundedBorder)
          Button("Apply") { reload() }.keyboardShortcut(.defaultAction).buttonStyle(
            .borderedProminent
          ).help("Apply")
        }
      }.padding(.horizontal).padding(.bottom, 8)
    }
    if state.historyLoading {
      VStack {
        ProgressView()
        Text("Loading history…")
        Button("Cancel") { state.cancelHistoryLoad() }
      }
      .frame(maxHeight: .infinity)
    } else if let error = state.historyError {
      VStack {
        Text(error)
        Button("Try again") { reload() }
      }.frame(maxHeight: .infinity)
    } else if entries(showingDeleted: showingDeleted).isEmpty {
      if showingDeleted {
        VStack(spacing: 12) {
          Image(systemName: "trash").font(.system(size: 40)).foregroundStyle(.tertiary)
          Text("No deleted history").foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        EmptyStateView(
          title: "No history in this range", symbol: "doc.text",
          detail: "Try a different date range, or show all history to view your completed timers.",
          actionTitle: "Show all history"
        ) { state.perform { await state.showAllHistory() } }
      }
    } else {
      historyTable(showingDeleted: showingDeleted)
    }
  }
  private func historyTable(showingDeleted: Bool) -> some View {
    let values = entries(showingDeleted: showingDeleted)
    return VStack(spacing: 0) {
      Table(
        values,
        selection: Binding(
          get: { selectedIDs }, set: { selectedIDs = $0 })
      ) {
        TableColumn("Timer") { Text($0.title.isEmpty ? "Untitled timer" : $0.title) }
        TableColumn("Tags") { Text($0.tags.map { "#\($0)" }.joined(separator: " ")) }
        TableColumn("Ended") {
          Text(
            WallClockDisplay.string(
              $0.endedAt, uses24HourTime: state.preferences.uses24HourTime, includesDate: true))
        }
        TableColumn("Duration") { Text(Self.duration($0.elapsedSeconds)).monospacedDigit() }
      }.frame(maxHeight: .infinity)
      HStack {
        let selected = values.filter { selectedIDs.contains($0.id) }
        if showingDeleted {
          Button("Recover Selected") {
            state.perform {
              if await state.recoverHistory(selected.map(\.id)) { selectedIDs.removeAll() }
            }
          }.disabled(selected.isEmpty).help("Recover Selected")
        } else {
          Button("Edit") {
            if selected.count == 1 { editing = selected.first }
          }.disabled(selected.count != 1).help("Edit")
          Button("Delete Selected") {
            state.perform {
              if await state.deleteHistory(selected) { selectedIDs.removeAll() }
            }
          }.disabled(selected.isEmpty).help("Delete Selected")
          if !values.isEmpty {
            Button("Delete All…") { showingDeleteAllConfirmation = true }.help(
              "Delete All")
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
          Text(
            timer.title.isEmpty ? (timer.kind == .stopwatch ? "Stopwatch" : "Timer") : timer.title)
          Text(statusText).font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        Text(timing.text).monospacedDigit()
        if timer.state == .paused {
          Button("Resume") { state.perform { _ = await state.resume(timer.id) } }.buttonStyle(
            .borderless)
          terminalAction
        } else if timer.state == .running {
          Button("Pause") { state.perform { _ = await state.pause(timer.id) } }.buttonStyle(
            .borderless)
          terminalAction
        }
      }.frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
    }
  }
  @ViewBuilder private var terminalAction: some View {
    if timer.kind == .stopwatch {
      Button("Finish") { state.perform { _ = await state.complete(timer.id) } }.buttonStyle(
        .borderless)
    } else {
      Button("Stop") { state.perform { _ = await state.cancel(timer.id) } }.buttonStyle(.borderless)
    }
  }
  private var statusText: String {
    switch timer.state {
    case .running: "Running"
    case .paused: "Paused"
    case .completed: "Finished"
    case .cancelled: "Stopped"
    case .acknowledged: "Completed"
    case .idle: "Not started"
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
    VStack(spacing: 0) {
      Form {
        TextField("Title", text: $title)
        TextField("Description", text: $details, axis: .vertical).lineLimit(3...8)
        TextField("Tags (comma separated)", text: $tags)
        if let error = state.historyError { Text(error).foregroundStyle(.red) }
      }.padding(20)
      Divider()
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
        }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).help("Save changes")
      }.padding(16)
    }.frame(width: 440).background(Color(nsColor: .windowBackgroundColor))
      .accessibilityLabel("Edit history record")
  }
}
