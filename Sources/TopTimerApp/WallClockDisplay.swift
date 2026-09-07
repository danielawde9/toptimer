import Foundation

public enum WallClockDisplay {
  public static func string(
    _ date: Date, uses24HourTime: Bool, includesDate: Bool = false, timeZone: TimeZone = .current
  ) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    formatter.dateFormat =
      (includesDate ? "yyyy-MM-dd " : "") + (uses24HourTime ? "HH:mm" : "h:mm a")
    return formatter.string(from: date)
  }
}
