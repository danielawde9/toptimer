import Foundation

public struct CSVExporter {
    private static let columns = [
        "id", "title", "description", "tags", "kind", "started_at", "ended_at", "elapsed_seconds", "reason"
    ]

    public init() {}

    public func export(_ entries: [HistoryEntry]) throws -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var lines = [Self.columns.joined(separator: ",")]
        lines.reserveCapacity(entries.count + 1)
        for entry in entries {
            lines.append(row(for: entry, formatter: formatter))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    private func row(for entry: HistoryEntry, formatter: ISO8601DateFormatter) -> String {
        [
            entry.id.uuidString.lowercased(),
            entry.title,
            entry.details,
            entry.tags.sorted().joined(separator: "|"),
            entry.kind.rawValue,
            entry.startedAt.map(formatter.string(from:)) ?? "",
            formatter.string(from: entry.endedAt),
            String(format: "%.15g", locale: Locale(identifier: "en_US_POSIX"), entry.elapsedSeconds),
            entry.completionReason.rawValue
        ]
        .map(escape)
        .joined(separator: ",")
    }

    private func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\r") || field.contains("\n") else {
            return field
        }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
