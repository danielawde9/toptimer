import Foundation
import TopTimerDomain
import TopTimerPersistence

public struct SequenceStep: Codable, Equatable, Identifiable, Sendable {
  public var id = UUID()
  public var title: String
  public var minutes: Double
  public init(title: String, minutes: Double) {
    self.title = title
    self.minutes = minutes
  }
}

public struct SequenceSession: Codable, Equatable, Sendable {
  public var steps: [SequenceStep]
  public var repeats: Bool
  public var index: Int
  public var cycle: Int
  public var timer: TimerItem?
  public var previousTimerID: UUID?
  public var schedulePending = true
  func validate() throws {
    guard !steps.isEmpty, steps.count <= 100, steps.indices.contains(index), cycle > 0,
      Set(steps.map(\.id)).count == steps.count,
      steps.allSatisfy({
        !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.title.count <= 200
          && $0.minutes.isFinite && $0.minutes > 0 && $0.minutes <= 525_600
      })
    else { throw SequenceError.invalidSteps }
    if let timer {
      guard timer.kind == .countdown, timer.recurrence == .none
      else { throw SequenceError.invalidSteps }
    }
  }
}

enum SequenceError: LocalizedError {
  case invalidSteps, alreadyRunning, busy
  var errorDescription: String? {
    switch self {
    case .invalidSteps:
      "Add 1–100 named tasks with a duration greater than zero and at most one year."
    case .alreadyRunning: "Stop the current sequence before starting another."
    case .busy: "A sequence operation is already running. Try again."
    }
  }
}

@MainActor public protocol SequenceStorage {
  func load() throws -> SequenceSession?
  func save(_ session: SequenceSession?) throws
}

@MainActor public final class MemorySequenceStorage: SequenceStorage {
  private var value: SequenceSession?
  public init() {}
  public func load() throws -> SequenceSession? { value }
  public func save(_ session: SequenceSession?) throws { value = session }
}

@MainActor public final class JSONSequenceStorage: SequenceStorage {
  private let url: URL
  public init(url: URL) { self.url = url }
  public func load() throws -> SequenceSession? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let data = try Data(contentsOf: url)
    guard data.count <= 1_000_000 else { throw SequenceError.invalidSteps }
    let session = try JSONDecoder().decode(SequenceSession.self, from: data)
    try session.validate()
    return session
  }
  public func save(_ session: SequenceSession?) throws {
    if let session {
      try session.validate()
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONEncoder().encode(session).write(to: url, options: .atomic)
    } else if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }
}

/// Save the planned timer ID before inserting it. Recovery retries that same ID,
/// so a crash between the two writes cannot create parallel copies of a step.
@MainActor final class SequenceCoordinator {
  private let repository: any TimerRepository
  private let storage: any SequenceStorage
  private var loaded = false
  private var busy = false
  private(set) var session: SequenceSession?
  init(repository: any TimerRepository, storage: any SequenceStorage) {
    self.repository = repository
    self.storage = storage
  }
  private func load() throws {
    if !loaded {
      session = try storage.load()
      loaded = true
    }
  }
  private func save(_ value: SequenceSession?) throws {
    try storage.save(value)
    session = value
  }
  func start(
    steps: [SequenceStep], repeats: Bool, at date: Date, alertName: String? = nil,
    alertVolume: Double = 1
  ) async throws -> [TimerItem] {
    guard !busy else { throw SequenceError.busy }
    busy = true
    defer { busy = false }
    try load()
    guard session?.timer == nil else { throw SequenceError.alreadyRunning }
    var value = SequenceSession(
      steps: steps, repeats: repeats, index: 0, cycle: 1, timer: nil, previousTimerID: nil)
    try value.validate()
    var timer = try TimerItem.countdown(
      title: steps[0].title, duration: steps[0].minutes * 60, alertName: alertName,
      alertVolume: alertVolume, createdAt: date)
    try timer.start(at: date)
    value.timer = timer
    try save(value)
    return try await ensurePlannedTimer()
  }
  func reconcile(at date: Date) async throws -> [TimerItem] {
    guard !busy else { return [] }
    busy = true
    defer { busy = false }
    try load()
    guard let planned = session?.timer else {
      try await acknowledgePrevious(at: date)
      return []
    }
    let scheduled = try await ensurePlannedTimer()
    let current = try await repository.timer(id: planned.id)
    if current.state == .completed {
      return scheduled + (try await advance(after: current, at: date))
    }
    if current.deletedAt != nil || current.state == .cancelled || current.state == .acknowledged {
      var value = session!
      value.timer = nil
      value.previousTimerID = nil
      try save(value)
    } else {
      session?.timer = current
    }
    return scheduled
  }
  private func ensurePlannedTimer() async throws -> [TimerItem] {
    guard let planned = session?.timer else { return [] }
    var current: TimerItem
    do { current = try await repository.timer(id: planned.id) } catch TimerRepositoryError
      .timerNotFound
    { current = try await repository.insert(planned) }
    try await acknowledgePrevious(at: planned.createdAt)
    return session?.schedulePending == true && current.state == .running && current.deletedAt == nil
      ? [current] : []
  }
  private func acknowledgePrevious(at date: Date) async throws {
    guard let previous = session?.previousTimerID else { return }
    var timer = try await repository.timer(id: previous)
    if timer.state == .completed {
      try timer.acknowledge(at: max(date, timer.lastTransitionAt ?? date))
      try await repository.update(timer)
    }
    var value = session!
    value.previousTimerID = nil
    try save(value)
  }
  private func advance(after timer: TimerItem, at date: Date) async throws -> [TimerItem] {
    var value = session!
    if value.index == value.steps.count - 1 && !value.repeats {
      value.timer = nil
      value.previousTimerID = timer.id
      value.schedulePending = false
      try save(value)
      try await acknowledgePrevious(at: date)
      return []
    }
    value.index += 1
    if value.index == value.steps.count {
      value.index = 0
      value.cycle += 1
    }
    let step = value.steps[value.index]
    var next = try TimerItem.countdown(
      title: step.title, duration: step.minutes * 60, alertName: timer.alertName,
      alertVolume: timer.alertVolume, createdAt: date)
    try next.start(at: date)
    value.timer = next
    value.previousTimerID = timer.id
    value.schedulePending = true
    try save(value)
    return try await ensurePlannedTimer()
  }
  func markScheduled(_ id: UUID) throws {
    guard var value = session, value.timer?.id == id else { return }
    value.schedulePending = false
    try save(value)
  }
  func stop(at date: Date) async throws -> UUID? {
    guard !busy else { throw SequenceError.busy }
    busy = true
    defer { busy = false }
    try load()
    let id = session?.timer?.id
    if let id {
      do {
        let timer = try await repository.timer(id: id)
        if timer.state == .running || timer.state == .paused {
          _ = try await repository.cancel(id: id, at: date)
        }
      } catch TimerRepositoryError.timerNotFound {}
    }
    if var value = session {
      value.timer = nil
      value.previousTimerID = nil
      try save(value)
    }
    return id
  }
  func clear() throws {
    guard !busy else { throw SequenceError.busy }
    try save(nil)
    loaded = true
  }
}
