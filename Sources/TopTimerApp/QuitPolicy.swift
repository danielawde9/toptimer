import TopTimerDomain

public enum QuitDecision: Equatable, Sendable {
  case quitImmediately
  case confirmPersistence(running: Int, paused: Int)
}

public enum QuitPolicy {
  public static func decide(activeTimers: [TimerItem]) -> QuitDecision {
    let running = activeTimers.filter { $0.state == .running }.count
    let paused = activeTimers.filter { $0.state == .paused }.count
    guard running + paused > 0 else { return .quitImmediately }
    return .confirmPersistence(running: running, paused: paused)
  }
}
