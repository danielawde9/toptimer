import Foundation

/// Synchronous admission keeps UI work from racing store shutdown.
@MainActor public final class AppOperationOwner {
  public private(set) var accepting = true
  private var tasks: [UUID: Task<Void, Never>] = [:]
  private var tail: Task<Void, Never>?
  private var tailID: UUID?
  private let capacity: Int
  public var pendingCount: Int { tasks.count }
  public init(capacity: Int = 128) { self.capacity = max(1, min(128, capacity)) }
  @discardableResult public func submit(_ operation: @escaping @MainActor () async -> Void) -> Bool
  {
    guard accepting, tasks.count < capacity else { return false }
    let id = UUID()
    let previous = tail
    let task = Task {
      defer {
        tasks.removeValue(forKey: id)
        if tailID == id { tail = nil; tailID = nil }
      }
      await previous?.value
      guard accepting, !Task.isCancelled else { return }
      await operation()
    }
    tasks[id] = task
    tail = task
    tailID = id
    return true
  }
  public func stopAccepting() { accepting = false }
  public func drain() async {
    stopAccepting()
    let pending = Array(tasks.values)
    for task in pending { task.cancel() }
    for task in pending { await task.value }
  }
}
