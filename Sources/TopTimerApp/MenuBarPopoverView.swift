import SwiftUI
import TopTimerDomain

struct MenuBarPopoverView: View {
  @ObservedObject var state: AppState
  let openSettings: () -> Void
  let openTimers: () -> Void
  let quit: () -> Void
  @FocusState private var focused: Bool
  var body: some View {
    VStack(spacing: 0) {
      entryBar
      Divider()
      ScrollView { content.padding(12).frame(maxWidth: .infinity, alignment: .leading) }
        .frame(maxHeight: 200)
      Divider()
      footer
    }.frame(width: 304).onAppear { focused = state.priorityTimer == nil }
  }
  private var entryBar: some View {
    HStack(spacing: 8) {
      HStack(spacing: 6) {
        Image(systemName: "timer").foregroundStyle(.secondary).accessibilityHidden(true)
        TextField("Start a timer", text: $state.quickEntryText)
          .textFieldStyle(.plain).focused($focused).onSubmit(start)
          .accessibilityLabel("Start a timer")
      }.padding(.horizontal, 10).padding(.vertical, 7)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
      Button("Start", action: start).buttonStyle(.borderedProminent).controlSize(.regular)
        .keyboardShortcut(.return, modifiers: [])
    }.padding(12)
  }
  private var footer: some View {
    HStack(spacing: 4) {
      FooterButton(title: "Settings", symbol: "gearshape", action: openSettings)
      FooterButton(title: "All timers", symbol: "list.bullet", action: openTimers)
      Spacer()
      FooterButton(title: "Quit", symbol: "power", action: quit)
    }.padding(.horizontal, 8).padding(.vertical, 6)
  }
  @ViewBuilder private var content: some View {
    if let timer = state.priorityTimer {
      runningCard(timer)
    } else {
      idleList
    }
  }
  private func runningCard(_ timer: TimerItem) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(timer.title.isEmpty ? "Timer" : timer.title).font(.headline).lineLimit(1)
      Text(TimerRowTiming(timer: timer, at: .now).text)
        .monospacedDigit().font(.system(size: 30, weight: .semibold, design: .rounded))
      HStack(spacing: 8) {
        Button(timer.state == .paused ? "Resume" : "Pause") {
          state.perform { _ = timer.state == .paused ? await state.resume(timer.id) : await state.pause(timer.id) }
        }.buttonStyle(.bordered)
        Button(timer.kind == .stopwatch ? "Finish" : "Stop") {
          state.perform { _ = timer.kind == .stopwatch ? await state.complete(timer.id) : await state.cancel(timer.id) }
        }.buttonStyle(.bordered)
        Spacer()
        Button("Start another") { focused = true }.buttonStyle(.link)
      }
    }
  }
  private var idleList: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("No timer running").font(.subheadline).foregroundStyle(.secondary).padding(.bottom, 4)
      ForEach(Array(state.suggestions.prefix(3).enumerated()), id: \.offset) { pair in
        SuggestionRow(text: pair.element) { state.quickEntryText = pair.element; start() }
      }
    }
  }
  private func start() { let entry = state.quickEntryText; state.perform { await state.create(command: entry) } }
}

private struct SuggestionRow: View {
  let text: String
  let action: () -> Void
  @State private var hovering = false
  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Image(systemName: "play.fill").font(.caption).foregroundStyle(.tint).accessibilityHidden(true)
        Text(text).lineLimit(1)
        Spacer(minLength: 0)
      }.padding(.horizontal, 8).padding(.vertical, 6).contentShape(Rectangle())
    }.buttonStyle(.plain)
      .background(hovering ? Color.primary.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
      .onHover { hovering = $0 }
  }
}

private struct FooterButton: View {
  let title: String
  let symbol: String
  let action: () -> Void
  @State private var hovering = false
  var body: some View {
    Button(action: action) {
      Label(title, systemImage: symbol).font(.callout).padding(.horizontal, 8).padding(.vertical, 5)
        .contentShape(Rectangle())
    }.buttonStyle(.plain).foregroundStyle(.secondary)
      .background(hovering ? Color.primary.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
      .onHover { hovering = $0 }
  }
}
