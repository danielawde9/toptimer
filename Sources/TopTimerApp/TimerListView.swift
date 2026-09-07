import SwiftUI
import TopTimerDomain

public struct TimerRowActionVisibility: Equatable, Sendable {
  public let isHovered: Bool
  public let isFocused: Bool
  public var showsActions: Bool { isHovered || isFocused }
}

public struct TimerListView: View {
  @ObservedObject var state: AppState
  @State private var recentlyDeleted = false
  public init(state: AppState, recentlyDeleted: Bool = false) {
    self.state = state
    _recentlyDeleted = State(initialValue: recentlyDeleted)
  }
  public var body: some View {
    VStack(spacing: 0) {
      Picker("Timer collection", selection: $recentlyDeleted) {
        Text("Timers").tag(false)
        Text("Recently Deleted").tag(true)
      }.pickerStyle(.segmented).labelsHidden().padding(8)
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          if recentlyDeleted {
            if state.deletedTimers.isEmpty {
              Text("No recently deleted timers").foregroundStyle(.secondary).padding()
            }
            ForEach(state.deletedTimers.prefix(100), id: \.id) { timer in
              HStack {
                Text(timer.title.isEmpty ? "Untitled timer" : timer.title)
                Spacer()
                Button("Restore") { state.perform { _ = await state.restore(timer.id) } }
                  .buttonStyle(.borderless).help("Restore timer").accessibilityLabel(
                    "Restore \(timer.title)"
                  ).frame(minHeight: 28)
              }.padding(8)
              Divider()
            }
          } else {
            if state.activeTimers.isEmpty {
              Text("No active timers").foregroundStyle(.secondary).padding()
            }
            ForEach(state.activeTimers.prefix(100), id: \.id) { timer in
              TimerRow(timer: timer, state: state)
              Divider()
            }
          }
        }
      }
    }.frame(width: 340, height: 260).accessibilityIdentifier("timer-list")
  }
}

private struct TimerRow: View {
  let timer: TimerItem
  @ObservedObject var state: AppState
  @State private var hovered = false
  @FocusState private var focused: Bool
  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      let timing = TimerRowTiming(timer: timer, at: context.date)
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text(
            timer.title.isEmpty ? (timer.kind == .stopwatch ? "Stopwatch" : "Timer") : timer.title
          ).lineLimit(1)
          Text(timing.text).monospacedDigit().foregroundStyle(
            Color(red: 111.0 / 255, green: 155.0 / 255, blue: 1))
          if !summary.isEmpty { Text(summary).font(.caption2).foregroundStyle(.secondary) }
          if !timer.tags.isEmpty {
            Text(timer.tags.map { "#\($0)" }.joined(separator: " ")).font(.caption2)
              .foregroundStyle(.secondary).lineLimit(1)
          }
          GeometryReader { geometry in
            ZStack(alignment: .leading) {
              Color.secondary.opacity(0.2)
              Color.accentColor.frame(width: geometry.size.width * timing.progress)
            }
          }.frame(height: 2)
        }
        Spacer(minLength: 4)
        Menu("Actions") { actions }
          .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 60, height: 28)
          .help("Timer actions").accessibilityLabel("Actions for \(timer.title)")
          .focused($focused)
          // Keep the native menu in the focus and accessibility tree.
          .opacity(
            TimerRowActionVisibility(isHovered: hovered, isFocused: focused).showsActions ? 1 : 0.01
          )
          .accessibilityHidden(false)
      }.padding(8).onHover { hovered = $0 }
    }
  }
  @ViewBuilder private var actions: some View {
    Button("Edit") { state.perform { await state.selectEditor(timer.id) } }
    Button("Duplicate") { state.perform { _ = await state.duplicate(timer.id) } }
    Button("Restart") { state.perform { _ = await state.restart(timer.id) } }
    if timer.state == .running { Button("Pause") { state.perform { _ = await state.pause(timer.id) } } }
    if timer.state == .paused { Button("Resume") { state.perform { _ = await state.resume(timer.id) } } }
    if timer.state == .idle { Button("Start") { state.perform { _ = await state.start(timer.id) } } }
    if timer.state == .completed {
      Button("Acknowledge") { state.perform { _ = await state.acknowledge(timer.id) } }
    }
    Button("Delete", role: .destructive) { state.perform { _ = await state.softDelete(timer.id) } }
  }
  private var summary: String {
    let recurrence: String
    switch timer.recurrence {
    case .none: recurrence = ""
    case .interval: recurrence = "Repeats after completion"
    case .daily: recurrence = "Daily"
    case .weekdays: recurrence = "Weekdays"
    case .weekly: recurrence = "Weekly"
    case .selectedWeekdays: recurrence = "Selected days"
    }
    let end = timer.deadline.map { "Ends \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
    return [end, recurrence].filter { !$0.isEmpty }.joined(separator: " · ")
  }
}
