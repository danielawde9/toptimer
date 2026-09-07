import Foundation

public struct HistoryDateRange: Equatable, Sendable {
  public let from: Date
  public let before: Date
  public init(from: Date, through: Date, calendar: Calendar = .current) throws {
    guard from.timeIntervalSinceReferenceDate.isFinite,
      through.timeIntervalSinceReferenceDate.isFinite,
      let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: through))
    else { throw CocoaError(.validationDateTooLate) }
    self.from = calendar.startOfDay(for: from)
    before = next
    guard self.from < before else { throw CocoaError(.validationDateTooSoon) }
  }
  /// The repository's existing inclusive API uses the immediately preceding
  /// representable instant, not a fixed second or millisecond subtraction.
  public var inclusiveUpperBound: Date {
    Date(timeIntervalSinceReferenceDate: before.timeIntervalSinceReferenceDate.nextDown)
  }
}
