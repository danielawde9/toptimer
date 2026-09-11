import Foundation
import TopTimerDomain

public struct StatusTitle: Equatable, Sendable {
  public let text: String
  public let showsIcon: Bool
  public let accessibilityLabel: String
}

public enum StatusTitleFormatter {
  public static func format(
    timer: TimerItem?, now: Date,
    mode: StatusDisplayMode = .compact, uses24HourTime: Bool = true
  ) -> StatusTitle {
    guard let timer else { return .init(text: "", showsIcon: true, accessibilityLabel: "TopTimer") }
    let seconds: TimeInterval
    if timer.kind == .countdown {
      seconds = max(0, timer.deadline?.timeIntervalSince(now) ?? timer.remaining ?? 0)
    } else {
      seconds = max(0, now.timeIntervalSince(timer.startedAt ?? now) - timer.accumulatedPause)
    }
    let text: String
    switch mode {
    case .compact: text = timer.state == .idle ? "" : duration(seconds, includeSeconds: false)
    case .seconds: text = duration(seconds, includeSeconds: true)
    case .clock:
      text =
        timer.deadline.map { WallClockDisplay.string($0, uses24HourTime: uses24HourTime) }
        ?? duration(seconds, includeSeconds: false)
    }
    let suffix = timer.kind == .countdown ? "remaining" : "elapsed"
    let state = timer.state == .paused ? "Paused, " : ""
    return .init(
      text: text, showsIcon: true,
      accessibilityLabel: text.isEmpty ? timer.title : "\(timer.title), \(state)\(text) \(suffix)")
  }

  private static func duration(_ seconds: TimeInterval, includeSeconds: Bool) -> String {
    let value = Int(seconds.rounded(.down))
    let hours = value / 3600
    let minutes = value / 60 % 60
    let secs = value % 60
    if includeSeconds { return String(format: "%02d:%02d:%02d", hours, minutes, secs) }
    return hours > 0
      ? String(format: "%d:%02d:%02d", hours, minutes, secs)
      : String(format: "%d:%02d", minutes, secs)
  }
}

public enum StatusDisplayMode: Sendable, Equatable { case compact, seconds, clock }
