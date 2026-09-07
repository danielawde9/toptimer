import Foundation
import TopTimerDomain

public struct TimerRowTiming: Equatable, Sendable {
  public let text: String
  public let progress: Double
  public init(timer: TimerItem, at date: Date) {
    let value = timer.kind == .countdown ? timer.remaining(at: date) : timer.elapsed(at: date)
    let seconds = Int(min(TimeInterval(Int.max / 2), max(0, value ?? 0)))
    let time =
      seconds >= 3600
      ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
      : String(format: "%02d:%02d", seconds / 60, seconds % 60)
    text = time + (timer.kind == .countdown ? " remaining" : " elapsed")
    progress = timer.duration.map { min(1, max(0, 1 - (value ?? 0) / $0)) } ?? 0
  }
}
