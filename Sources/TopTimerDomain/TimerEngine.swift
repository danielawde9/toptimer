import Foundation

public enum TimerTransitionError: Error, Equatable, Sendable {
    case invalidState
    case alreadyCompleted
    case notDue
    case invalidTimestamp
}

private func validTimerDate(_ date: Date) -> Bool {
    date.timeIntervalSinceReferenceDate.isFinite
}

private func dateByAdding(_ seconds: TimeInterval, to date: Date) throws -> Date {
    guard seconds.isFinite, validTimerDate(date) else {
        throw TimerTransitionError.invalidTimestamp
    }
    let result = date.addingTimeInterval(seconds)
    guard validTimerDate(result) else {
        throw TimerTransitionError.invalidTimestamp
    }
    return result
}

private func requireNotBefore(_ date: Date, _ earlierDate: Date) throws {
    guard validTimerDate(date), validTimerDate(earlierDate), date >= earlierDate else {
        throw TimerTransitionError.invalidTimestamp
    }
}

public extension TimerItem {
    mutating func start(at date: Date) throws {
        guard state == .idle else {
            throw TimerTransitionError.invalidState
        }
        guard validTimerDate(date) else {
            throw TimerTransitionError.invalidTimestamp
        }
        try requireNotBefore(date, createdAt)

        switch kind {
        case .countdown:
            guard let duration else { throw TimerTransitionError.invalidState }
            deadline = try dateByAdding(duration, to: date)
            remaining = nil
        case .stopwatch:
            accumulatedPause = 0
        }
        state = .running
        startedAt = date
        pausedAt = nil
        lastTransitionAt = date
        completedAt = nil
        deletedAt = nil
    }

    mutating func pause(at date: Date) throws {
        guard state == .running else {
            throw TimerTransitionError.invalidState
        }
        guard let startedAt else { throw TimerTransitionError.invalidState }
        try requireNotBefore(date, lastTransitionAt ?? startedAt)

        switch kind {
        case .countdown:
            guard let deadline else { throw TimerTransitionError.invalidState }
            let liveRemaining = deadline.timeIntervalSince(date)
            guard liveRemaining.isFinite else {
                throw TimerTransitionError.invalidTimestamp
            }
            remaining = max(0, liveRemaining)
            self.deadline = nil
        case .stopwatch:
            break
        }
        state = .paused
        pausedAt = date
        lastTransitionAt = date
    }

    mutating func resume(at date: Date) throws {
        guard state == .paused else {
            throw TimerTransitionError.invalidState
        }
        guard let startedAt, let pausedAt else {
            throw TimerTransitionError.invalidState
        }
        try requireNotBefore(date, lastTransitionAt ?? pausedAt)

        switch kind {
        case .countdown:
            guard let remaining else { throw TimerTransitionError.invalidState }
            deadline = try dateByAdding(remaining, to: date)
            self.remaining = nil
        case .stopwatch:
            let pauseLength = date.timeIntervalSince(pausedAt)
            let totalPause = accumulatedPause + pauseLength
            guard totalPause.isFinite, totalPause >= accumulatedPause else {
                throw TimerTransitionError.invalidTimestamp
            }
            accumulatedPause = totalPause
        }
        state = .running
        self.startedAt = startedAt
        self.pausedAt = nil
        lastTransitionAt = date
    }

    mutating func restart(at date: Date) throws {
        guard validTimerDate(date) else {
            throw TimerTransitionError.invalidTimestamp
        }
        try requireNotBefore(date, createdAt)
        if let lastTransitionAt {
            try requireNotBefore(date, lastTransitionAt)
        }

        switch kind {
        case .countdown:
            guard let duration else { throw TimerTransitionError.invalidState }
            deadline = try dateByAdding(duration, to: date)
            remaining = nil
            accumulatedPause = 0
        case .stopwatch:
            deadline = nil
            remaining = nil
            accumulatedPause = 0
        }
        state = .running
        startedAt = date
        pausedAt = nil
        lastTransitionAt = date
        completedAt = nil
        deletedAt = nil
    }

    mutating func complete(at date: Date) throws {
        guard validTimerDate(date) else {
            throw TimerTransitionError.invalidTimestamp
        }
        if state == .completed || state == .acknowledged {
            throw TimerTransitionError.alreadyCompleted
        }
        guard let temporalFloor = lastTransitionAt ?? pausedAt ?? startedAt else {
            throw TimerTransitionError.invalidState
        }
        try requireNotBefore(date, temporalFloor)

        switch kind {
        case .countdown:
            guard state == .running, let deadline else {
                throw TimerTransitionError.invalidState
            }
            guard date >= deadline else {
                throw TimerTransitionError.notDue
            }
            remaining = 0
            self.deadline = nil
        case .stopwatch:
            guard state == .running || state == .paused else {
                throw TimerTransitionError.invalidState
            }
            let pauseLength: TimeInterval
            if state == .paused {
                guard let pausedAt else { throw TimerTransitionError.invalidState }
                try requireNotBefore(date, pausedAt)
                pauseLength = date.timeIntervalSince(pausedAt)
            } else {
                guard let startedAt else { throw TimerTransitionError.invalidState }
                try requireNotBefore(date, startedAt)
                pauseLength = 0
            }
            let totalPause = accumulatedPause + pauseLength
            guard totalPause.isFinite, totalPause >= accumulatedPause else {
                throw TimerTransitionError.invalidTimestamp
            }
            accumulatedPause = totalPause
            self.deadline = nil
        }
        state = .completed
        pausedAt = nil
        lastTransitionAt = date
        completedAt = date
        deletedAt = nil
    }

