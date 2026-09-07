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

    private let repository: any TimerRepository
    private let notifications: any TimerNotificationScheduling
    private let now: () -> Date
    private let parser: (Date) -> TimerParser

    public init(
        repository: any TimerRepository,
        notifications: any TimerNotificationScheduling,
        now: @escaping () -> Date = { .now },
        parser: @escaping (Date) -> TimerParser = { TimerParser(now: $0) }
    ) {
        self.repository = repository
        self.notifications = notifications
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
                    notificationStatus = try await notifications.schedule(persisted)
                } catch {
                    notificationStatus = nil
                    inlineError = "Timer saved, but notification scheduling failed."
                }
            }
            await publishActive()
            quickEntryText = ""
        } catch {
            inlineError = "Could not create timer."
        }
    }

    /// Re-reads durable state; it never decrements a UI-side counter.
    public func refresh(now _: Date) async {
        await publishActive()
    }

    private func publishActive() async {
        do {
            activeTimers = Array(try await repository.active(limit: 100).prefix(100))
        } catch {
            inlineError = "Could not refresh timers."
        }
    }
}
