import SwiftUI
import TopTimerDomain

public struct NowView: View {
  @ObservedObject private var state: AppState
  private let openHistory: () -> Void
  private let openSettings: () -> Void
  private let openTimerList: () -> Void
  private let requestQuit: () -> Void
  private let focusEntry: Bool
  @FocusState private var entryFocused: Bool

  public init(state: AppState, focusEntry: Bool = false, openHistory: @escaping () -> Void = {}, openSettings: @escaping () -> Void = {}, openTimerList: @escaping () -> Void = {}, requestQuit: @escaping () -> Void = {}) {
    self.state = state; self.focusEntry = focusEntry; self.openHistory = openHistory
    self.openSettings = openSettings; self.openTimerList = openTimerList; self.requestQuit = requestQuit
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("TopTimer").font(.title2.bold()); Spacer()
        Button("History", action: openHistory); Button("Settings", action: openSettings)
        Button("Quit", action: requestQuit)
      }
      HStack {
        TextField("Start a timer, e.g. 25m focus", text: $state.quickEntryText)
          .focused($entryFocused).onSubmit { startEntry() }.accessibilityLabel("Timer entry")
        Button("Start", action: startEntry).keyboardShortcut(.return, modifiers: [])
      }
      if state.activeTimers.isEmpty {
        Text("Start a timer").font(.headline)
        HStack {
          example("25m focus"); example("10m tea"); example("stopwatch reading")
        }
      }
      recovery
      if let timer = primaryTimer { primary(timer) }
      if state.activeTimers.count > 1 {
        Text("Other active timers").font(.headline)
        ForEach(state.activeTimers.filter { $0.id != primaryTimer?.id }.prefix(3), id: \.id) { timer in secondary(timer) }
        if state.activeTimers.count > 4 { Button("Show all active timers", action: openTimerList) }
      }
      Spacer(minLength: 0)
    }.padding(24).frame(minWidth: 460, minHeight: 360, alignment: .topLeading)
      .onAppear { entryFocused = focusEntry && state.activeTimers.isEmpty }.onExitCommand {}
  }

  private func example(_ text: String) -> some View {
    Button(text) { state.quickEntryText = text; startEntry() }.buttonStyle(.link)
  }

  @ViewBuilder private var recovery: some View {
    if let message = state.startupRecovery.message {
      HStack { Text(message).font(.callout); Button("History") { state.dismissStartupRecovery(); openHistory() } }
        .padding(8).background(.secondary.opacity(0.12)).cornerRadius(6)
    }
    if state.notificationStatus == .authorizationDenied || state.notificationStatus == .notAuthorized(.denied) {
      HStack {
        Text("Notifications are denied.").font(.caption).foregroundStyle(.orange)
        Button("Open Settings", action: openSettings)
      }
    }
    if let error = state.inlineError {
      HStack { Text(error).font(.caption).foregroundStyle(.red); Button("Retry") { entryFocused = true } }
    }
  }

  private func primary(_ timer: TimerItem) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(timer.title.isEmpty ? (timer.kind == .stopwatch ? "Stopwatch" : "Timer") : timer.title).font(.title3.bold())
      TimelineView(.periodic(from: .now, by: 1)) { context in
        let timing = TimerRowTiming(timer: timer, at: context.date)
        VStack(alignment: .leading, spacing: 6) {
          Text(timer.state == .paused ? "Paused" : "Running").accessibilityAddTraits(.isHeader)
          Text(timing.text).monospacedDigit().font(.title2).accessibilityLabel("\(timer.state == .paused ? "Paused" : "Running"), \(timing.text)")
          ProgressView(value: timing.progress)
          HStack {
            if timer.state == .paused { Button("Resume") { state.perform { _ = await state.resume(timer.id) } } }
            else { Button("Pause") { state.perform { _ = await state.pause(timer.id) } } }
            if timer.kind == .stopwatch { Button("Finish") { state.perform { _ = await state.complete(timer.id) } } }
            else { Button("Stop") { state.perform { _ = await state.cancel(timer.id) } } }
          }
        }
      }
    }.accessibilityElement(children: .contain)
  }

  private func secondary(_ timer: TimerItem) -> some View {
    HStack {
      VStack(alignment: .leading) { Text(timer.title.isEmpty ? "Untitled timer" : timer.title); Text(timer.state == .paused ? "Paused" : "Running").font(.caption) }
      Spacer(); Text(TimerRowTiming(timer: timer, at: .now).text).monospacedDigit()
      Menu("Actions") {
        if timer.state == .paused { Button("Resume") { state.perform { _ = await state.resume(timer.id) } } }
        if timer.state == .running { Button("Pause") { state.perform { _ = await state.pause(timer.id) } } }
        Button(timer.kind == .stopwatch ? "Finish" : "Stop") { state.perform { _ = await (timer.kind == .stopwatch ? state.complete(timer.id) : state.cancel(timer.id)) } }
      }
    }.padding(.vertical, 4)
  }

  private func startEntry() { let command = state.quickEntryText; state.perform { await state.create(command: command) } }
  private var primaryTimer: TimerItem? { state.priorityTimer ?? state.activeTimers.first }
}
