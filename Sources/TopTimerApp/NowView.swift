import SwiftUI
import TopTimerDomain

public struct NowView: View {
  @ObservedObject private var state: AppState
  private let navigate: ((TopTimerWindow) -> Void)?
  private let focusEntry: Bool
  @FocusState private var entryFocused: Bool

  public init(
    state: AppState, focusEntry: Bool = false, navigate: ((TopTimerWindow) -> Void)? = nil
  ) {
    self.state = state
    self.focusEntry = focusEntry
    self.navigate = navigate
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text("TopTimer").font(.title.bold())
        HStack(spacing: 10) {
          TextField("Start a timer, e.g. 25m focus", text: $state.quickEntryText)
            .textFieldStyle(.roundedBorder).focused($entryFocused).onSubmit(startEntry)
            .accessibilityLabel("Timer entry")
          Button("Start", action: startEntry).buttonStyle(.borderedProminent).help("Start")
            .keyboardShortcut(.return, modifiers: [])
        }.controlSize(.large)
        recovery
        if state.activeTimers.isEmpty {
          VStack(alignment: .leading, spacing: 12) {
            Text("Start a timer").font(.headline)
            ForEach(state.quickEntryExamples, id: \.self) { text in
              Button(text) {
                state.quickEntryText = text
                startEntry()
              }
              .buttonStyle(.borderless).help(text)
            }
          }
        }
        if let timer = primaryTimer { primary(timer) }
        let otherTimers = state.activeTimers.filter { $0.id != primaryTimer?.id }
        if !otherTimers.isEmpty {
          Divider()
          Text("Other active timers").font(.headline)
          ForEach(otherTimers, id: \.id) { timer in
            secondary(timer)
            Divider()
          }
        }
      }.padding(24)
    }.frame(minWidth: 460, minHeight: 360, alignment: .topLeading)
      .background(Color(nsColor: .windowBackgroundColor))
      .onAppear { entryFocused = focusEntry && state.activeTimers.isEmpty }
  }

  @ViewBuilder private var recovery: some View {
    if let message = state.startupRecovery.message {
      HStack {
        Text(message).font(.callout)
        if let navigate {
          Button("View history") {
            state.dismissStartupRecovery()
            navigate(.history)
          }.help("View recovered history")
        } else {
          Button("Dismiss") { state.dismissStartupRecovery() }
        }
      }.padding(8).background(
        Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }
    if state.notificationStatus == .authorizationDenied
      || state.notificationStatus == .notAuthorized(.denied)
    {
      Text("Notifications are denied. Enable TopTimer notifications in macOS System Settings.")
        .font(.caption).foregroundStyle(.orange)
    }
    if let error = state.inlineError {
      TimerOperationMessage(message: error, dismiss: state.dismissInlineError)
    }
  }

  private func primary(_ timer: TimerItem) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        VStack(alignment: .leading, spacing: 6) {
          Text(title(timer)).font(.title2.bold()).lineLimit(1)
          TimerStatusLabel(timer: timer)
        }
        Spacer()
        TimelineView(.periodic(from: .now, by: 1)) { context in
          TimerTimeBadge(timer: timer, date: context.date, prominent: true)
        }
      }
      if timer.kind == .countdown {
        TimelineView(.periodic(from: .now, by: 1)) { context in
          ProgressView(value: TimerRowTiming(timer: timer, at: context.date).progress)
        }
      }
      HStack(spacing: 8) {
        controls(timer)
        if timer.state == .idle {
          Button("Start") { state.perform { _ = await state.start(timer.id) } }.help("Start timer")
        }
        if timer.state == .completed {
          Button("Acknowledge") { state.perform { _ = await state.acknowledge(timer.id) } }.help(
            "Acknowledge")
        }
      }
    }.accessibilityElement(children: .contain)
  }

  private func secondary(_ timer: TimerItem) -> some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(title(timer)).fontWeight(.semibold).lineLimit(1)
        TimerStatusLabel(timer: timer)
      }
      Spacer(minLength: 4)
      TimelineView(.periodic(from: .now, by: 1)) { context in
        TimerTimeBadge(timer: timer, date: context.date)
      }
      controls(timer)
    }.padding(.vertical, 4).controlSize(.small)
  }

  @ViewBuilder private func controls(_ timer: TimerItem) -> some View {
    if timer.state == .paused || timer.state == .running {
      Button(timer.state == .paused ? "Resume" : "Pause") {
        state.perform {
          _ = timer.state == .paused ? await state.resume(timer.id) : await state.pause(timer.id)
        }
      }.buttonStyle(.borderedProminent).help(timer.state == .paused ? "Resume" : "Pause")
      Button(timer.kind == .stopwatch ? "Finish" : "Stop") {
        state.perform {
          _ =
            timer.kind == .stopwatch ? await state.complete(timer.id) : await state.cancel(timer.id)
        }
      }.help(timer.kind == .stopwatch ? "Finish" : "Stop")
    }
  }

  private func title(_ timer: TimerItem) -> String {
    timer.title.isEmpty ? (timer.kind == .stopwatch ? "Stopwatch" : "Timer") : timer.title
  }
  private func startEntry() {
    let command = state.quickEntryText
    state.perform { await state.create(command: command) }
  }
  private var primaryTimer: TimerItem? { state.displayedTimer ?? state.activeTimers.first }
}
