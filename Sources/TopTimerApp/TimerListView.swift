import SwiftUI
import TopTimerDomain

public struct TimerListView: View {
    @ObservedObject var state: AppState
    public init(state: AppState) { self.state = state }
    public var body: some View { VStack(alignment: .leading, spacing: 0) { if state.activeTimers.isEmpty { VStack(spacing: 6) { Image(systemName: "timer"); Text("No active timers"); Text("Create one above to begin.").font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding() } else { ForEach(state.activeTimers.prefix(100), id: \.id) { timer in TimerRow(timer: timer, state: state); Divider() } } }.frame(width: 340).accessibilityIdentifier("timer-list") }
}
private struct TimerRow: View { let timer: TimerItem; @ObservedObject var state: AppState
    var body: some View { HStack { VStack(alignment: .leading) { Text(timer.title.isEmpty ? "Stopwatch" : timer.title); if !timer.details.isEmpty { Text(timer.details).font(.caption).foregroundStyle(.secondary) }; if !timer.tags.isEmpty { Text(timer.tags.map { "#\($0)" }.joined(separator: " ")).font(.caption2).foregroundStyle(.secondary) } }; Spacer(); Button { Task { _ = await state.restart(timer.id) } } label: { Image(systemName: "arrow.clockwise") }.help("Restart"); Button { Task { _ = await state.pause(timer.id) } } label: { Image(systemName: "pause.fill") }.help("Pause"); Button(role: .destructive) { Task { _ = await state.softDelete(timer.id) } } label: { Image(systemName: "trash") }.help("Delete") }.padding(8) }
}
