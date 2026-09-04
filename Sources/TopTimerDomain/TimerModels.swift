import Foundation

public enum TimerValidationError: Error, Equatable {
    case nonPositiveDuration
    case titleTooLong
    case descriptionTooLong
    case tooManyTags
    case tagTooLong
}

public enum RecurrenceValidationError: Error, Equatable {
    case invalidInterval
    case invalidClockTime
    case invalidWeekday
    case emptyWeekdays
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

private func exceedsLimit(_ value: String, limit: Int) -> Bool {
    value.prefix(limit + 1).count > limit
}

private func validateTimerMetadata(title: String, details: String, tags: [String]) throws {
    guard !exceedsLimit(title, limit: TimerLimits.title) else {
        throw TimerValidationError.titleTooLong
    }
    guard !exceedsLimit(details, limit: TimerLimits.details) else {
        throw TimerValidationError.descriptionTooLong
    }
    guard tags.count <= TimerLimits.tags else {
        throw TimerValidationError.tooManyTags
    }
    guard tags.allSatisfy({ !exceedsLimit($0, limit: TimerLimits.tag) }) else {
        throw TimerValidationError.tagTooLong
    }
}

private func validateRecurrence(_ recurrence: RecurrenceRule) throws {
    func validClockTime(hour: Int, minute: Int) -> Bool {
        (0...23).contains(hour) && (0...59).contains(minute)
    }

    switch recurrence {
    case .none:
        return
    case let .interval(seconds):
        guard seconds.isFinite, seconds > 0 else {
            throw RecurrenceValidationError.invalidInterval
        }
    case let .daily(hour, minute), let .weekdays(hour, minute):
        guard validClockTime(hour: hour, minute: minute) else {
            throw RecurrenceValidationError.invalidClockTime
        }
    case let .weekly(weekday, hour, minute):
        guard (1...7).contains(weekday) else {
            throw RecurrenceValidationError.invalidWeekday
        }
        guard validClockTime(hour: hour, minute: minute) else {
            throw RecurrenceValidationError.invalidClockTime
        }
    case let .selectedWeekdays(weekdays, hour, minute):
        guard !weekdays.isEmpty else {
            throw RecurrenceValidationError.emptyWeekdays
        }
        guard weekdays.allSatisfy({ (1...7).contains($0) }) else {
            throw RecurrenceValidationError.invalidWeekday
        }
        guard validClockTime(hour: hour, minute: minute) else {
            throw RecurrenceValidationError.invalidClockTime
        }
    }
}

public struct TimerItem: Codable, Equatable, Sendable {
    public let id: UUID
    public let occurrenceID: UUID
    public internal(set) var title: String
    public internal(set) var details: String
    public internal(set) var tags: [String]
    public let kind: TimerKind
    public internal(set) var state: TimerState
    public let duration: TimeInterval?
    public internal(set) var remaining: TimeInterval?
    public internal(set) var deadline: Date?
    public let createdAt: Date
    public internal(set) var startedAt: Date?
    public internal(set) var pausedAt: Date?
    public internal(set) var completedAt: Date?
    public internal(set) var deletedAt: Date?
    public internal(set) var recurrence: RecurrenceRule
    public internal(set) var alertName: String?
    public internal(set) var alertVolume: Double
    public internal(set) var successorID: UUID?

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
        createdAt: Date
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

