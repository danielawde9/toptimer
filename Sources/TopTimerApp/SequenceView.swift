import SwiftUI
import TopTimerDomain

public struct SequenceView: View {
  @ObservedObject private var state: AppState
  @State private var steps = [
    SequenceStep(title: "Task 1", minutes: 15), SequenceStep(title: "Task 2", minutes: 15),
    SequenceStep(title: "Task 3", minutes: 30),
  ]
  @State private var repeats = true
  public init(state: AppState) { self.state = state }
  private var current: TimerItem? {
    guard let planned = state.sequenceSession?.timer else { return nil }
    return state.activeTimers.first { $0.id == planned.id } ?? planned
  }
  public var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Sequential timers").font(.title2.bold())
      Text("Tasks run one after another. Durations are in minutes.").foregroundStyle(.secondary)
      if let current, let session = state.sequenceSession {
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text("Task \(session.index + 1) of \(session.steps.count) · Loop \(session.cycle)")
              .font(.caption).foregroundStyle(.secondary)
            Text(current.title).font(.headline)
          }
          Spacer()
          TimelineView(.periodic(from: .now, by: 1)) { context in
            TimerTimeBadge(timer: current, date: context.date)
          }
        }
        HStack {
          Button(current.state == .paused ? "Resume sequence" : "Pause sequence") {
            state.perform {
              _ =
                current.state == .paused
                ? await state.resume(current.id) : await state.pause(current.id)
            }
          }.buttonStyle(.borderedProminent).help(
            current.state == .paused ? "Resume sequence" : "Pause sequence")
          Button("Stop sequence") { state.perform { _ = await state.stopSequence() } }.help(
            "Stop sequence")
        }
      }
      ScrollView {
        VStack(spacing: 10) {
          ForEach($steps) { $step in
            HStack(spacing: 10) {
              Text("\((steps.firstIndex { $0.id == step.id } ?? 0) + 1)").foregroundStyle(
                .secondary
              ).frame(width: 20)
              TextField("Task name", text: $step.title).textFieldStyle(.roundedBorder)
              TextField("Minutes", value: $step.minutes, format: .number).textFieldStyle(
                .roundedBorder
              ).frame(width: 80)
              Text("min").foregroundStyle(.secondary)
              Button("Remove") { steps.removeAll { $0.id == step.id } }
                .buttonStyle(.borderless).help("Remove \(step.title)").accessibilityLabel(
                  "Remove \(step.title)")
            }
          }
        }
      }.frame(maxHeight: .infinity).disabled(current != nil)
      HStack {
        Button("Add task") {
          steps.append(SequenceStep(title: "Task \(steps.count + 1)", minutes: 15))
        }
        .help("Add task").disabled(current != nil || steps.count >= 100)
        Spacer()
        Toggle("Repeat endlessly", isOn: $repeats).disabled(current != nil)
      }
      if let status = state.notificationStatus, status != .scheduled {
        Text("Notifications are disabled. Timers still advance while TopTimer is running.").font(
          .caption
        ).foregroundStyle(.secondary)
      }
      if let error = state.sequenceError {
        Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
      }
      if let error = state.inlineError {
        TimerOperationMessage(message: error, dismiss: state.dismissInlineError)
      }
      Divider()
      HStack {
        Text(
          current == nil
            ? "Start begins with the first task." : "Stop the sequence to edit its tasks."
        ).font(.caption).foregroundStyle(.secondary)
        Spacer()
        Button("Start sequence") {
          state.perform { _ = await state.startSequence(steps: steps, repeats: repeats) }
        }
        .buttonStyle(.borderedProminent).help("Start sequence").disabled(
          current != nil || state.clearingData)
      }
    }.padding(20).frame(minWidth: 560, minHeight: 440).background(
      Color(nsColor: .windowBackgroundColor)
    )
    .onAppear {
      if let saved = state.sequenceSession {
        steps = saved.steps
        repeats = saved.repeats
      }
    }
    .onChange(of: state.sequenceSession == nil) { empty in
      if empty {
        steps = [
          SequenceStep(title: "Task 1", minutes: 15), SequenceStep(title: "Task 2", minutes: 15),
          SequenceStep(title: "Task 3", minutes: 30),
        ]
        repeats = true
      }
    }
  }
}
