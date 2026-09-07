import Charts
import SwiftUI
import TopTimerDomain

public struct ReportsView: View {
  @ObservedObject private var state: AppState
  @State private var from = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
  @State private var through = Date.now
  public init(state: AppState) { self.state = state }
  public var body: some View {
    VStack(alignment: .leading) {
      HStack { DatePicker("From", selection: $from, displayedComponents: .date); DatePicker("Through", selection: $through, displayedComponents: .date); Button("Update") { load() } }.padding()
      if state.historyLoading { ProgressView("Loading report…").frame(maxWidth: .infinity, maxHeight: .infinity) }
      else if let error = state.inlineError { VStack { Text(error); Button("Try again") { load() } }.frame(maxWidth: .infinity, maxHeight: .infinity) }
      else if rows.isEmpty { VStack { Text("No timer activity in this range"); Button("Choose last 30 days") { from = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now; load() } }.frame(maxWidth: .infinity, maxHeight: .infinity) }
      else {
        Chart(daily, id: \.date) { item in BarMark(x: .value("Day", item.date), y: .value("Seconds", item.seconds)).foregroundStyle(Color.accentColor) }.frame(height: 150).accessibilityLabel("Daily timer totals")
        Chart(weekly, id: \.date) { item in BarMark(x: .value("Week", item.date), y: .value("Seconds", item.seconds)).foregroundStyle(Color.orange) }.frame(height: 150).accessibilityLabel("Weekly timer totals")
        HStack { totalsTable("Timers", values: timerTotals); totalsTable("Tags", values: tagTotals) }
      }
    }.padding().frame(minWidth: 680, minHeight: 500).accessibilityIdentifier("reports-view").onAppear { load() }
  }
  private var rows: [HistoryEntry] { Array(state.historyPage.entries.prefix(200)) }
  private var daily: [(date: Date, seconds: Double)] { ((try? HistoryAnalytics().totalsByDay(rows)) ?? [:]).map { ($0.key, $0.value) }.sorted { $0.date < $1.date } }
  private var weekly: [(date: Date, seconds: Double)] { ((try? HistoryAnalytics().totalsByWeek(rows)) ?? [:]).map { ($0.key, $0.value) }.sorted { $0.date < $1.date } }
  private var timerTotals: [(String, Double)] { Dictionary(grouping: rows, by: { $0.timerID }).map { ($0.value.first?.title ?? "Untitled timer", $0.value.reduce(0) { $0 + $1.elapsedSeconds }) }.sorted { $0.1 > $1.1 } }
  private var tagTotals: [(String, Double)] { ((try? HistoryAnalytics().totalsByTag(rows)) ?? [:]).map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 } }
  private func load() { state.perform { await state.loadHistory(from: from, through: through, query: "") } }
  private func totalsTable(_ title: String, values: [(String, Double)]) -> some View { VStack(alignment: .leading) { Text(title).font(.headline); ForEach(Array(values.prefix(100).enumerated()), id: \.offset) { _, value in HStack { Text(value.0); Spacer(); Text(Duration.seconds(value.1).formatted(.time(pattern: .hourMinute))) } } }.frame(maxWidth: .infinity, alignment: .topLeading).accessibilityElement(children: .contain).accessibilityLabel("\(title) totals") }
}
