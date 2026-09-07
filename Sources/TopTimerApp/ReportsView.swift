import Charts
import SwiftUI
import TopTimerDomain

public struct ReportsView: View {
  @ObservedObject private var state: AppState
  @State private var from = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
  @State private var through = Date.now
  @State private var rangeError: String?
  public init(state: AppState) { self.state = state }
  public var body: some View {
    VStack(alignment: .leading) {
      HStack {
        DatePicker("From", selection: $from, displayedComponents: .date)
        DatePicker("Through", selection: $through, displayedComponents: .date)
        Button("Update") { load() }
      }.padding()
      if state.reportsLoading {
        VStack {
          ProgressView("Loading report…")
          Button("Cancel") { state.cancelReportsLoad() }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let error = rangeError ?? state.reportsError {
        VStack {
          Text(error)
          Button("Try again") { load() }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if rows.isEmpty {
        VStack {
          Text("No timer activity in this range")
          Button("Choose last 30 days") {
            through = .now
            from = Calendar.current.date(byAdding: .day, value: -30, to: through) ?? through
            load()
          }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        Text("Daily totals").font(.headline)
        Chart(daily, id: \.date) { item in
          BarMark(x: .value("Day", item.date, unit: .day), y: .value("Seconds", item.seconds))
            .foregroundStyle(Color.accentColor)
        }.frame(height: 150).accessibilityLabel("Daily timer totals")
        Text("Weekly totals").font(.headline)
        Chart(weekly, id: \.date) { item in
          BarMark(
            x: .value("Week", item.date, unit: .weekOfYear), y: .value("Seconds", item.seconds)
          ).foregroundStyle(Color.orange)
        }.frame(height: 150).accessibilityLabel("Weekly timer totals")
        HStack {
          totalsTable("Timers", values: timerTotals)
          totalsTable("Tags", values: tagTotals)
        }
      }
    }.padding().frame(minWidth: 680, minHeight: 500).accessibilityIdentifier("reports-view")
      .onAppear { load() }
  }
  private var rows: [HistoryEntry] { state.reportEntries }
  private var daily: [ReportPoint] { state.reportSummary.daily }
  private var weekly: [ReportPoint] { state.reportSummary.weekly }
  private var timerTotals: [ReportTotal] { state.reportSummary.timerTotals }
  private var tagTotals: [ReportTotal] { state.reportSummary.tagTotals }
  private func load() {
    do {
      let range = try HistoryDateRange(from: from, through: through)
      rangeError = nil
      state.perform {
        await state.loadReports(from: range.from, through: range.inclusiveUpperBound)
      }
    } catch { rangeError = "Choose a Through date on or after From, then Update." }
  }
  private func totalsTable(_ title: String, values: [ReportTotal]) -> some View {
    Table(values) {
      TableColumn(title, value: \.name)
      TableColumn("Total duration") {
        Text(Duration.seconds($0.seconds).formatted(.time(pattern: .hourMinuteSecond)))
      }
    }.accessibilityLabel("\(title) totals")
  }
}
