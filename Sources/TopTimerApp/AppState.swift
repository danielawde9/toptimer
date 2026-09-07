import Combine
import Foundation
import TopTimerDomain
import TopTimerPersistence
import TopTimerSystem

/// The small system boundary used by application state. UI tests provide this
/// protocol instead of talking to UserNotifications.
public protocol TimerNotificationScheduling: Sendable {
  func schedule(_ timer: TimerItem) async throws -> NotificationScheduleStatus
  func scheduleCreatedTimer(_ timer: TimerItem) async throws -> NotificationScheduleStatus
  func validateSound(name: String?) async throws
  func cancel(timerID: UUID) async throws
}

extension TimerNotificationScheduling {
  public func scheduleCreatedTimer(_ timer: TimerItem) async throws -> NotificationScheduleStatus {
    try await schedule(timer)
  }
  public func validateSound(name: String?) async throws {}
}

extension NotificationController: TimerNotificationScheduling {
  public func scheduleCreatedTimer(_ timer: TimerItem) async throws -> NotificationScheduleStatus {
    guard timer.kind == .countdown, let deadline = timer.deadline else { return .scheduled }
    return try await schedule(
      timerID: timer.id, title: timer.title, details: timer.details, fireDate: deadline,
      requestAuthorizationForFirstSuccessfulCreation: true, alertName: timer.alertName)
  }
  public func schedule(_ timer: TimerItem) async throws -> NotificationScheduleStatus {
    guard let deadline = timer.deadline else { return .scheduled }
    return try await schedule(
      timerID: timer.id, title: timer.title, details: timer.details, fireDate: deadline,
      alertName: timer.alertName)
  }
}

/// Main-actor owned presentation state. Persistence remains the source of truth:
/// every mutation is stored before it is reflected to the UI.
@MainActor
public final class AppState: ObservableObject {
  public let operations: AppOperationOwner
  public func perform(_ operation: @escaping @MainActor () async -> Void) {
    if !operations.submit(operation) {
      inlineError = "Timer work is unavailable while closing or busy. Try again when ready."
    }
  }
  @Published public private(set) var activeTimers: [TimerItem] = []
  @Published public private(set) var deletedTimers: [TimerItem] = []
  @Published public var quickEntryText = ""
  @Published public private(set) var inlineError: String?
  @Published public private(set) var notificationStatus: NotificationScheduleStatus?
  @Published public private(set) var priorityTimer: TimerItem?
  @Published public private(set) var selectedEditorTimer: TimerItem?
  @Published public private(set) var historyPage = HistoryPage(entries: [], nextCursor: nil)
  @Published public private(set) var recentlyDeletedHistory: [HistoryEntry] = []
  @Published public private(set) var historyLoading = false
  @Published public private(set) var historyError: String?
  @Published public private(set) var exportError: String?
  @Published public private(set) var reportEntries: [HistoryEntry] = []
  @Published public private(set) var reportSummary = ReportSummary.empty
  @Published public private(set) var reportsLoading = false
  @Published public private(set) var reportsError: String?
  private var historyRequest = UUID()
  private var reportsRequest = UUID()
  private var historyFilter: (from: Date?, through: Date?, query: String) = (nil, nil, "")
  private var reportsFilter: (from: Date?, through: Date?) = (nil, nil)
  private var reportsRequested = false
  @Published public private(set) var suggestions: [String] = []
  @Published public private(set) var settingsError: String?
  @Published public private(set) var sleepError: String?
  @Published public private(set) var retentionError: String?
  @Published public private(set) var loginError: String?
  @Published public private(set) var hotKeyError: String?
  @Published public private(set) var soundError: String?
  @Published public var preferences = AppPreferences() {
    didSet {
      guard !restoringPreferences, preferences != oldValue else { return }
      do {
        try settingsStore?.save(preferences)
        settingsError = nil
      } catch {
        restoringPreferences = true
        preferences = oldValue
        restoringPreferences = false
        settingsError = "Could not save settings. Previous values are active. Retry your change."
        return
      }
      updateSleepAssertion()
      if preferences.retention != oldValue.retention { perform { await self.applyRetention() } }
    }
  }
  private var restoringPreferences = false
  private let settingsStore: TopTimerSettingsStore?
  private let sleepController: SleepAssertionController?
  private var lastRetentionDay: Date?
  private var refreshing = false

