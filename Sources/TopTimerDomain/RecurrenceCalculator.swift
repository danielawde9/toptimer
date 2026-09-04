import Foundation

public enum RecurrenceCalculatorError: Error, Equatable, Sendable {
    case recurrenceDisabled
    case invalidInterval
    case invalidClockTime
    case invalidWeekday
    case emptyWeekdays
    case invalidReferenceDate
    case noDateFound
}

public struct RecurrenceCalculator: Sendable {
    private static let maximumCandidateDays = 370

    private let calendar: Calendar

    public init(calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
    }

    public func nextDate(after reference: Date, rule: RecurrenceRule) throws -> Date {
        guard reference.timeIntervalSinceReferenceDate.isFinite else {
            throw RecurrenceCalculatorError.invalidReferenceDate
        }

        switch rule {
        case .none:
            throw RecurrenceCalculatorError.recurrenceDisabled
        case let .interval(seconds):
            return try nextIntervalDate(after: reference, seconds: seconds)
        case let .daily(hour, minute):
            try validateRule(.daily(hour: hour, minute: minute))
            return try nextCalendarDate(after: reference, hour: hour, minute: minute) { _ in true }
        case let .weekdays(hour, minute):
            try validateRule(.weekdays(hour: hour, minute: minute))
            return try nextCalendarDate(after: reference, hour: hour, minute: minute) { day in
                let weekday = calendar.component(.weekday, from: day)
                return (2...6).contains(weekday)
            }
        case let .weekly(weekday, hour, minute):
            try validateRule(.weekly(weekday: weekday, hour: hour, minute: minute))
            return try nextCalendarDate(after: reference, hour: hour, minute: minute) { day in
                calendar.component(.weekday, from: day) == weekday
            }
        case let .selectedWeekdays(weekdays, hour, minute):
            try validateRule(.selectedWeekdays(weekdays: weekdays, hour: hour, minute: minute))
            return try nextCalendarDate(after: reference, hour: hour, minute: minute) { day in
                weekdays.contains(calendar.component(.weekday, from: day))
            }
        }
    }

    public func complete(_ timer: TimerItem, at date: Date) throws -> CompletionOutcome {
        try RecurrenceService(calendar: calendar).complete(timer, at: date)
    }

    private func nextIntervalDate(after reference: Date, seconds: TimeInterval) throws -> Date {
        try validateRule(.interval(seconds: seconds))
        let result = reference.addingTimeInterval(seconds)
        guard result.timeIntervalSinceReferenceDate.isFinite, result > reference else {
            throw RecurrenceCalculatorError.invalidReferenceDate
        }
        return result
    }

    private func nextCalendarDate(
        after reference: Date,
        hour: Int,
        minute: Int,
        matchesDay: (Date) -> Bool
    ) throws -> Date {
        let firstDay = calendar.startOfDay(for: reference)
        guard firstDay.timeIntervalSinceReferenceDate.isFinite else {
            throw RecurrenceCalculatorError.invalidReferenceDate
        }

        for offset in 0..<Self.maximumCandidateDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay),
                  day.timeIntervalSinceReferenceDate.isFinite else {
                continue
            }
            guard matchesDay(day) else { continue }

            var components = DateComponents()
            components.hour = hour
            components.minute = minute
            let searchStart = offset == 0 ? reference : day.addingTimeInterval(-1)
            guard searchStart.isFiniteDate,
                  let candidate = calendar.nextDate(
                      after: searchStart,
                      matching: components,
                      matchingPolicy: .nextTime,
                      repeatedTimePolicy: .first,
                      direction: .forward
                  ) else {
                continue
            }
            guard candidate.timeIntervalSinceReferenceDate.isFinite else { continue }
            guard isSameCalendarDay(candidate, day), candidate > reference else { continue }
            return candidate
        }
        throw RecurrenceCalculatorError.noDateFound
    }

    private func isSameCalendarDay(_ lhs: Date, _ rhs: Date) -> Bool {
        let components: Set<Calendar.Component> = [.era, .year, .month, .day]
        return calendar.dateComponents(components, from: lhs) == calendar.dateComponents(components, from: rhs)
    }

    private func validateRule(_ rule: RecurrenceRule) throws {
        do {
            try RecurrenceRuleValidator.validate(rule)
        } catch let error as RecurrenceValidationError {
            switch error {
            case .invalidInterval:
                throw RecurrenceCalculatorError.invalidInterval
            case .invalidClockTime:
                throw RecurrenceCalculatorError.invalidClockTime
            case .invalidWeekday:
                throw RecurrenceCalculatorError.invalidWeekday
            case .emptyWeekdays:
                throw RecurrenceCalculatorError.emptyWeekdays
            }
        }
    }
}

private extension Date {
    var isFiniteDate: Bool {
        timeIntervalSinceReferenceDate.isFinite
    }
}

public enum CompletionOutcomeValidationError: Error, Equatable, Sendable {
    case successorIDMismatch
    case predecessorOccurrenceIDMismatch
    case duplicateIdentity
    case invalidSuccessorState
}

public struct CompletionOutcome: Codable, Equatable, Sendable {
    public let completed: TimerItem
    public let successor: TimerItem?

    internal init(completed: TimerItem, successor: TimerItem?) throws {
        try Self.validate(completed: completed, successor: successor)
        self.completed = completed
        self.successor = successor
    }

