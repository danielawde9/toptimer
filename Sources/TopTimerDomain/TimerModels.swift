import Foundation

public enum TimerValidationError: Error, Equatable {
    case nonPositiveDuration
    case titleTooLong
    case descriptionTooLong
    case tooManyTags
    case tagTooLong
}

public struct TimerLimits: Sendable {
    public static let title = 80
    public static let details = 500
    public static let tags = 12
    public static let tag = 32

    private init() {}
}

public enum TimerKind: String, Codable, Equatable, Sendable {
    case countdown
    case stopwatch
}

public enum TimerState: String, Codable, Equatable, Sendable {
    case idle
    case running
    case paused
    case completed
    case acknowledged
    case cancelled
}

public enum CompletionReason: String, Codable, Equatable, Sendable {
    case finished
    case stopped
    case cancelled
    case snoozed
}

public enum RecurrenceRule: Codable, Equatable, Sendable {
    case none
    case interval(seconds: TimeInterval)
    case daily(hour: Int, minute: Int)
    case weekdays(hour: Int, minute: Int)
    case weekly(weekday: Int, hour: Int, minute: Int)
    case selectedWeekdays(weekdays: Set<Int>, hour: Int, minute: Int)
}

private func validateTimerMetadata(title: String, details: String, tags: [String]) throws {
    guard title.count <= TimerLimits.title else {
        throw TimerValidationError.titleTooLong
    }
    guard details.count <= TimerLimits.details else {
        throw TimerValidationError.descriptionTooLong
    }
    guard tags.count <= TimerLimits.tags else {
        throw TimerValidationError.tooManyTags
    }
    guard tags.allSatisfy({ $0.count <= TimerLimits.tag }) else {
        throw TimerValidationError.tagTooLong
    }
}

public struct TimerItem: Codable, Equatable, Sendable {
    public let id: UUID
    public let occurrenceID: UUID
    public var title: String
    public var details: String
    public var tags: [String]
    public let kind: TimerKind
    public var state: TimerState
    public let duration: TimeInterval?
    public var remaining: TimeInterval?
    public var deadline: Date?
    public let createdAt: Date
    public var startedAt: Date?
    public var pausedAt: Date?
    public var completedAt: Date?
    public var deletedAt: Date?
    public var recurrence: RecurrenceRule
    public var alertName: String?
    public var alertVolume: Double
    public var successorID: UUID?

    public static func countdown(
        title: String,
        duration: TimeInterval,
        details: String = "",
        tags: [String] = [],
        recurrence: RecurrenceRule = .none,
        alertName: String? = nil,
        alertVolume: Double = 1,
        id: UUID = UUID(),
        occurrenceID: UUID = UUID(),
        createdAt: Date = .now
    ) throws -> TimerItem {
        try TimerItem(
            id: id,
            occurrenceID: occurrenceID,
            title: title,
            details: details,
            tags: tags,
            kind: .countdown,
            duration: duration,
            createdAt: createdAt,
            recurrence: recurrence,
            alertName: alertName,
            alertVolume: alertVolume
        )
    }

    public static func stopwatch(
        title: String,
        details: String = "",
        tags: [String] = [],
        recurrence: RecurrenceRule = .none,
        alertName: String? = nil,
        alertVolume: Double = 1,
        id: UUID = UUID(),
        occurrenceID: UUID = UUID(),
        createdAt: Date = .now
    ) throws -> TimerItem {
        try TimerItem(
            id: id,
            occurrenceID: occurrenceID,
            title: title,
            details: details,
            tags: tags,
            kind: .stopwatch,
            duration: nil,
            createdAt: createdAt,
            recurrence: recurrence,
            alertName: alertName,
            alertVolume: alertVolume
        )
    }