  private let repository: any TimerRepository
  private let notifications: any TimerNotificationScheduling
  private let alertSounds: AlertSoundController?
  private let presets: (any PresetRepository)?
  private let now: () -> Date
  private let parser: ((Date) -> TimerParser)?

  public init(
    repository: any TimerRepository,
    notifications: any TimerNotificationScheduling,
    presets: (any PresetRepository)? = nil,
    alertSounds: AlertSoundController? = nil,
    operations: AppOperationOwner = AppOperationOwner(),
    settingsStore: TopTimerSettingsStore? = nil,
    initialPreferences: TopTimerSettings = .defaults,
    sleepController: SleepAssertionController? = nil,
    now: @escaping () -> Date = { .now },
    parser: ((Date) -> TimerParser)? = nil
  ) {
    self.repository = repository
    self.operations = operations
    self.notifications = notifications
    self.alertSounds = alertSounds
    self.presets = presets
    self.now = now
    self.parser = parser
    self.settingsStore = settingsStore
    self.preferences = initialPreferences
    self.sleepController = sleepController
  }

  public func updateSleepAssertion() {
    do {
      try sleepController?.setRunningTimerCount(
        priorityTimer == nil ? 0 : 1, enabled: preferences.preventsSleep)
      sleepError = nil
    } catch {
      sleepError = "Could not update sleep prevention. Retry sleep prevention in Settings."
    }
  }

  public func changeLogin(_ enabled: Bool, apply: (Bool) -> String?) -> String? {
    var value = preferences
    value.launchesAtLogin = enabled
    loginError = commitSystemSetting(value) { apply(enabled) }
    return loginError
  }

  public func changeHotKey(
    _ shortcut: Shortcut, slot: HotKeySlot, apply: (HotKeySlot, Shortcut) -> String?
  ) -> String? {
    var value = preferences
    if slot == .quickEntry {
      value.quickEntryShortcut = shortcut
    } else {
      value.pauseResumeShortcut = shortcut
    }
    hotKeyError = commitSystemSetting(value) { apply(slot, shortcut) }
    return hotKeyError
  }

  private func commitSystemSetting(_ candidate: TopTimerSettings, apply: () -> String?) -> String? {
    do { try settingsStore?.save(candidate) } catch {
      return "Could not save settings. Previous values remain active. Retry the change."
    }
    if let error = apply() {
      do { try settingsStore?.save(preferences) } catch {
        settingsError =
          "Could not restore saved settings. Retry the previous selection before relaunch."
      }
      return error
    }
    restoringPreferences = true
    preferences = candidate
    restoringPreferences = false
    return nil
  }

  @discardableResult public func changeDefaultSound(_ name: String?) async -> Bool {
    do {
      if let name { _ = try AlertSoundIdentity.sourceURL(name: name) }
      try await notifications.validateSound(name: name)
      preferences.defaultAlertName = name
      guard settingsError == nil else { return false }
      soundError = nil
      return true
    } catch {
      soundError =
        "Could not use that sound. Previous sound is active. Choose another sound or retry import."
      return false
    }
  }

