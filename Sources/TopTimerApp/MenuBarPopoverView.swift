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
      HStack(spacing: 8) {
        TextField("Start a timer", text: $state.quickEntryText)
          .focused($focused).onSubmit(start).accessibilityLabel("Start a timer")
        Button("Start", action: start).keyboardShortcut(.return, modifiers: [])
      }.padding(12)
      Divider()
      ScrollView { content.padding(12) }.frame(maxHeight: 190)
      Divider()
      HStack {
        Button("Settings", action: openSettings)
        Button("All timers", action: openTimers)
        Spacer()
        Button("Quit", action: quit)
      }.buttonStyle(.plain).padding(12)
    }.frame(width: 304).onAppear { focused = state.priorityTimer == nil }
  }
  @ViewBuilder private var content: some View {
    if let timer = state.priorityTimer {
      VStack(alignment: .leading, spacing: 10) {
        Text(timer.title.isEmpty ? "Timer" : timer.title).font(.headline).lineLimit(1)
        Text(TimerRowTiming(timer: timer, at: .now).text).monospacedDigit().font(.title2)
        HStack {
          Button(timer.state == .paused ? "Resume" : "Pause") { state.perform { _ = timer.state == .paused ? await state.resume(timer.id) : await state.pause(timer.id) } }
          Button(timer.kind == .stopwatch ? "Finish" : "Stop") { state.perform { _ = timer.kind == .stopwatch ? await state.complete(timer.id) : await state.cancel(timer.id) } }
          Spacer()
          Button("Start another timer") { focused = true }.buttonStyle(.link)
        }
      }
    } else {
      VStack(alignment: .leading, spacing: 8) {
        Text("No timer running").foregroundStyle(.secondary)
        ForEach(Array(state.suggestions.prefix(3).enumerated()), id: \.offset) { pair in
          Button(pair.element) { state.quickEntryText = pair.element; start() }.buttonStyle(.plain)
        }
      }
    }
  }
  private func start() { let entry = state.quickEntryText; state.perform { await state.create(command: entry) } }
}
