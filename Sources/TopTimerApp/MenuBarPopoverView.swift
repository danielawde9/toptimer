import SwiftUI
import TopTimerDomain

struct MenuBarPopoverView: View {
  @ObservedObject var state: AppState
  let openSettings: () -> Void
  let openTimers: () -> Void
  let quit: () -> Void
  var openNow: (() -> Void)? = nil
  var openSequences: (() -> Void)? = nil
  var closePopover: () -> Void = {}
  @State private var focused = false
  @State private var selectedSuggestion = -1
  @State private var focusRequest = 0

  var body: some View {
    VStack(spacing: 0) {
      entryBar
      Divider()
      ScrollView {
        VStack(spacing: 10) {
          if let error = state.inlineError {
            TimerOperationMessage(message: error, dismiss: state.dismissInlineError)
          }
          if let error = state.sequenceError { Text(error).font(.caption).foregroundStyle(.orange) }
          if let timer = state.displayedTimer { runningCard(timer) }
          if state.displayedTimer == nil || selectedSuggestion >= 0 || !state.quickEntryText.isEmpty
          {
            idleList
          }
        }.padding(12).frame(maxWidth: .infinity)
      }.frame(maxWidth: .infinity, maxHeight: .infinity)
      Divider()
      footer
    }.frame(width: 320, height: 300).background(Color(nsColor: .windowBackgroundColor))
      .onAppear { focused = true }
      .onChange(of: state.quickEntryText) { text in
        selectedSuggestion = -1
        state.perform { await state.refreshSuggestions(query: text) }
      }
  }

  private var entryBar: some View {
    HStack(spacing: 8) {
      HStack(spacing: 6) {
        Image(systemName: "timer").foregroundStyle(.secondary).accessibilityHidden(true)
        QuickEntryTextField(
          text: $state.quickEntryText, selectedSuggestion: $selectedSuggestion,
          suggestions: state.quickEntryExamples, focus: focused, command: handle,
          focusRequest: focusRequest, placeholder: "Start a timer"
        )
        .frame(height: 20)
      }.padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12)))
      Button("Start", action: start).buttonStyle(.borderedProminent).help("Start")
        .keyboardShortcut(.return, modifiers: [])
    }.padding(12)
  }

  private var footer: some View {
    VStack(spacing: 2) {
      HStack(spacing: 4) {
        FooterButton(title: "Settings", symbol: "gearshape", action: openSettings)
        FooterButton(title: "All timers", symbol: "list.bullet", action: openTimers)
        Spacer(minLength: 0)
        FooterButton(title: "Quit", symbol: "power", action: quit)
      }
      if let openSequences {
        Button("Sequences", systemImage: "list.number", action: openSequences).buttonStyle(
          .borderless
        ).font(.caption).help("Sequences")
      }
      if let openNow {
        Button("Open window", systemImage: "macwindow", action: openNow)
          .buttonStyle(.borderless).font(.caption).help("Open window")
      }
    }.padding(.horizontal, 8).padding(.vertical, 8)
  }

  private func runningCard(_ timer: TimerItem) -> some View {
    VStack(spacing: 10) {
      if let session = state.sequenceSession, session.timer?.id == timer.id {
        Text("Task \(session.index + 1) of \(session.steps.count) · Loop \(session.cycle)").font(
          .caption
        ).foregroundStyle(.secondary)
      }
      Text(timer.title.isEmpty ? (timer.kind == .stopwatch ? "Stopwatch" : "Timer") : timer.title)
        .font(.headline).lineLimit(1)
      TimelineView(.periodic(from: .now, by: 1)) { context in
        TimerTimeBadge(timer: timer, date: context.date, prominent: true)
      }
      HStack(spacing: 8) {
        Button(timer.state == .paused ? "Resume" : "Pause") {
          state.perform {
            _ = timer.state == .paused ? await state.resume(timer.id) : await state.pause(timer.id)
          }
        }.buttonStyle(.borderedProminent).help(timer.state == .paused ? "Resume" : "Pause")
        Button(timer.kind == .stopwatch ? "Finish" : "Stop") {
          state.perform {
            _ =
              timer.kind == .stopwatch
              ? await state.complete(timer.id) : await state.cancel(timer.id)
          }
        }.buttonStyle(.bordered).help(timer.kind == .stopwatch ? "Finish" : "Stop")
        Spacer(minLength: 0)
        Button("Start another") {
          focused = true
          focusRequest += 1
        }
        .buttonStyle(.borderless).help("Start another")
      }
    }.frame(maxWidth: .infinity)
  }

  private var idleList: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(state.displayedTimer == nil ? "No timer running" : "Suggestions").font(.subheadline)
        .foregroundStyle(.secondary).padding(.bottom, 6)
      ForEach(Array(state.quickEntryExamples.enumerated()), id: \.element) { index, text in
        HStack {
          Button {
            state.quickEntryText = text
            start()
          } label: {
            HStack(spacing: 8) {
              Image(systemName: "play.circle.fill").foregroundStyle(.tint).accessibilityHidden(true)
              Text(text).lineLimit(1)
              Spacer(minLength: 0)
            }.padding(.vertical, 5)
          }.buttonStyle(.borderless).help(text)
            .background(index == selectedSuggestion ? Color.accentColor.opacity(0.16) : Color.clear)
          if state.suggestions.contains(text) {
            Button("Remove") { state.perform { await state.removeSuggestion(text) } }
              .buttonStyle(.borderless).help("Remove saved suggestion \(text)").accessibilityLabel(
                "Remove saved suggestion \(text)")
          }
        }
      }
      if !state.suggestions.isEmpty {
        Button("Clear saved suggestions") { state.perform { _ = await state.clearSuggestions() } }
          .buttonStyle(.borderless).font(.caption).help("Clear saved suggestions")
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }

  private func handle(_ effect: QuickEntryEffect) {
    switch effect {
    case .run(let selected):
      if selected, state.quickEntryExamples.indices.contains(selectedSuggestion) {
        state.quickEntryText = state.quickEntryExamples[selectedSuggestion]
      }
      start()
    case .clear:
      state.quickEntryText = ""
      selectedSuggestion = -1
    case .close: closePopover()
    case .togglePriority: state.perform { await state.togglePriorityTimer() }
    case .passThrough, .selectSuggestion: break
    }
  }

  private func start() {
    let entry = state.quickEntryText
    state.perform { await state.create(command: entry) }
  }
}

private struct FooterButton: View {
  let title: String
  let symbol: String
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      Label(title, systemImage: symbol).font(.callout)
    }.buttonStyle(.borderless).foregroundStyle(.secondary).help(title)
  }
}
