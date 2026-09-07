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
    public func scheduleCreatedTimer(_ timer: TimerItem) async throws -> NotificationScheduleStatus { try await schedule(timer) }
    public func validateSound(name: String?) async throws {}
}

extension NotificationController: TimerNotificationScheduling {
    public func scheduleCreatedTimer(_ timer: TimerItem) async throws -> NotificationScheduleStatus {
        guard timer.kind == .countdown, let deadline = timer.deadline else { return .scheduled }
        return try await schedule(timerID: timer.id, title: timer.title, details: timer.details, fireDate: deadline, requestAuthorizationForFirstSuccessfulCreation: true, alertName: timer.alertName)
    }
    public func schedule(_ timer: TimerItem) async throws -> NotificationScheduleStatus {
        guard let deadline = timer.deadline else { return .scheduled }
        return try await schedule(timerID: timer.id, title: timer.title, details: timer.details, fireDate: deadline, alertName: timer.alertName)
    }
}

/// Main-actor owned presentation state. Persistence remains the source of truth:
/// every mutation is stored before it is reflected to the UI.
@MainActor
public final class AppState: ObservableObject {
    public let operations: AppOperationOwner
    public func perform(_ operation: @escaping @MainActor () async -> Void) {
        if !operations.submit(operation) { inlineError = "Timer work is unavailable while closing or busy. Try again when ready." }
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
    @Published public private(set) var suggestions: [String] = []
    @Published public var preferences = AppPreferences()
    private var refreshing = false

    private let repository: any TimerRepository
    private let notifications: any TimerNotificationScheduling
    private let alertSounds: AlertSoundController?
    private let presets: (any PresetRepository)?
    private let now: () -> Date
    private let parser: (Date) -> TimerParser

    public init(
        repository: any TimerRepository,
        notifications: any TimerNotificationScheduling,
        presets: (any PresetRepository)? = nil,
        alertSounds: AlertSoundController? = nil,
        operations: AppOperationOwner = AppOperationOwner(),
        now: @escaping () -> Date = { .now },
        parser: @escaping (Date) -> TimerParser = { TimerParser(now: $0) }
    ) {
        self.repository = repository
        self.operations = operations
        self.notifications = notifications
        self.alertSounds = alertSounds
        self.presets = presets
        self.now = now
        self.parser = parser
    }

    /// Creates a running timer. The observable order is persist, schedule,
    /// publish; notification failures do not undo durable timer state.
    public func create(command: String) async {
        inlineError = nil
        let submittedAt = now()
        do {
            let parsed = try parser(submittedAt).parse(command)
            var timer: TimerItem
            if parsed.kind == .stopwatch {
                timer = try TimerItem.stopwatch(title: parsed.title, tags: parsed.tags, createdAt: submittedAt)
            } else {
                timer = try TimerItem.countdown(
                    title: parsed.title,
                    duration: parsed.duration ?? 1,
                    tags: parsed.tags,
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
            deletedTimers = Array(try await repository.deleted(limit: 100).prefix(100))
        } catch {
            inlineError = "Could not refresh timers."
        }
    }

    public func load() async {
        await publishActive()
        await loadHistory()
        await refreshSuggestions(query: quickEntryText)
    }

    public func loadHistory() async {
        await loadHistory(from: nil, through: nil, query: "", append: false)
    }

    public func loadHistory(from: Date?, through: Date?, query: String, append: Bool = false) async {
        guard !historyLoading else { return }
        historyLoading = true
        defer { historyLoading = false }
        let cursor = append ? historyPage.nextCursor : nil
        do {
            let page = try await repository.historyPage(
                from: from, through: through, query: query,
                limit: min(200, max(1, preferences.historyPageSize)), after: cursor)
            let entries = append ? Array((historyPage.entries + page.entries).prefix(200)) : page.entries
            historyPage = HistoryPage(entries: entries, nextCursor: entries.count < 200 ? page.nextCursor : nil)
        }
        catch { inlineError = "Could not load timer history." }
    }

    @discardableResult public func editHistory(_ entry: HistoryEntry, title: String, details: String, tags: [String]) async -> Bool {
        do { var edited = entry; try edited.updateMetadata(title: title, details: details, tags: tags); try await repository.updateHistory(edited); await loadHistory(); return true }
        catch { inlineError = "Could not save history changes. Review the fields and try again."; return false }
    }

    @discardableResult public func deleteHistory(_ entry: HistoryEntry) async -> Bool {
        do { try await repository.softDeleteHistory(entry.id, at: now()); recentlyDeletedHistory = Array(([entry] + recentlyDeletedHistory).prefix(200)); await loadHistory(); return true }
        catch { inlineError = "Could not delete this history record. Try again."; return false }
    }

    public func refreshSuggestions(query: String) async {
        guard let presets else { suggestions = []; return }
        do { suggestions = try await presets.suggestions(query: query, limit: 20).map { $0.command } }
        catch { suggestions = [] }
    }

    public func selectEditor(_ id: UUID?) async {
        guard let id else { selectedEditorTimer = nil; return }
        selectedEditorTimer = try? await repository.timer(id: id)
    }

    @discardableResult public func pause(_ id: UUID) async -> Bool { await transition(id, failure: "Could not pause timer.", mutation: { try $0.pause(at: self.now()) }, effect: { _ in try await self.notifications.cancel(timerID: id) }) }
    @discardableResult public func start(_ id: UUID) async -> Bool { await transition(id, failure: "Could not start timer.", mutation: { try $0.start(at: self.now()) }, effect: { timer in await self.scheduleAfterPersistence(timer) }) }
    @discardableResult public func resume(_ id: UUID) async -> Bool { await transition(id, failure: "Could not resume timer.", mutation: { try $0.resume(at: self.now()) }, effect: { timer in await self.scheduleAfterPersistence(timer) }) }
    @discardableResult public func restart(_ id: UUID) async -> Bool { await transition(id, failure: "Could not restart timer.", mutation: { try $0.restart(at: self.now()) }, effect: { timer in await self.scheduleAfterPersistence(timer) }) }
    @discardableResult public func acknowledge(_ id: UUID) async -> Bool { await transition(id, failure: "Could not acknowledge timer.", mutation: { try $0.acknowledge(at: self.now()) }, effect: { _ in try await self.notifications.cancel(timerID: id) }) }
    @discardableResult public func softDelete(_ id: UUID) async -> Bool { do { try await repository.softDelete(id, at: now()); await cancelAfterPersistence(id); await publishActive(); return true } catch { inlineError = "Could not delete timer."; return false } }
    @discardableResult public func restore(_ id: UUID) async -> Bool {
        do {
            try await repository.restore(id, at: now())
            let timer = try await repository.timer(id: id)
            if timer.state == .running { await scheduleAfterPersistence(timer) }
            await publishActive()
            return true
        } catch { inlineError = "Could not restore timer."; return false }
    }
    @discardableResult public func cancel(_ id: UUID) async -> Bool { do { _ = try await repository.cancel(id: id, at: now()); await cancelAfterPersistence(id); await publishActive(); return true } catch { inlineError = "Could not cancel timer."; return false } }
    @discardableResult public func complete(_ id: UUID) async -> Bool { do { let prior = try await repository.timer(id: id); let outcome = try await repository.complete(id, at: now()); if outcome.completed != prior { await playCompletion(outcome.completed) }; if let successor = outcome.successor { await scheduleAfterPersistence(successor) }; await publishActive(); return true } catch { inlineError = "Could not complete timer."; return false } }
    @discardableResult public func edit(_ id: UUID, title: String, details: String, tags: [String]) async -> Bool {
        await transition(id, failure: "Could not edit timer.", mutation: { try $0.updateMetadata(title: title, details: details, tags: tags) }, effect: { timer in
            try await self.notifications.cancel(timerID: id)
            await self.scheduleAfterPersistence(timer)
        })
    }
    @discardableResult public func reconfigure(_ id: UUID, configuration: TimerConfiguration) async -> Bool {
        do { try await notifications.validateSound(name: configuration.alertName) }
        catch { inlineError = "Could not use the selected sound. Previous settings are unchanged. \(error.localizedDescription)"; return false }
        return await transition(id, failure: "Could not edit timer.", mutation: { try $0.reconfigure(configuration, at: self.now()) }, effect: { timer in
            try await self.notifications.cancel(timerID: id)
            await self.scheduleAfterPersistence(timer)
        })
    }

    /// Duplicates through the domain factory, then persists before publishing.
    @discardableResult public func duplicate(_ id: UUID) async -> Bool {
        do {
            let date = now(); let source = try await repository.timer(id: id)
            var copy = try source.duplicate(at: date); try copy.start(at: date)
            let persisted = try await repository.insert(copy)
            await scheduleAfterPersistence(persisted); await publishActive(); return true
        } catch { inlineError = "Could not duplicate timer."; return false }
    }

    /// Recovers the repository's supported history record; active timers are not recovered.
    @discardableResult public func recoverHistory(_ id: UUID) async -> Bool {
        do { try await repository.recoverHistory(id); recentlyDeletedHistory.removeAll { $0.id == id }; await loadHistory(); await publishActive(); return true }
        catch { inlineError = "Could not recover timer history."; return false }
    }

    /// NotificationController performs category and payload validation before
    /// this boundary is called; invalid values intentionally have no effects.
    public func handle(notificationAction action: TimerNotificationAction) async {
        switch action {
        case let .stop(id): await cancel(id)
        case let .repeatTimer(id, _): await repeatActionTimer(from: id)
        case let .snooze(id, _): await createActionTimer(from: id, duration: preferences.snoozeSeconds)
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
            var timer = try TimerItem.countdown(title: source.title, duration: duration, details: source.details, tags: source.tags, createdAt: date)
            try timer.start(at: date)
            let persisted = try await repository.insert(timer)
            do { notificationStatus = try await notifications.schedule(persisted) }
            catch { notificationStatus = nil; inlineError = "Timer saved, but notification scheduling failed." }
            await publishActive()
        } catch { inlineError = "Could not create timer from notification action." }
    }

    private func transition(_ id: UUID, failure: String, mutation: (inout TimerItem) throws -> Void, effect: (TimerItem) async throws -> Void) async -> Bool {
        do {
            var timer = try await repository.timer(id: id)
            try mutation(&timer)
            try await repository.update(timer)
            do { try await effect(timer) } catch { inlineError = "Timer saved, but notification scheduling failed." }
            await publishActive()
            return true
        } catch { inlineError = failure; return false }
    }

    private func cancelAfterPersistence(_ id: UUID) async {
        do { try await notifications.cancel(timerID: id) }
        catch { inlineError = "Timer saved, but notification scheduling failed." }
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
        do { notificationStatus = try await notifications.schedule(timer) }
        catch { notificationStatus = nil; inlineError = "Timer saved, but notification scheduling failed." }
    }
}
