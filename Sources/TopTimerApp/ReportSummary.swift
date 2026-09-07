import Foundation
import TopTimerDomain

public struct ReportTotal: Identifiable, Equatable, Sendable {
  public let id: String
  public let name: String
  public let seconds: Double
}
public struct ReportPoint: Equatable, Sendable {
  public let date: Date
  public let seconds: Double
}
public struct ReportSummary: Equatable, Sendable {
  public static let empty = ReportSummary()
  public let daily: [ReportPoint]
  public let weekly: [ReportPoint]
  public let timerTotals: [ReportTotal]
  public let tagTotals: [ReportTotal]
  private init() {
    daily = []
    weekly = []
    timerTotals = []
    tagTotals = []
  }
  public init(entries: [HistoryEntry], calendar: Calendar = .current) throws {
    let analytics = HistoryAnalytics(calendar: calendar)
    daily = try analytics.totalsByDay(entries).map { ReportPoint(date: $0.key, seconds: $0.value) }
      .sorted { $0.date < $1.date }
    weekly = try analytics.totalsByWeek(entries).map {
      ReportPoint(date: $0.key, seconds: $0.value)
    }.sorted { $0.date < $1.date }
    let names = Dictionary(grouping: entries, by: \.timerID).mapValues { $0.first?.title ?? "" }
    timerTotals = try analytics.totalsByTimer(entries).map {
      ReportTotal(
        id: $0.key.uuidString,
        name: names[$0.key].flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled timer", seconds: $0.value
      )
    }.sorted { ($0.seconds, $0.id) > ($1.seconds, $1.id) }
    tagTotals = try analytics.totalsByTag(entries).map {
      ReportTotal(id: $0.key, name: $0.key, seconds: $0.value)
    }.sorted { ($0.seconds, $0.id) > ($1.seconds, $1.id) }
  }
}