    private static func validate(completed: TimerItem, successor: TimerItem?) throws {
        guard let successor else { return }
        guard completed.successorID == successor.id else {
            throw CompletionOutcomeValidationError.successorIDMismatch
        }
        guard successor.predecessorOccurrenceID == completed.occurrenceID else {
            throw CompletionOutcomeValidationError.predecessorOccurrenceIDMismatch
        }
        guard completed.id != successor.id, completed.occurrenceID != successor.occurrenceID else {
            throw CompletionOutcomeValidationError.duplicateIdentity
        }
        guard successor.kind == .countdown, successor.state == .running else {
            throw CompletionOutcomeValidationError.invalidSuccessorState
        }
    }

    private enum CodingKeys: String, CodingKey {
        case completed
        case successor
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let completed = try container.decode(TimerItem.self, forKey: .completed)
        let successor = try container.decodeIfPresent(TimerItem.self, forKey: .successor)
        do {
            try self.init(completed: completed, successor: successor)
        } catch {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Completion outcome links are inconsistent")
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        try Self.validate(completed: completed, successor: successor)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(completed, forKey: .completed)
        try container.encodeIfPresent(successor, forKey: .successor)
    }
}

public struct RecurrenceService: Sendable {
    private let calculator: RecurrenceCalculator

    public init(calendar: Calendar = .autoupdatingCurrent) {
        calculator = RecurrenceCalculator(calendar: calendar)
    }

    public func complete(_ timer: TimerItem, at date: Date) throws -> CompletionOutcome {
        if timer.kind == .stopwatch, timer.recurrence != .none {
            throw TimerValidationError.recurrenceUnsupportedForStopwatch
        }
        switch timer.state {
        case .cancelled:
            throw TimerTransitionError.invalidState
        case .completed, .acknowledged:
            guard timer.successorID != nil else {
                throw TimerTransitionError.alreadyCompleted
            }
            return try CompletionOutcome(completed: timer, successor: nil)
        default:
            break
        }

        var completed = timer
        try completed.complete(at: date)
        guard completed.kind == .countdown, completed.recurrence != .none else {
            return try CompletionOutcome(completed: completed, successor: nil)
        }

        let nextDate = try calculator.nextDate(after: date, rule: completed.recurrence)
        guard completed.duration != nil else {
            throw TimerTransitionError.invalidState
        }
        let scheduledDuration = nextDate.timeIntervalSince(date)
        guard scheduledDuration.isFinite, scheduledDuration > 0 else {
            throw RecurrenceCalculatorError.invalidReferenceDate
        }
        let stableTimerID = StableRecurrenceIdentity.timerID(
            sourceOccurrenceID: completed.occurrenceID,
            scheduledDeadline: nextDate
        )
        let stableOccurrenceID = StableRecurrenceIdentity.occurrenceID(
            sourceOccurrenceID: completed.occurrenceID,
            scheduledDeadline: nextDate
        )
        var successor = try TimerItem.countdown(
            title: completed.title,
            duration: scheduledDuration,
            details: completed.details,
            tags: completed.tags,
            recurrence: completed.recurrence,
            alertName: completed.alertName,
            alertVolume: completed.alertVolume,
            id: stableTimerID,
            occurrenceID: stableOccurrenceID,
            createdAt: date
        )

        // A successor is immediately schedulable. Its deadline is the next
        // wall-clock occurrence, rather than duration after the completion.
        successor.state = .running
        successor.startedAt = date
        successor.lastTransitionAt = date
        successor.deadline = nextDate
        successor.remaining = nil
        successor.predecessorOccurrenceID = completed.occurrenceID
        completed.successorID = stableTimerID
        return try CompletionOutcome(completed: completed, successor: successor)
    }
}

public typealias RecurrenceCompletionService = RecurrenceService

private enum StableRecurrenceIdentity {
    private static let timerNamespace: UInt64 = 0x5449_4D45_525F_4944
    private static let occurrenceNamespace: UInt64 = 0x4F43_4355_525F_4944

    static func timerID(sourceOccurrenceID: UUID, scheduledDeadline: Date) -> UUID {
        makeUUID(sourceOccurrenceID: sourceOccurrenceID, scheduledDeadline: scheduledDeadline, namespace: timerNamespace)
    }

    static func occurrenceID(sourceOccurrenceID: UUID, scheduledDeadline: Date) -> UUID {
        makeUUID(sourceOccurrenceID: sourceOccurrenceID, scheduledDeadline: scheduledDeadline, namespace: occurrenceNamespace)
    }

    private static func makeUUID(sourceOccurrenceID: UUID, scheduledDeadline: Date, namespace: UInt64) -> UUID {
        var input = [UInt8]()
        input.reserveCapacity(32)
        withUnsafeBytes(of: sourceOccurrenceID.uuid) { input.append(contentsOf: $0) }
        var deadlineBits = scheduledDeadline.timeIntervalSinceReferenceDate.bitPattern
        for _ in 0..<8 {
            input.append(UInt8(truncatingIfNeeded: deadlineBits))
            deadlineBits >>= 8
        }

        var first = 0xcbf2_9ce4_8422_2325 ^ namespace
        var second = 0x8422_2325_cbf2_9ce4 ^ ((namespace << 17) | (namespace >> 47))
        for byte in input {
            first ^= UInt64(byte)
            first &*= 0x0000_0100_0000_01B3
            second ^= UInt64(byte)
            second &*= 0x0000_0100_0000_01B3
            second ^= (first >> 23) | (first << 41)
        }

        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<8 {
            bytes[index] = UInt8(truncatingIfNeeded: first >> (index * 8))
            bytes[index + 8] = UInt8(truncatingIfNeeded: second >> (index * 8))
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
