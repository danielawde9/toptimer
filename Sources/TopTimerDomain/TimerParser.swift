import Foundation

public enum TimerParserError: Error, Equatable, Sendable {
    case inputTooLong
    case invalidFormat
    case invalidNumber
    case unsupportedSuffix
    case duplicateUnit
    case negativeValue
    case nonPositiveDuration
    case nonFiniteValue
    case durationTooLong
    case invalidWallClock
    case malformedTag
}

public struct ParsedTimer: Equatable, Sendable {
    public let kind: TimerKind
    public let duration: TimeInterval?
    public let deadline: Date?
    public let title: String
    public let tags: [String]

    public init(
        kind: TimerKind,
        duration: TimeInterval?,
        deadline: Date?,
        title: String,
        tags: [String]
    ) {
        self.kind = kind
        self.duration = duration
        self.deadline = deadline
        self.title = title
        self.tags = tags
    }
}

public struct TimerParser: Sendable {
    private static let maxInputScalars = 2_048
    private static let maxDuration: TimeInterval = 365 * 24 * 60 * 60

    private let calendar: Calendar
    private let now: Date

    public init(calendar: Calendar = .current, now: Date = .now) {
        self.calendar = calendar
        self.now = now
    }

    public func parse(_ input: String) throws -> ParsedTimer {
        guard input.unicodeScalars.count <= Self.maxInputScalars else {
            throw TimerParserError.inputTooLong
        }

        let tokens = input.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !tokens.isEmpty else {
            return ParsedTimer(kind: .stopwatch, duration: nil, deadline: nil, title: "", tags: [])
        }

        let timing = try parseTiming(from: tokens)
        var titleTokens: [String] = []
        var tags: [String] = []

        for token in tokens.dropFirst(timing.consumedTokens) {
            if token.contains("#") {
                guard token.first == "#", token.count > 1, !token.dropFirst().contains("#") else {
                    throw TimerParserError.malformedTag
                }
                tags.append(String(token.dropFirst()))
            } else {
                titleTokens.append(token)
            }
        }

        let title = titleTokens.joined(separator: " ")
        try validateMetadata(title: title, tags: tags)
        return ParsedTimer(
            kind: .countdown,
            duration: timing.duration,
            deadline: timing.deadline,
            title: title,
            tags: tags
        )
    }

    private struct Timing {
        let duration: TimeInterval
        let deadline: Date?
        let consumedTokens: Int
    }

    private struct UnitPart {
        let unit: Character
        let seconds: TimeInterval
    }

    private func parseTiming(from tokens: [String]) throws -> Timing {
        let first = tokens[0]
        if first.first == "@" {
            return try parseWallClock(first)
        }
        if first.contains(":") {
            return Timing(duration: try parseColonDuration(first), deadline: nil, consumedTokens: 1)
        }

        var total: TimeInterval = 0
        var consumed = 0
        var units = Set<Character>()
        while consumed < tokens.count {
            let token = tokens[consumed]
            guard let part = try parseUnitToken(token, allowBare: consumed == 0) else {
                break
            }
            guard units.insert(part.unit).inserted else {
                throw TimerParserError.duplicateUnit
            }
            total = total + part.seconds
            guard total.isFinite else {
                throw TimerParserError.nonFiniteValue
            }
            consumed += 1
        }

        guard consumed > 0 else {
            throw TimerParserError.invalidFormat
        }
        guard total > 0 else {
            throw TimerParserError.nonPositiveDuration
        }
        guard total <= Self.maxDuration else {
            throw TimerParserError.durationTooLong
        }
        return Timing(duration: total, deadline: nil, consumedTokens: consumed)
    }

    private func parseUnitToken(_ token: String, allowBare: Bool) throws -> UnitPart? {
        let scalars = Array(token.unicodeScalars)
        guard !scalars.isEmpty else { return nil }

        let lower = token.lowercased()
        if lower == "nan" || lower == "infinity" || lower == "+infinity" || lower == "-infinity" {
            throw TimerParserError.nonFiniteValue
        }

        if let last = lower.last, "smhd".contains(last) {
            let numberText = String(lower.dropLast())
            guard !numberText.isEmpty else {
                throw TimerParserError.invalidNumber
            }
            guard let value = Double(numberText) else {
                guard numericPrefixEnd(scalars) > 0 else {
                    if allowBare { throw TimerParserError.invalidNumber }
                    return nil
                }
                throw TimerParserError.unsupportedSuffix
            }
            guard value.isFinite else {
                throw TimerParserError.nonFiniteValue
            }
            if value < 0 {
                throw TimerParserError.negativeValue
            }
            let seconds = value * multiplier(for: last)
            guard seconds.isFinite else {
                throw TimerParserError.nonFiniteValue
            }
            guard seconds <= Self.maxDuration else {
                throw TimerParserError.durationTooLong
            }
            return UnitPart(unit: last, seconds: seconds)
        }

        let numericEnd = numericPrefixEnd(scalars)
        guard numericEnd > 0 else {
            if allowBare { throw TimerParserError.invalidFormat }
            return nil
        }
        let numberText = String(String.UnicodeScalarView(scalars[..<numericEnd]))
        let suffix = String(String.UnicodeScalarView(scalars[numericEnd...]))
        guard suffix.isEmpty else {
            throw TimerParserError.unsupportedSuffix
        }
        guard let value = Double(numberText) else {
            throw TimerParserError.invalidNumber
        }
        guard value.isFinite else {
            throw TimerParserError.nonFiniteValue
        }
        if value < 0 {
            throw TimerParserError.negativeValue
        }
        let seconds = value * 60
        guard seconds.isFinite else {
            throw TimerParserError.nonFiniteValue
        }
        guard seconds <= Self.maxDuration else {
            throw TimerParserError.durationTooLong
        }
        guard allowBare else { return nil }
        return UnitPart(unit: "m", seconds: seconds)
    }

