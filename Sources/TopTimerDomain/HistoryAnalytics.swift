import Foundation

public enum HistoryAnalyticsError: Error, Equatable, Sendable {
    case tooManyEntries
}

public struct HistoryAnalytics: Sendable {
    public static let maximumEntries = 10_000

    private let calendar: Calendar

    public init(calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
    }

    public func filter(_ entries: [HistoryEntry], query: String) throws -> [HistoryEntry] {
        try validate(entries)
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else { return entries }
        return entries.filter { entry in
            searchableValues(for: entry).contains { normalize($0).contains(normalizedQuery) }
        }
    }

    public func totalsByDay(_ entries: [HistoryEntry]) throws -> [Date: TimeInterval] {
        try totals(entries) { calendar.startOfDay(for: $0.endedAt) }
    }

    public func totalsByWeek(_ entries: [HistoryEntry]) throws -> [Date: TimeInterval] {
        try totals(entries) { date in
            calendar.dateInterval(of: .weekOfYear, for: date.endedAt)?.start ?? calendar.startOfDay(for: date.endedAt)
        }
    }

    public func totalsByTimer(_ entries: [HistoryEntry]) throws -> [UUID: TimeInterval] {
        try totals(entries, key: \.timerID)
    }

    public func totalsByTag(_ entries: [HistoryEntry]) throws -> [String: TimeInterval] {
        try validate(entries)
        var results: [String: TimeInterval] = [:]
        for entry in entries {
            var seenTags = Set<String>()
            for tag in entry.tags {
                let normalizedTag = normalize(tag)
                if seenTags.insert(normalizedTag).inserted {
                    results[normalizedTag, default: 0] += entry.elapsedSeconds
                }
            }
        }
        return results
    }

    private func totals<Key: Hashable>(
        _ entries: [HistoryEntry],
        key: (HistoryEntry) -> Key
    ) throws -> [Key: TimeInterval] {
        try validate(entries)
        var results: [Key: TimeInterval] = [:]
        for entry in entries {
            results[key(entry), default: 0] += entry.elapsedSeconds
        }
        return results
    }

    private func validate(_ entries: [HistoryEntry]) throws {
        guard entries.count <= Self.maximumEntries else { throw HistoryAnalyticsError.tooManyEntries }
    }

    private func searchableValues(for entry: HistoryEntry) -> [String] {
        [entry.title, entry.details] + entry.tags
    }

    private func normalize(_ value: String) -> String {
        value
            .precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
