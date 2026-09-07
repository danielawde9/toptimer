import Foundation
import TopTimerDomain
import TopTimerPersistence
import TopTimerSystem

/// The small system boundary used by application state. UI tests provide this
/// protocol instead of talking to UserNotifications.
public protocol TimerNotificationScheduling: Sendable {
    func schedule(_ timer: TimerItem) async throws -> NotificationScheduleStatus
    func cancel(timerID: UUID) async throws
}

extension NotificationController: TimerNotificationScheduling {
    public func schedule(_ timer: TimerItem) async throws -> NotificationScheduleStatus {
        guard let deadline = timer.deadline else { return .scheduled }
        return try await schedule(timerID: timer.id, title: timer.title, details: timer.details, fireDate: deadline)
    }
}

/// Main-actor owned presentation state. Persistence remains the source of truth:
/// every mutation is stored before it is reflected to the UI.
@MainActor
public final class AppState {
    public private(set) var activeTimers: [TimerItem] = []
    public var quickEntryText = ""
    public private(set) var inlineError: String?
    public private(set) var notificationStatus: NotificationScheduleStatus?
    public private(set) var priorityTimer: TimerItem?
    public private(set) var selectedEditorTimer: TimerItem?
    public private(set) var historyPage = HistoryPage(entries: [], nextCursor: nil)
    public private(set) var suggestions: [String] = []
    public var preferences = AppPreferences()
    private var refreshing = false

    private let repository: any TimerRepository
    private let notifications: any TimerNotificationScheduling
    private let presets: (any PresetRepository)?
    private let now: () -> Date
    private let parser: (Date) -> TimerParser

    public init(
        repository: any TimerRepository,
        notifications: any TimerNotificationScheduling,
        presets: (any PresetRepository)? = nil,
        now: @escaping () -> Date = { .now },
        parser: @escaping (Date) -> TimerParser = { TimerParser(now: $0) }
    ) {
        self.repository = repository
        self.notifications = notifications
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

            // Presets are a convenience record: a preset write never makes a
            // successfully persisted timer disappear from the UI.
            _ = try? await presets?.record(command: command, tags: parsed.tags, at: submittedAt)

            if persisted.kind == .countdown {
                do {
                    notificationStatus = try await notifications.schedule(persisted)
                } catch {
                    notificationStatus = nil
                    inlineError = "Timer saved, but notification scheduling failed."
                }
            }
            await publishActive()
            quickEntryText = ""
            await refreshSuggestions(query: "")
        } catch {
            inlineError = "Could not create timer."
        }
    }

    /// Re-reads durable state; it never decrements a UI-side counter.
    public func refresh(now _: Date) async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        let date = now()
        do {
            let current = Array(try await repository.active(limit: 100).prefix(100))
            for timer in current where timer.kind == .countdown && timer.state == .running && (timer.deadline ?? .distantFuture) <= date {
                let outcome = try await repository.complete(timer.id, at: date)
                if let successor = outcome.successor { _ = try? await notifications.schedule(successor) }
            }
        } catch { inlineError = "Could not refresh timers." }
        await publishActive()
    }

    private func publishActive() async {
        do {
            activeTimers = Array(try await repository.active(limit: 100).prefix(100))
            priorityTimer = activeTimers.sorted { left, right in
                let l = left.deadline ?? .distantFuture
                let r = right.deadline ?? .distantFuture
                return l == r ? left.id.uuidString < right.id.uuidString : l < r
            }.first
        } catch {
            inlineError = "Could not refresh timers."
        }
    }

    public func load() async {
        await publishActive()
        do { historyPage = try await repository.historyPage(from: nil, through: nil, query: "", limit: 100, after: nil) }
        catch { inlineError = "Could not load timer history." }
        await refreshSuggestions(query: quickEntryText)
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

    public func pause(_ id: UUID) async { await update(id) { try $0.pause(at: self.now()) }; try? await notifications.cancel(timerID: id) }
    public func resume(_ id: UUID) async { await update(id) { try $0.resume(at: self.now()) }; await reschedule(id) }
    public func restart(_ id: UUID) async { await update(id) { try $0.restart(at: self.now()) }; await reschedule(id) }
    public func acknowledge(_ id: UUID) async { await update(id) { try $0.acknowledge(at: self.now()) }; try? await notifications.cancel(timerID: id) }
    public func softDelete(_ id: UUID) async { do { try await repository.softDelete(id, at: now()); try? await notifications.cancel(timerID: id); await publishActive() } catch { inlineError = "Could not delete timer." } }
    public func cancel(_ id: UUID) async { do { _ = try await repository.cancel(id: id, at: now()); try? await notifications.cancel(timerID: id); await publishActive() } catch { inlineError = "Could not cancel timer." } }
    public func complete(_ id: UUID) async { do { let outcome = try await repository.complete(id, at: now()); if let successor = outcome.successor { _ = try? await notifications.schedule(successor) }; await publishActive() } catch { inlineError = "Could not complete timer." } }

    /// NotificationController performs category and payload validation before
    /// this boundary is called; invalid values intentionally have no effects.
    public func handle(notificationAction action: TimerNotificationAction) async {
        switch action {
        case let .stop(id): await cancel(id)
        case let .repeatTimer(id, duration): await createActionTimer(from: id, duration: duration)
        case let .snooze(id, seconds): await createActionTimer(from: id, duration: seconds)
        case .invalidPayload: return
        }
    }

    private func createActionTimer(from id: UUID, duration: TimeInterval) async {
        guard duration.isFinite, duration > 0, duration <= TimerLimits.maximumDuration else { return }
        do {
            let source = try await repository.timer(id: id)
            let date = now()
            var timer = try TimerItem.countdown(title: source.title, duration: duration, details: source.details, tags: source.tags, createdAt: date)
            try timer.start(at: date)
            let persisted = try await repository.insert(timer)
            notificationStatus = try? await notifications.schedule(persisted)
            await publishActive()
        } catch { inlineError = "Could not create timer from notification action." }
    }

    private func update(_ id: UUID, mutation: (inout TimerItem) throws -> Void) async {
        do { var timer = try await repository.timer(id: id); try mutation(&timer); try await repository.update(timer); await publishActive() }
        catch { inlineError = "Could not update timer." }
    }
    private func reschedule(_ id: UUID) async { if let timer = try? await repository.timer(id: id), timer.kind == .countdown { notificationStatus = try? await notifications.schedule(timer) } }
}

public struct AppPreferences: Equatable, Sendable {
    public var snoozeSeconds: TimeInterval
    public init(snoozeSeconds: TimeInterval = 300) { self.snoozeSeconds = min(86_400, max(60, snoozeSeconds)) }
}