    /// Convenience for UI entry points that intentionally start from the current clock.
    public static func countdown(
        title: String,
        duration: TimeInterval,
        details: String = "",
        tags: [String] = [],
        recurrence: RecurrenceRule = .none,
        alertName: String? = nil,
        alertVolume: Double = 1,
        id: UUID = UUID(),
        occurrenceID: UUID = UUID()
    ) throws -> TimerItem {
        try countdown(
            title: title,
            duration: duration,
            details: details,
            tags: tags,
            recurrence: recurrence,
            alertName: alertName,
            alertVolume: alertVolume,
            id: id,
            occurrenceID: occurrenceID,
            createdAt: .now
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
        createdAt: Date
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

    /// Convenience for UI entry points that intentionally start from the current clock.
    public static func stopwatch(
        title: String,
        details: String = "",
        tags: [String] = [],
        recurrence: RecurrenceRule = .none,
        alertName: String? = nil,
        alertVolume: Double = 1,
        id: UUID = UUID(),
        occurrenceID: UUID = UUID()
    ) throws -> TimerItem {
        try stopwatch(
            title: title,
            details: details,
            tags: tags,
            recurrence: recurrence,
            alertName: alertName,
            alertVolume: alertVolume,
            id: id,
            occurrenceID: occurrenceID,
            createdAt: .now
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
        try validateRecurrence(recurrence)

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

    public mutating func updateMetadata(title: String, details: String, tags: [String]) throws {
        try validateTimerMetadata(title: title, details: details, tags: tags)
        self.title = title
        self.details = details
        self.tags = tags
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
        let kind = try container.decode(TimerKind.self, forKey: .kind)
        let duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
        let remaining = try container.decodeIfPresent(TimeInterval.self, forKey: .remaining)
        let deadline = try container.decodeIfPresent(Date.self, forKey: .deadline)
        let state = try container.decode(TimerState.self, forKey: .state)
        let startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        let pausedAt = try container.decodeIfPresent(Date.self, forKey: .pausedAt)
        let completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        let recurrence = try container.decode(RecurrenceRule.self, forKey: .recurrence)

        do {
            try validateTimerMetadata(
                title: container.decode(String.self, forKey: .title),
                details: container.decode(String.self, forKey: .details),
                tags: container.decode([String].self, forKey: .tags)
            )
            try validateRecurrence(recurrence)
        } catch {
            throw Self.corrupted(decoder, reason: "Invalid timer metadata or recurrence")
        }

        guard Self.hasValidPersistedShape(
            kind: kind,
            duration: duration,
            remaining: remaining,
            deadline: deadline,
            state: state,
            startedAt: startedAt,
            pausedAt: pausedAt,
            completedAt: completedAt
        ) else {
            throw Self.corrupted(decoder, reason: "Timer fields do not match kind and state")
        }

        self.id = try container.decode(UUID.self, forKey: .id)
        self.occurrenceID = try container.decode(UUID.self, forKey: .occurrenceID)
        self.title = try container.decode(String.self, forKey: .title)
        self.details = try container.decode(String.self, forKey: .details)
        self.tags = try container.decode([String].self, forKey: .tags)
        self.kind = kind
        self.state = state
        self.duration = duration
        self.remaining = remaining
        self.deadline = deadline
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.startedAt = startedAt
        self.pausedAt = pausedAt
        self.completedAt = completedAt
        self.deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        self.recurrence = recurrence
        self.alertName = try container.decodeIfPresent(String.self, forKey: .alertName)
        self.alertVolume = try container.decode(Double.self, forKey: .alertVolume)
        self.successorID = try container.decodeIfPresent(UUID.self, forKey: .successorID)
    }

    private static func hasValidPersistedShape(
        kind: TimerKind,
        duration: TimeInterval?,
        remaining: TimeInterval?,
        deadline: Date?,
        state: TimerState,
        startedAt: Date?,
        pausedAt: Date?,
        completedAt: Date?
    ) -> Bool {
        switch kind {
        case .countdown:
            guard let duration, duration.isFinite, duration > 0 else { return false }
            if let remaining, (!remaining.isFinite || remaining < 0 || remaining > duration) {
                return false
            }
            switch state {
            case .idle:
                return remaining != nil && deadline == nil && startedAt == nil && pausedAt == nil && completedAt == nil
            case .running:
                return deadline != nil && startedAt != nil && pausedAt == nil && completedAt == nil
            case .paused:
                return remaining != nil && deadline == nil && startedAt != nil && pausedAt != nil && completedAt == nil
            case .completed, .acknowledged, .cancelled:
                return completedAt != nil
            }
        case .stopwatch:
            guard duration == nil, remaining == nil, deadline == nil else { return false }
            switch state {
            case .idle:
                return startedAt == nil && pausedAt == nil && completedAt == nil
            case .running:
                return startedAt != nil && pausedAt == nil && completedAt == nil
            case .paused:
                return startedAt != nil && pausedAt != nil && completedAt == nil
            case .completed, .acknowledged, .cancelled:
                return completedAt != nil
            }
        }
    }

    private static func corrupted(_ decoder: Decoder, reason: String) -> DecodingError {
        DecodingError.dataCorrupted(
            DecodingError.Context(codingPath: decoder.codingPath, debugDescription: reason)
        )
    }
}

public struct HistoryEntry: Codable, Equatable, Sendable {
    public let id: UUID
    public let timerID: UUID
    public let occurrenceID: UUID
    public internal(set) var title: String
    public internal(set) var details: String
    public internal(set) var tags: [String]
    public let kind: TimerKind
    public let startedAt: Date?
    public let endedAt: Date
    public let elapsedSeconds: TimeInterval
    public let completionReason: CompletionReason
    public internal(set) var deletedAt: Date?

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

    public mutating func updateMetadata(title: String, details: String, tags: [String]) throws {
        try validateTimerMetadata(title: title, details: details, tags: tags)
        self.title = title
        self.details = details
        self.tags = tags
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
