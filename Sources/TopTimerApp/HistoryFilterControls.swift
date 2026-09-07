import Foundation

public struct HistoryQuery: Equatable, Sendable {
  public static let allTime = HistoryQuery(from: nil, through: nil, query: "")
  public let from: Date?
  public let through: Date?
  public let query: String
}

public struct HistoryFilterControls: Equatable, Sendable {
  public var allTime = false
  public var from: Date
  public var through: Date
  public var query = ""
  public init(now: Date = .now, calendar: Calendar = .current) {
    through = now
    from = calendar.date(byAdding: .month, value: -1, to: now) ?? now
  }
  public func validatedQuery(calendar: Calendar = .current) throws -> HistoryQuery {
    let text = String(query.prefix(2048))
    if allTime { return HistoryQuery(from: nil, through: nil, query: text) }
    let range = try HistoryDateRange(from: from, through: through, calendar: calendar)
    return HistoryQuery(from: range.from, through: range.inclusiveUpperBound, query: text)
  }
}