    private func numericPrefixEnd(_ scalars: [Unicode.Scalar]) -> Int {
        var index = 0
        var hasDigits = false
        var hasExponent = false
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar.isASCII, scalar.value >= 48, scalar.value <= 57 {
                hasDigits = true
                index += 1
            } else if scalar == "." && !hasExponent {
                index += 1
            } else if (scalar == "e" || scalar == "E") && hasDigits && !hasExponent {
                hasExponent = true
                index += 1
                if index < scalars.count && (scalars[index] == "+" || scalars[index] == "-") {
                    index += 1
                }
            } else if (scalar == "+" || scalar == "-") && index == 0 {
                index += 1
            } else {
                break
            }
        }
        return hasDigits ? index : 0
    }

    private func multiplier(for unit: Character) -> TimeInterval {
        switch unit {
        case "s": return 1
        case "m": return 60
        case "h": return 60 * 60
        case "d": return 24 * 60 * 60
        default: return 0
        }
    }

    private func parseColonDuration(_ token: String) throws -> TimeInterval {
        let parts = token.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3 else {
            throw TimerParserError.invalidFormat
        }
        let values = try parts.map(parseUnsignedInteger)
        if values.count == 2 {
            guard values[1] < 60 else { throw TimerParserError.invalidWallClock }
            let seconds = TimeInterval(values[0]) * 60 + TimeInterval(values[1])
            return try checkedDuration(seconds)
        }
        guard values[1] < 60, values[2] < 60 else {
            throw TimerParserError.invalidWallClock
        }
        let seconds = TimeInterval(values[0]) * 3_600 + TimeInterval(values[1]) * 60 + TimeInterval(values[2])
        return try checkedDuration(seconds)
    }

    private func parseUnsignedInteger(_ value: Substring) throws -> Int {
        guard !value.isEmpty else { throw TimerParserError.invalidNumber }
        guard value.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            if value.first == "-" { throw TimerParserError.negativeValue }
            throw TimerParserError.invalidNumber
        }
        guard let result = Int(value) else { throw TimerParserError.durationTooLong }
        return result
    }

    private func checkedDuration(_ duration: TimeInterval) throws -> TimeInterval {
        guard duration.isFinite else { throw TimerParserError.nonFiniteValue }
        guard duration > 0 else { throw TimerParserError.nonPositiveDuration }
        guard duration <= Self.maxDuration else { throw TimerParserError.durationTooLong }
        return duration
    }

    private func parseWallClock(_ token: String) throws -> Timing {
        let text = String(token.dropFirst()).lowercased()
        guard !text.isEmpty else { throw TimerParserError.invalidWallClock }

        let isPM = text.hasSuffix("pm")
        let isAM = text.hasSuffix("am")
        let hasMeridiem = isPM || isAM
        let clockText = hasMeridiem ? String(text.dropLast(2)) : text
        let parts = clockText.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 1 || parts.count == 2 else {
            throw TimerParserError.invalidWallClock
        }
        let values = try parts.map(parseUnsignedInteger)
        let hour: Int
        let minute: Int
        if values.count == 1 {
            hour = values[0]
            minute = 0
        } else {
            hour = values[0]
            minute = values[1]
        }

        let normalizedHour: Int
        if hasMeridiem {
            guard hour >= 1, hour <= 12, minute < 60 else {
                throw TimerParserError.invalidWallClock
            }
            normalizedHour = (hour % 12) + (isPM ? 12 : 0)
        } else {
            guard hour < 24, minute < 60 else {
                throw TimerParserError.invalidWallClock
            }
            normalizedHour = hour
        }

        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = normalizedHour
        components.minute = minute
        components.second = 0
        guard var deadline = calendar.date(from: components) else {
            throw TimerParserError.invalidWallClock
        }
        if deadline <= now {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: deadline) else {
                throw TimerParserError.invalidWallClock
            }
            deadline = nextDay
        }
        let duration = deadline.timeIntervalSince(now)
        guard duration.isFinite, duration > 0, duration <= Self.maxDuration else {
            throw TimerParserError.durationTooLong
        }
        return Timing(duration: duration, deadline: deadline, consumedTokens: 1)
    }

    private func validateMetadata(title: String, tags: [String]) throws {
        guard title.count <= TimerLimits.title else {
            throw TimerValidationError.titleTooLong
        }
        guard tags.count <= TimerLimits.tags else {
            throw TimerValidationError.tooManyTags
        }
        guard tags.allSatisfy({ $0.count <= TimerLimits.tag }) else {
            throw TimerValidationError.tagTooLong
        }
    }
}