    mutating func cancel(at date: Date) throws {
        guard validTimerDate(date) else {
            throw TimerTransitionError.invalidTimestamp
        }
        guard state == .running || state == .paused else {
            throw TimerTransitionError.invalidState
        }
        guard let temporalFloor = lastTransitionAt ?? pausedAt ?? startedAt else {
            throw TimerTransitionError.invalidState
        }
        try requireNotBefore(date, temporalFloor)

        switch kind {
        case .countdown:
            if state == .running {
                guard let deadline else { throw TimerTransitionError.invalidState }
                let liveRemaining = deadline.timeIntervalSince(date)
                guard liveRemaining.isFinite else {
                    throw TimerTransitionError.invalidTimestamp
                }
                remaining = max(0, liveRemaining)
                self.deadline = nil
            }
        case .stopwatch:
            if state == .paused {
                guard let pausedAt else { throw TimerTransitionError.invalidState }
                let pauseLength = date.timeIntervalSince(pausedAt)
                let totalPause = accumulatedPause + pauseLength
                guard totalPause.isFinite, totalPause >= accumulatedPause else {
                    throw TimerTransitionError.invalidTimestamp
                }
                accumulatedPause = totalPause
            }
        }
        state = .cancelled
        pausedAt = nil
        lastTransitionAt = date
        completedAt = date
        deletedAt = nil
    }

    mutating func acknowledge(at date: Date = .now) throws {
        guard state == .completed else {
            throw TimerTransitionError.invalidState
        }
        guard validTimerDate(date) else {
            throw TimerTransitionError.invalidTimestamp
        }
        if let temporalFloor = lastTransitionAt ?? completedAt {
            try requireNotBefore(date, temporalFloor)
        }
        state = .acknowledged
        deletedAt = date
        lastTransitionAt = date
    }

    func duplicate(at date: Date = .now) throws -> TimerItem {
        guard validTimerDate(date) else {
            throw TimerTransitionError.invalidTimestamp
        }
        switch kind {
        case .countdown:
            guard let duration else { throw TimerTransitionError.invalidState }
            return try TimerItem.countdown(
                title: title,
                duration: duration,
                details: details,
                tags: tags,
                recurrence: recurrence,
                alertName: alertName,
                alertVolume: alertVolume,
                createdAt: date
            )
        case .stopwatch:
            return try TimerItem.stopwatch(
                title: title,
                details: details,
                tags: tags,
                recurrence: recurrence,
                alertName: alertName,
                alertVolume: alertVolume,
                createdAt: date
            )
        }
    }

    /// Returns the live countdown value without mutating persisted state.
    func remaining(at date: Date) -> TimeInterval? {
        guard kind == .countdown else { return nil }
        switch state {
        case .idle, .paused:
            return remaining
        case .running:
            guard let deadline else { return nil }
            let liveRemaining = deadline.timeIntervalSince(date)
            guard liveRemaining.isFinite else { return nil }
            return max(0, liveRemaining)
        case .completed, .acknowledged, .cancelled:
            return 0
        }
    }

    /// Returns stopwatch time excluding all paused wall-clock segments.
    func elapsed(at date: Date) -> TimeInterval? {
        guard kind == .stopwatch, let startedAt else { return kind == .stopwatch ? 0 : nil }
        let endDate: Date
        switch state {
        case .paused:
            guard let pausedAt else { return nil }
            endDate = pausedAt
        case .completed, .acknowledged, .cancelled:
            guard let completedAt else { return nil }
            endDate = completedAt
        default:
            endDate = date
        }
        let elapsed = endDate.timeIntervalSince(startedAt) - accumulatedPause
        guard elapsed.isFinite else { return nil }
        return max(0, elapsed)
    }

    func isDue(at date: Date) -> Bool {
        guard kind == .countdown, state == .running, let deadline else { return false }
        return date >= deadline
    }
}

public enum TimerPriority {
    public static func select(from timers: [TimerItem], at _: Date) -> TimerItem? {
        var earliestCountdown: TimerItem?
        var earliestStopwatch: TimerItem?

        for timer in timers where timer.state == .running {
            switch timer.kind {
            case .countdown:
                if isEarlierCountdown(timer, than: earliestCountdown) {
                    earliestCountdown = timer
                }
            case .stopwatch:
                if isEarlierStopwatch(timer, than: earliestStopwatch) {
                    earliestStopwatch = timer
                }
            }
        }
        return earliestCountdown ?? earliestStopwatch
    }

    private static func isEarlierCountdown(_ candidate: TimerItem, than current: TimerItem?) -> Bool {
        guard let current else { return true }
        let candidateDeadline = candidate.deadline ?? .distantFuture
        let currentDeadline = current.deadline ?? .distantFuture
        return candidateDeadline < currentDeadline
            || (candidateDeadline == currentDeadline && candidate.id.uuidString < current.id.uuidString)
    }

    private static func isEarlierStopwatch(_ candidate: TimerItem, than current: TimerItem?) -> Bool {
        guard let current else { return true }
        let candidateStart = candidate.startedAt ?? .distantFuture
        let currentStart = current.startedAt ?? .distantFuture
        return candidateStart < currentStart
            || (candidateStart == currentStart && candidate.id.uuidString < current.id.uuidString)
    }
}
