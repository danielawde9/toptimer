import Foundation

public enum StartupRecovery: Equatable, Sendable {
  case none
  case activeTimers(count: Int)
  case completedWhileClosed(count: Int, activeCount: Int)

  public var message: String? {
    switch self {
    case .none: return nil
    case let .activeTimers(count): return "\(count) active timer\(count == 1 ? "" : "s") recovered"
    case let .completedWhileClosed(count, activeCount):
      let finished = "\(count) timer\(count == 1 ? "" : "s") finished while TopTimer was closed"
      return activeCount == 0 ? finished : "\(finished); \(activeCount) still active"
    }
  }
}
