import SwiftUI
import TopTimerDomain

public struct TimerListView: View {
    @ObservedObject var state: AppState
    public init(state: AppState) { self.state = state }
    public var body: some View { ScrollView { VStack(alignment: .leading, spacing: 0) { if state.activeTimers.isEmpty { VStack(spacing: 6) { Image(systemName: "timer"); Text("No active timers"); Text("Create one above to begin.").font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding() } else { ForEach(state.activeTimers.prefix(100), id: \.id) { timer in TimerRow(timer: timer, state: state); Divider() } } } }.frame(width: 340, height: 260).accessibilityIdentifier("timer-list") }
}
private struct TimerRow: View { let timer: TimerItem; @ObservedObject var state: AppState
    var body: some View { HStack { VStack(alignment: .leading, spacing: 3) { Text(timer.title.isEmpty ? "Stopwatch" : timer.title); if !timer.details.isEmpty { Text(timer.details).lineLimit(1).font(.caption).foregroundStyle(.secondary) }; Text(summary).font(.caption2).foregroundStyle(.secondary); if !timer.tags.isEmpty { Text(timer.tags.map { "#\($0)" }.joined(separator: " ")).font(.caption2).foregroundStyle(.secondary) }; ProgressView(value: progress).tint(.accentColor) }; Spacer(); Button { Task { await state.selectEditor(timer.id) } } label: { Image(systemName: "pencil") }.help("Edit"); Button { Task { _ = await state.duplicate(timer.id) } } label: { Image(systemName: "plus.square.on.square") }.help("Duplicate"); Button { Task { _ = await state.restart(timer.id) } } label: { Image(systemName: "arrow.clockwise") }.help("Restart"); Button { Task { _ = timer.state == .running ? await state.pause(timer.id) : await state.resume(timer.id) } } label: { Image(systemName: timer.state == .running ? "pause.fill" : "play.fill") }.help(timer.state == .running ? "Pause" : "Resume"); if timer.state == .completed { Button { Task { _ = await state.acknowledge(timer.id) } } label: { Image(systemName: "checkmark") }.help("Acknowledge") }; Button(role: .destructive) { Task { _ = await state.softDelete(timer.id) } } label: { Image(systemName: "trash") }.help("Delete") }.padding(8) }
    private var progress: Double { guard let duration = timer.duration, let deadline = timer.deadline else { return 0 }; return min(1, max(0, 1 - deadline.timeIntervalSinceNow / duration)) }
    private var summary: String { if let deadline = timer.deadline { return "Ends \(deadline.formatted(date: .omitted, time: .shortened))" }; return timer.kind == .stopwatch ? "Stopwatch" : "Paused" }
}
