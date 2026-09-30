import SwiftUI
import TopTimerDomain

struct TimerTimeBadge: View {
  let timer: TimerItem
  let date: Date
  var prominent = false

  var body: some View {
    VStack(spacing: 2) {
      Text(TimerRowTiming(timer: timer, at: date).text.components(separatedBy: " ")[0])
        .font(.system(size: prominent ? 30 : 18, weight: .semibold, design: .rounded))
        .monospacedDigit().foregroundStyle(
          timer.state == .paused ? Color.secondary : Color.accentColor)
      Text(timer.kind == .countdown ? "remaining" : "elapsed")
        .font(.caption).foregroundStyle(.secondary)
    }
    .padding(.horizontal, prominent ? 24 : 12).padding(.vertical, prominent ? 10 : 6)
    .background(
      Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: prominent ? 28 : 8)
    )
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(TimerRowTiming(timer: timer, at: date).text)
  }
}

struct TimerStatusLabel: View {
  let timer: TimerItem
  var body: some View {
    Label {
      Text(timer.state.displayTitle)
    } icon: {
      Circle().fill(timer.state == .paused ? Color.orange : Color.accentColor).frame(
        width: 7, height: 7)
    }.font(.caption).foregroundStyle(.secondary)
  }
}

extension TimerState {
  var displayTitle: String {
    switch self {
    case .running: "Running"
    case .paused: "Paused"
    case .completed: "Finished"
    case .cancelled: "Stopped"
    case .acknowledged: "Completed"
    case .idle: "Not started"
    }
  }
}

struct TimerOperationMessage: View {
  let message: String
  let dismiss: () -> Void
  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
      Text(message).font(.caption).fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
      Button("Dismiss", action: dismiss).buttonStyle(.borderless).help("Dismiss")
    }.padding(8).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
  }
}
