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

private enum TimerShapeValidationError: Error {
    case invalidShape
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
    /// Wall-clock seconds spent paused by a stopwatch. Countdown timers keep this at zero.
    public internal(set) var accumulatedPause: TimeInterval
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
        accumulatedPause: TimeInterval = 0,
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
            self.accumulatedPause = 0
            self.deadline = deadline
        case .stopwatch:
            self.duration = nil
            self.remaining = nil
            self.accumulatedPause = accumulatedPause
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
        case accumulatedPause
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
        let title = try container.decode(String.self, forKey: .title)
        let details = try container.decode(String.self, forKey: .details)
        let tags = try container.decode([String].self, forKey: .tags)
        let kind = try container.decode(TimerKind.self, forKey: .kind)
        let duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
        let remaining = try container.decodeIfPresent(TimeInterval.self, forKey: .remaining)
        let accumulatedPause = try container.decodeIfPresent(TimeInterval.self, forKey: .accumulatedPause) ?? 0
        let deadline = try container.decodeIfPresent(Date.self, forKey: .deadline)
        let state = try container.decode(TimerState.self, forKey: .state)
        let startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        let pausedAt = try container.decodeIfPresent(Date.self, forKey: .pausedAt)
        let completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        let recurrence = try container.decode(RecurrenceRule.self, forKey: .recurrence)

        do {
            try Self.validateFullShape(
                title: title,
                details: details,
                tags: tags,
                kind: kind,
                duration: duration,
                remaining: remaining,
                accumulatedPause: accumulatedPause,
                deadline: deadline,
                state: state,
                startedAt: startedAt,
                pausedAt: pausedAt,
                completedAt: completedAt,
                recurrence: recurrence
            )
        } catch {
            throw Self.corrupted(decoder, reason: "Invalid timer metadata or recurrence")
        }

        self.id = try container.decode(UUID.self, forKey: .id)
        self.occurrenceID = try container.decode(UUID.self, forKey: .occurrenceID)
        self.title = title
        self.details = details
        self.tags = tags
        self.kind = kind
        self.state = state
        self.duration = duration
        self.remaining = remaining
        self.accumulatedPause = accumulatedPause
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

    public func encode(to encoder: Encoder) throws {
        do {
            try Self.validateFullShape(
                title: title,
                details: details,
                tags: tags,
                kind: kind,
                duration: duration,
                remaining: remaining,
                accumulatedPause: accumulatedPause,
                deadline: deadline,
                state: state,
                startedAt: startedAt,
                pausedAt: pausedAt,
                completedAt: completedAt,
                recurrence: recurrence
            )
        } catch {
            throw EncodingError.invalidValue(
                self,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "Timer fields do not match bounded model invariants"
                )
            )
        }

        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(occurrenceID, forKey: .occurrenceID)
        try container.encode(title, forKey: .title)
        try container.encode(details, forKey: .details)
        try container.encode(tags, forKey: .tags)
        try container.encode(kind, forKey: .kind)
        try container.encode(state, forKey: .state)
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encodeIfPresent(remaining, forKey: .remaining)
        try container.encode(accumulatedPause, forKey: .accumulatedPause)
        try container.encodeIfPresent(deadline, forKey: .deadline)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(pausedAt, forKey: .pausedAt)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try container.encode(recurrence, forKey: .recurrence)
        try container.encodeIfPresent(alertName, forKey: .alertName)
        try container.encode(alertVolume, forKey: .alertVolume)
        try container.encodeIfPresent(successorID, forKey: .successorID)
    }

    private static func validateFullShape(
        title: String,
        details: String,
        tags: [String],
        kind: TimerKind,
        duration: TimeInterval?,
        remaining: TimeInterval?,
        accumulatedPause: TimeInterval,
        deadline: Date?,
        state: TimerState,
        startedAt: Date?,
        pausedAt: Date?,
        completedAt: Date?,
        recurrence: RecurrenceRule
    ) throws {
        try validateTimerMetadata(title: title, details: details, tags: tags)
        try validateRecurrence(recurrence)
        guard accumulatedPause.isFinite, accumulatedPause >= 0 else {
            throw TimerShapeValidationError.invalidShape
        }

        switch kind {
        case .countdown:
            guard accumulatedPause == 0 else {
                throw TimerShapeValidationError.invalidShape
            }
            guard let duration, duration.isFinite, duration > 0 else {
                throw TimerShapeValidationError.invalidShape
            }
            if let remaining, (!remaining.isFinite || remaining < 0 || remaining > duration) {
                throw TimerShapeValidationError.invalidShape
            }
            switch state {
            case .idle:
                guard remaining != nil, deadline == nil, startedAt == nil, pausedAt == nil, completedAt == nil else {
                    throw TimerShapeValidationError.invalidShape
                }
            case .running:
                guard deadline != nil, startedAt != nil, pausedAt == nil, completedAt == nil else {
                    throw TimerShapeValidationError.invalidShape
                }
            case .paused:
                guard remaining != nil, deadline == nil, startedAt != nil, pausedAt != nil, completedAt == nil else {
                    throw TimerShapeValidationError.invalidShape
                }
            case .completed, .acknowledged, .cancelled:
                guard completedAt != nil else {
                    throw TimerShapeValidationError.invalidShape
                }
            }
        case .stopwatch:
            guard duration == nil, remaining == nil, deadline == nil else {
                throw TimerShapeValidationError.invalidShape
            }
            switch state {
            case .idle:
                guard startedAt == nil, pausedAt == nil, completedAt == nil else {
                    throw TimerShapeValidationError.invalidShape
                }
            case .running:
                guard startedAt != nil, pausedAt == nil, completedAt == nil else {
                    throw TimerShapeValidationError.invalidShape
                }
            case .paused:
                guard startedAt != nil, pausedAt != nil, completedAt == nil else {
                    throw TimerShapeValidationError.invalidShape
                }
            case .completed, .acknowledged, .cancelled:
                guard completedAt != nil else {
                    throw TimerShapeValidationError.invalidShape
                }
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