    private init(
        id: UUID,
        occurrenceID: UUID,
        title: String,
        details: String,
        tags: [String],
        kind: TimerKind,
        duration: TimeInterval?,
        remaining: TimeInterval? = nil,
        deadline: Date? = nil,
        state: TimerState = .idle,
        createdAt: Date,
        startedAt: Date? = nil,
        pausedAt: Date? = nil,
        completedAt: Date? = nil,
        deletedAt: Date? = nil,
        recurrence: RecurrenceRule,
        alertName: String? = nil,
        alertVolume: Double = 1,
        successorID: UUID? = nil
    ) throws {
        try validateTimerMetadata(title: title, details: details, tags: tags)

        switch kind {
        case .countdown:
            guard let duration, duration.isFinite, duration > 0 else {
                throw TimerValidationError.nonPositiveDuration
            }
            self.duration = duration
            self.remaining = remaining ?? duration
            self.deadline = deadline
        case .stopwatch:
            self.duration = nil
            self.remaining = nil
            self.deadline = nil
        }

        self.id = id
        self.occurrenceID = occurrenceID
        self.title = title
        self.details = details
        self.tags = tags
        self.kind = kind
        self.state = state
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.pausedAt = pausedAt
        self.completedAt = completedAt
        self.deletedAt = deletedAt
        self.recurrence = recurrence
        self.alertName = alertName
        self.alertVolume = alertVolume
        self.successorID = successorID
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case occurrenceID
        case title
        case details
        case tags
        case kind
        case state
        case duration
        case remaining
        case deadline
        case createdAt
        case startedAt
        case pausedAt
        case completedAt
        case deletedAt
        case recurrence
        case alertName
        case alertVolume
        case successorID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            occurrenceID: container.decode(UUID.self, forKey: .occurrenceID),
            title: container.decode(String.self, forKey: .title),
            details: container.decode(String.self, forKey: .details),
            tags: container.decode([String].self, forKey: .tags),
            kind: container.decode(TimerKind.self, forKey: .kind),
            duration: container.decodeIfPresent(TimeInterval.self, forKey: .duration),
            remaining: container.decodeIfPresent(TimeInterval.self, forKey: .remaining),
            deadline: container.decodeIfPresent(Date.self, forKey: .deadline),
            state: container.decode(TimerState.self, forKey: .state),
            createdAt: container.decode(Date.self, forKey: .createdAt),
            startedAt: container.decodeIfPresent(Date.self, forKey: .startedAt),
            pausedAt: container.decodeIfPresent(Date.self, forKey: .pausedAt),
            completedAt: container.decodeIfPresent(Date.self, forKey: .completedAt),
            deletedAt: container.decodeIfPresent(Date.self, forKey: .deletedAt),
            recurrence: container.decode(RecurrenceRule.self, forKey: .recurrence),
            alertName: container.decodeIfPresent(String.self, forKey: .alertName),
            alertVolume: container.decode(Double.self, forKey: .alertVolume),
            successorID: container.decodeIfPresent(UUID.self, forKey: .successorID)
        )
    }
}

public struct HistoryEntry: Codable, Equatable, Sendable {
    public let id: UUID
    public let timerID: UUID
    public let occurrenceID: UUID
    public var title: String
    public var details: String
    public var tags: [String]
    public let kind: TimerKind
    public let startedAt: Date?
    public let endedAt: Date
    public let elapsedSeconds: TimeInterval
    public let completionReason: CompletionReason
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        timerID: UUID,
        occurrenceID: UUID,
        title: String,
        details: String = "",
        tags: [String] = [],
        kind: TimerKind,
        startedAt: Date? = nil,
        endedAt: Date,
        elapsedSeconds: TimeInterval,
        completionReason: CompletionReason,
        deletedAt: Date? = nil
    ) throws {
        try validateTimerMetadata(title: title, details: details, tags: tags)

        self.id = id
        self.timerID = timerID
        self.occurrenceID = occurrenceID
        self.title = title
        self.details = details
        self.tags = tags
        self.kind = kind
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.elapsedSeconds = elapsedSeconds
        self.completionReason = completionReason
        self.deletedAt = deletedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case timerID
        case occurrenceID
        case title
        case details
        case tags
        case kind
        case startedAt
        case endedAt
        case elapsedSeconds
        case completionReason
        case deletedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            timerID: container.decode(UUID.self, forKey: .timerID),
            occurrenceID: container.decode(UUID.self, forKey: .occurrenceID),
            title: container.decode(String.self, forKey: .title),
            details: container.decode(String.self, forKey: .details),
            tags: container.decode([String].self, forKey: .tags),
            kind: container.decode(TimerKind.self, forKey: .kind),
            startedAt: container.decodeIfPresent(Date.self, forKey: .startedAt),
            endedAt: container.decode(Date.self, forKey: .endedAt),
            elapsedSeconds: container.decode(TimeInterval.self, forKey: .elapsedSeconds),
            completionReason: container.decode(CompletionReason.self, forKey: .completionReason),
            deletedAt: container.decodeIfPresent(Date.self, forKey: .deletedAt)
        )
    }
}