  public func applyRetention() async {
    guard let days = preferences.retention.days,
      let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now())
    else {
      retentionError = nil
      return
    }
    do {
      for _ in 0..<50 {
        try Task.checkCancellation()
        let removed = try await repository.purgeHistory(endedBefore: cutoff)
        if removed < 200 {
          retentionError = nil
          lastRetentionDay = Calendar.current.startOfDay(for: now())
          return
        }
      }
      retentionError = "Removed 10,000 expired records. Retry retention to continue cleanup."
    } catch { retentionError = "Could not remove expired history. Retry retention in Settings." }
  }

  /// Creates a running timer. The observable order is persist, schedule,
  /// publish; notification failures do not undo durable timer state.
  public func create(command: String) async {
    inlineError = nil
    let submittedAt = now()
    do {
      let parsed = try
        (parser?(submittedAt)
        ?? TimerParser(now: submittedAt, uses24HourTime: preferences.uses24HourTime)).parse(command)
      var timer: TimerItem
      if parsed.kind == .stopwatch {
        timer = try TimerItem.stopwatch(
          title: parsed.title, tags: parsed.tags, alertName: preferences.defaultAlertName,
          alertVolume: preferences.alertVolume, createdAt: submittedAt)
      } else {
        timer = try TimerItem.countdown(
          title: parsed.title,
          duration: parsed.duration ?? 1,
          tags: parsed.tags,
          alertName: preferences.defaultAlertName,
          alertVolume: preferences.alertVolume,
          createdAt: submittedAt
        )
      }
      try timer.start(at: submittedAt)
      let persisted = try await repository.insert(timer)

      if persisted.kind == .countdown {
        do {
          notificationStatus = try await notifications.scheduleCreatedTimer(persisted)
        } catch {
          notificationStatus = nil
          inlineError = "Timer saved, but notification scheduling failed."
        }
      }
      await publishActive()
      // Presets are a convenience record. The durable timer has already
      // been published, so a preset failure cannot affect creation.
      _ = try? await presets?.record(command: command, tags: parsed.tags, at: submittedAt)
      quickEntryText = ""
      await refreshSuggestions(query: "")
    } catch let error as TimerParserError {
      inlineError = Self.message(for: error)
    } catch {
      inlineError = "Could not create timer. Check local storage and try again."
    }
  }

  public static func message(for error: TimerParserError) -> String {
    switch error {
    case .inputTooLong: return "Entry is too long. Keep it under 2,048 characters."
    case .invalidFormat: return "Start with a duration such as 15m or 1h 30m."
    case .invalidNumber, .nonFiniteValue: return "Use a valid number in the timer duration."
    case .unsupportedSuffix: return "Use seconds, minutes, hours, or days (s, m, h, d)."
    case .duplicateUnit: return "Use each duration unit only once."
    case .negativeValue, .nonPositiveDuration: return "Duration must be greater than zero."
    case .durationTooLong: return "Duration must be one year or less."
    case .invalidWallClock: return "Use a valid time after @, such as @14:30."
    case .malformedTag: return "Tags use one #name with no spaces."
    }
  }

  /// Re-reads durable state; it never decrements a UI-side counter.
  public func refresh(now date: Date) async {
    guard date.timeIntervalSinceReferenceDate.isFinite else { return }
    guard !refreshing else { return }
    refreshing = true
    defer { refreshing = false }
    if preferences.retention != .unlimited,
      lastRetentionDay != Calendar.current.startOfDay(for: date)
    {
      await applyRetention()
    }
    do {
      let current = try await repository.due(at: date, limit: 100)
      for timer in current {
        let outcome = try await repository.complete(timer.id, at: date)
        if outcome.completed != timer { await playCompletion(outcome.completed) }
        if let successor = outcome.successor { await scheduleAfterPersistence(successor) }
      }
    } catch { inlineError = "Could not refresh timers." }
    await publishActive(at: date)
  }

  private func publishActive(at date: Date? = nil) async {
    do {
      activeTimers = Array(try await repository.active(limit: 100).prefix(100))
      priorityTimer = try await repository.priority(at: date ?? now())
      updateSleepAssertion()
      deletedTimers = Array(try await repository.deleted(limit: 100).prefix(100))
    } catch {
      inlineError = "Could not refresh timers."
    }
  }

  public func load() async {
    await applyRetention()
    await publishActive()
    await loadHistory()
    await refreshSuggestions(query: quickEntryText)
  }

  public func loadHistory() async {
    await loadHistory(
      from: historyFilter.from, through: historyFilter.through, query: historyFilter.query)
  }

  public func loadHistory(from: Date?, through: Date?, query: String, append: Bool = false) async {
    let request = UUID()
    historyRequest = request
    historyFilter = (from, through, String(query.prefix(2048)))
    historyLoading = true
    defer { if historyRequest == request { historyLoading = false } }
    let cursor = append ? historyPage.nextCursor : nil
    do {
      let page = try await repository.historyPage(
        from: from, through: through, query: historyFilter.query,
        limit: min(200, max(1, preferences.historyPageSize)), after: cursor)
      let deleted = try await repository.deletedHistory(limit: 200)
      guard historyRequest == request, !Task.isCancelled else { return }
      historyPage = page
      recentlyDeletedHistory = deleted
      historyError = nil
    } catch {
      if historyRequest == request { historyError = "Could not load timer history. Try again." }
    }
  }

  public func cancelHistoryLoad() {
    historyRequest = UUID()
    historyLoading = false
  }
  public func cancelReportsLoad() {
    reportsRequest = UUID()
    reportsLoading = false
  }
  public func loadNextHistoryPage() async {
    await loadHistory(
      from: historyFilter.from, through: historyFilter.through, query: historyFilter.query,
      append: true)
  }

  public func loadReports(from: Date?, through: Date?) async {
    reportsRequested = true
    let request = UUID()
    reportsRequest = request
    reportsFilter = (from, through)
    reportsLoading = true
    defer { if reportsRequest == request { reportsLoading = false } }
    do {
      let rows = try await collectHistory(
        from: from, through: through, query: "", stillCurrent: { self.reportsRequest == request })
      guard reportsRequest == request, !Task.isCancelled else { return }
      let summary = try ReportSummary(entries: rows)
      reportEntries = rows
      reportSummary = summary
      reportsError = nil
    } catch {
      if reportsRequest == request {
        reportsError = "Could not load complete report. Choose a smaller date range and try again."
      }
    }
  }

  private func collectHistory(
    from: Date?, through: Date?, query: String, stillCurrent: () -> Bool = { true }
  ) async throws -> [HistoryEntry] {
    var rows: [HistoryEntry] = []
    var cursor: HistoryPageCursor?
    for _ in 0..<51 {
      try Task.checkCancellation()
      guard stillCurrent() else { throw CancellationError() }
      let page = try await repository.historyPage(
        from: from, through: through, query: query, limit: 200, after: cursor)
      guard rows.count + page.entries.count <= HistoryAnalytics.maximumEntries else {
        throw HistoryAnalyticsError.tooManyEntries
      }
      rows.append(contentsOf: page.entries)
      guard let next = page.nextCursor else { return rows }
      guard next != cursor else { throw TimerRepositoryError.malformedPayload }
      cursor = next
    }
    throw HistoryAnalyticsError.tooManyEntries
  }

  public func exportHistory(
    to url: URL, write: (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }
  ) async {
    let filter = historyFilter
    do {
      let rows = try await collectHistory(
        from: filter.from, through: filter.through, query: filter.query)
      let data = Data(try CSVExporter().export(rows).utf8)
      try write(data, url)
      exportError = nil
    } catch {
      exportError =
        "Could not export CSV. Choose a writable location or a smaller date range and retry Export CSV."
    }
  }

  @discardableResult public func editHistory(
    _ entry: HistoryEntry, title: String, details: String, tags: [String]
  ) async -> Bool {
    do {
      var edited = entry
      try edited.updateMetadata(title: title, details: details, tags: tags)
      try await repository.updateHistory(edited)
      await refreshHistoryConsumers()
      return true
    } catch {
      historyError = "Could not save history changes. Review the fields and try again."
      return false
    }
  }

  @discardableResult public func deleteHistory(_ entry: HistoryEntry) async -> Bool {
    do {
      try await repository.softDeleteHistory(entry.id, at: now())
      await refreshHistoryConsumers()
      return true
    } catch {
      historyError = "Could not delete this history record. Try again."
      return false
    }
  }

  private func refreshHistoryConsumers() async {
    await loadHistory()
    if reportsRequested {
      await loadReports(from: reportsFilter.from, through: reportsFilter.through)
    }
  }

  public func refreshSuggestions(query: String) async {
    guard let presets else {
      suggestions = []
      return
    }
    do {
      suggestions = try await presets.suggestions(query: query, limit: 20).map { $0.command }
    } catch { suggestions = [] }
  }

  public func selectEditor(_ id: UUID?) async {
    guard let id else {
      selectedEditorTimer = nil
      return
    }
    selectedEditorTimer = try? await repository.timer(id: id)
  }

  @discardableResult public func pause(_ id: UUID) async -> Bool {
    await transition(
      id, failure: "Could not pause timer.", mutation: { try $0.pause(at: self.now()) },
      effect: { _ in try await self.notifications.cancel(timerID: id) })
  }
  @discardableResult public func start(_ id: UUID) async -> Bool {
    await transition(
      id, failure: "Could not start timer.", mutation: { try $0.start(at: self.now()) },
      effect: { timer in await self.scheduleAfterPersistence(timer) })
  }
  @discardableResult public func resume(_ id: UUID) async -> Bool {
    await transition(
      id, failure: "Could not resume timer.", mutation: { try $0.resume(at: self.now()) },
      effect: { timer in await self.scheduleAfterPersistence(timer) })
  }
  @discardableResult public func restart(_ id: UUID) async -> Bool {
    await transition(
      id, failure: "Could not restart timer.", mutation: { try $0.restart(at: self.now()) },
      effect: { timer in await self.scheduleAfterPersistence(timer) })
  }
  @discardableResult public func acknowledge(_ id: UUID) async -> Bool {
    await transition(
      id, failure: "Could not acknowledge timer.", mutation: { try $0.acknowledge(at: self.now()) },
      effect: { _ in try await self.notifications.cancel(timerID: id) })
  }
  @discardableResult public func softDelete(_ id: UUID) async -> Bool {
    do {
      try await repository.softDelete(id, at: now())
      await cancelAfterPersistence(id)
      await publishActive()
      return true
    } catch {
      inlineError = "Could not delete timer."
      return false
    }
  }
  @discardableResult public func restore(_ id: UUID) async -> Bool {
    do {
      try await repository.restore(id, at: now())
      let timer = try await repository.timer(id: id)
      if timer.state == .running { await scheduleAfterPersistence(timer) }
      await publishActive()
      return true
    } catch {
      inlineError = "Could not restore timer."
      return false
    }
  }
  @discardableResult public func cancel(_ id: UUID) async -> Bool {
    do {
      _ = try await repository.cancel(id: id, at: now())
      await cancelAfterPersistence(id)
      await publishActive()
      return true
    } catch {
      inlineError = "Could not cancel timer."
      return false
    }
  }
  @discardableResult public func complete(_ id: UUID) async -> Bool {
    do {
      let prior = try await repository.timer(id: id)
      let outcome = try await repository.complete(id, at: now())
      if outcome.completed != prior { await playCompletion(outcome.completed) }
      if let successor = outcome.successor { await scheduleAfterPersistence(successor) }
      await publishActive()
      return true
    } catch {
      inlineError = "Could not complete timer."
      return false
    }
  }
  @discardableResult public func edit(_ id: UUID, title: String, details: String, tags: [String])
    async -> Bool
  {
    await transition(
      id, failure: "Could not edit timer.",
      mutation: { try $0.updateMetadata(title: title, details: details, tags: tags) },
      effect: { timer in
        try await self.notifications.cancel(timerID: id)
        await self.scheduleAfterPersistence(timer)
      })
  }
  @discardableResult public func reconfigure(_ id: UUID, configuration: TimerConfiguration) async
    -> Bool
  {
    do { try await notifications.validateSound(name: configuration.alertName) } catch {
      inlineError =
        "Could not use the selected sound. Previous settings are unchanged. \(error.localizedDescription)"
      return false
    }
    return await transition(
      id, failure: "Could not edit timer.",
      mutation: { try $0.reconfigure(configuration, at: self.now()) },
      effect: { timer in
        try await self.notifications.cancel(timerID: id)
        await self.scheduleAfterPersistence(timer)
      })
  }

  /// Duplicates through the domain factory, then persists before publishing.
  @discardableResult public func duplicate(_ id: UUID) async -> Bool {
    do {
      let date = now()
      let source = try await repository.timer(id: id)
      var copy = try source.duplicate(at: date)
      try copy.start(at: date)
      let persisted = try await repository.insert(copy)
      await scheduleAfterPersistence(persisted)
      await publishActive()
      return true
    } catch {
      inlineError = "Could not duplicate timer."
      return false
    }
  }

  /// Recovers the repository's supported history record; active timers are not recovered.
  @discardableResult public func recoverHistory(_ id: UUID) async -> Bool {
    do {
      try await repository.recoverHistory(id)
      await refreshHistoryConsumers()
      await publishActive()
      return true
    } catch {
      historyError = "Could not recover timer history."
      return false
    }
  }

  /// NotificationController performs category and payload validation before
  /// this boundary is called; invalid values intentionally have no effects.
  public func handle(notificationAction action: TimerNotificationAction) async {
    switch action {
    case .stop(let id): await cancel(id)
    case .repeatTimer(let id, _): await repeatActionTimer(from: id)
    case .snooze(let id, _): await createActionTimer(from: id, duration: preferences.snoozeSeconds)
    case .invalidPayload: return
    }
  }

  private func createActionTimer(from id: UUID, duration: TimeInterval) async {
    guard duration.isFinite, duration > 0, duration <= TimerLimits.maximumDuration else { return }
    do {
      let source = try await repository.timer(id: id)
      await createActionTimer(from: source, duration: duration)
    } catch { inlineError = "Could not create timer from notification action." }
  }

  private func repeatActionTimer(from id: UUID) async {
    do {
      let source = try await repository.timer(id: id)
      guard let duration = source.duration else { return }
      await createActionTimer(from: source, duration: duration)
    } catch { inlineError = "Could not create timer from notification action." }
  }

  private func createActionTimer(from source: TimerItem, duration: TimeInterval) async {
    guard duration.isFinite, duration > 0, duration <= TimerLimits.maximumDuration else { return }
    do {
      let date = now()
      var timer = try TimerItem.countdown(
        title: source.title, duration: duration, details: source.details, tags: source.tags,
        alertName: source.alertName, alertVolume: source.alertVolume, createdAt: date)
      try timer.start(at: date)
      let persisted = try await repository.insert(timer)
      do { notificationStatus = try await notifications.schedule(persisted) } catch {
        notificationStatus = nil
        inlineError = "Timer saved, but notification scheduling failed."
      }
      await publishActive()
    } catch { inlineError = "Could not create timer from notification action." }
  }

  private func transition(
    _ id: UUID, failure: String, mutation: (inout TimerItem) throws -> Void,
    effect: (TimerItem) async throws -> Void
  ) async -> Bool {
    do {
      var timer = try await repository.timer(id: id)
      try mutation(&timer)
      try await repository.update(timer)
      do { try await effect(timer) } catch {
        inlineError = "Timer saved, but notification scheduling failed."
      }
      await publishActive()
      return true
    } catch {
      inlineError = failure
      return false
    }
  }

  private func cancelAfterPersistence(_ id: UUID) async {
    do { try await notifications.cancel(timerID: id) } catch {
      inlineError = "Timer saved, but notification scheduling failed."
    }
  }

  private func playCompletion(_ timer: TimerItem) async {
    guard let alertSounds else { return }
    do {
      let url = try timer.alertName.map { try AlertSoundIdentity.sourceURL(name: $0) }
      await alertSounds.play(customSound: url, volume: timer.alertVolume)
    } catch {
      inlineError = "Could not play the selected alert sound. Using the default sound."
      await alertSounds.play(customSound: nil, volume: timer.alertVolume)
    }
  }

  private func scheduleAfterPersistence(_ timer: TimerItem) async {
    guard timer.kind == .countdown else { return }
    do { notificationStatus = try await notifications.schedule(timer) } catch {
      notificationStatus = nil
      inlineError = "Timer saved, but notification scheduling failed."
    }
  }
}
