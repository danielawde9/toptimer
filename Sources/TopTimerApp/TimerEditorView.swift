import SwiftUI
import TopTimerDomain

public enum RecurrenceEditorMode: String, CaseIterable, Sendable {
  case none, interval, daily, weekdays, weekly, selectedWeekdays
}
public enum EditorDraftError: Error, Equatable { case invalid(String) }
public struct EditorDraft: Equatable, Sendable {
  public var kind: TimerKind = .countdown
  public var title = ""
  public var details = ""
  public var tags: [String] = []
  public var duration: TimeInterval = 300
  public var recurrenceMode: RecurrenceEditorMode = .none
  public var interval: TimeInterval = 300
  public var hour = 9
  public var minute = 0
  public var weekday = 2
  public var selectedWeekdays: Set<Int> = []
  public var alertName: String?
  public var volume = 1.0
  public init() {}
  public init(timer: TimerItem) {
    kind = timer.kind
    title = timer.title
    details = timer.details
    tags = timer.tags
    duration = timer.duration ?? 300
    alertName = timer.alertName
    volume = timer.alertVolume
    switch timer.recurrence {
    case .none: break
    case .interval(let seconds):
      recurrenceMode = .interval
      interval = seconds
    case .daily(let hour, let minute):
      recurrenceMode = .daily
      self.hour = hour
      self.minute = minute
    case .weekdays(let hour, let minute):
      recurrenceMode = .weekdays
      self.hour = hour
      self.minute = minute
    case .weekly(let weekday, let hour, let minute):
      recurrenceMode = .weekly
      self.weekday = weekday
      self.hour = hour
      self.minute = minute
    case .selectedWeekdays(let days, let hour, let minute):
      recurrenceMode = .selectedWeekdays
      selectedWeekdays = days
      self.hour = hour
      self.minute = minute
    }
  }
  public func configuration(catalog: SoundCatalog = .builtIn) throws -> TimerConfiguration {
    guard validationError() == nil else { throw EditorDraftError.invalid(validationError()!) }
    if let alertName, !catalog.names.contains(alertName) {
      throw EditorDraftError.invalid("Choose an available alert sound.")
    }
    return TimerConfiguration(
      kind: kind, title: title, details: details, tags: tags,
      duration: kind == .countdown ? duration : nil, recurrence: recurrence(), alertName: alertName,
      alertVolume: volume)
  }
  public func validationError() -> String? {
    if title.count > TimerLimits.title { return "Title must be 80 characters or fewer." }
    if details.count > TimerLimits.details { return "Details must be 500 characters or fewer." }
    if tags.count > TimerLimits.tags { return "Use at most 12 tags." }
    if tags.contains(where: { $0.count > TimerLimits.tag }) {
      return "Tags must be 32 characters or fewer."
    }
    if kind == .countdown
      && (!duration.isFinite || duration < 1 || duration > TimerLimits.maximumDuration)
    {
      return "Duration must be between 1 second and 1 year."
    }
    if !volume.isFinite || !(0...1).contains(volume) { return "Volume must be between 0 and 1." }
    if recurrenceMode == .interval
      && (!interval.isFinite || interval < 1 || interval > TimerLimits.maximumDuration)
    {
      return "Interval must be between 1 second and 1 year."
    }
    if recurrenceMode != .none && recurrenceMode != .interval
      && (!(0...23).contains(hour) || !(0...59).contains(minute))
    {
      return "Choose an hour from 0 to 23 and a minute from 0 to 59."
    }
    if recurrenceMode == .weekly && !(1...7).contains(weekday) {
      return "Choose a weekday from Sunday to Saturday."
    }
    if recurrenceMode == .selectedWeekdays && selectedWeekdays.isEmpty {
      return "Choose at least one weekday."
    }
    if recurrenceMode == .selectedWeekdays && !selectedWeekdays.isSubset(of: Set(1...7)) {
      return "Choose weekdays from Sunday to Saturday."
    }
    if kind == .stopwatch && recurrenceMode != .none { return "Stopwatches cannot recur." }
    return nil
  }
  private func recurrence() -> RecurrenceRule {
    switch recurrenceMode {
    case .none: .none
    case .interval: .interval(seconds: interval)
    case .daily: .daily(hour: hour, minute: minute)
    case .weekdays: .weekdays(hour: hour, minute: minute)
    case .weekly: .weekly(weekday: weekday, hour: hour, minute: minute)
    case .selectedWeekdays:
      .selectedWeekdays(weekdays: selectedWeekdays, hour: hour, minute: minute)
    }
  }
}
public struct TimerEditorView: View {
  @Binding var draft: EditorDraft
  let save: (TimerConfiguration) async -> Bool
  let catalog: SoundCatalog
  @State private var error: String?
  @Environment(\.dismiss) private var dismiss
  public init(
    draft: Binding<EditorDraft>, catalog: SoundCatalog = .builtIn,
    save: @escaping (TimerConfiguration) async -> Bool
  ) {
    _draft = draft
    self.catalog = catalog
    self.save = save
  }
  public var body: some View {
    Form {
      Picker("Timer type", selection: $draft.kind) {
        Text("Countdown").tag(TimerKind.countdown)
        Text("Stopwatch").tag(TimerKind.stopwatch)
      }
      TextField("Title", text: $draft.title).accessibilityIdentifier("timer-editor-title")
      TextField("Details", text: $draft.details, axis: .vertical)
      TextField(
        "Tags",
        text: Binding(
          get: { draft.tags.joined(separator: ", ") },
          set: {
            draft.tags = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
          }))
      if draft.kind == .countdown {
        EditorNumberField("Duration (seconds)", value: $draft.duration).accessibilityIdentifier(
          "timer-editor-duration")
      }
      recurrenceControls
      Picker(
        "Alert sound",
        selection: Binding(
          get: { draft.alertName ?? "" }, set: { draft.alertName = $0.isEmpty ? nil : $0 })
      ) {
        Text("Default").tag("")
        ForEach(catalog.names, id: \.self) { Text($0).tag($0) }
        if let selected = draft.alertName, !catalog.names.contains(selected) {
          Text("Unavailable: \(selected)").tag(selected)
        }
      }
      Slider(value: $draft.volume, in: 0...1) { Text("Volume") }
      if let message = error ?? draft.validationError() ?? soundError {
        Text(message).foregroundStyle(.red).accessibilityLabel(message)
      }
    }.padding().frame(width: 360)
      .onChange(of: draft) { _ in error = nil }
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Save", action: submit) } }
  }
  private var soundError: String? {
    draft.alertName.map { catalog.names.contains($0) ? nil : "Choose an available alert sound." }
      ?? nil
  }
  @ViewBuilder private var recurrenceControls: some View {
    Picker("Recurrence", selection: $draft.recurrenceMode) {
      Text("None").tag(RecurrenceEditorMode.none)
      Text("After completion").tag(RecurrenceEditorMode.interval)
      Text("Daily").tag(RecurrenceEditorMode.daily)
      Text("Weekdays").tag(RecurrenceEditorMode.weekdays)
      Text("Weekly").tag(RecurrenceEditorMode.weekly)
      Text("Selected weekdays").tag(RecurrenceEditorMode.selectedWeekdays)
    }
    if draft.recurrenceMode == .interval {
      EditorNumberField("Interval (seconds)", value: $draft.interval)
    }
    if draft.recurrenceMode != .none && draft.recurrenceMode != .interval {
      HStack {
        EditorNumberField("Hour", integer: $draft.hour)
        EditorNumberField("Minute", integer: $draft.minute)
      }
    }
    if draft.recurrenceMode == .weekly {
      Picker("Weekday", selection: $draft.weekday) {
        ForEach(1...7, id: \.self) { Text(Calendar.current.weekdaySymbols[$0 - 1]).tag($0) }
      }
    }
    if draft.recurrenceMode == .selectedWeekdays {
      ForEach(1...7, id: \.self) { day in
        Toggle(
          Calendar.current.weekdaySymbols[day - 1],
          isOn: Binding(
            get: { draft.selectedWeekdays.contains(day) },
            set: { selected in
              if selected {
                draft.selectedWeekdays.insert(day)
              } else {
                draft.selectedWeekdays.remove(day)
              }
            }))
      }
    }
  }
  private func submit() {
    Task {
      do {
        let configuration = try draft.configuration(catalog: catalog)
        guard await save(configuration) else {
          error = "Could not save timer."
          return
        }
        dismiss()
      } catch let EditorDraftError.invalid(message) { error = message } catch {
        self.error = "Invalid timer configuration."
      }
    }
  }
}

/// Invalid text stays visible and invalidates the draft instead of silently
/// saving the previous numeric value through a formatter's failed conversion.
private struct EditorNumberField: View {
  let label: String
  @Binding var value: Double
  @State private var text: String
  init(_ label: String, value: Binding<Double>) {
    self.label = label
    _value = value
    _text = State(initialValue: value.wrappedValue.formatted(.number.grouping(.never)))
  }
  init(_ label: String, integer: Binding<Int>) {
    self.init(
      label,
      value: Binding(
        get: { Double(integer.wrappedValue) },
        set: { value in
          integer.wrappedValue =
            value.isFinite && value.rounded() == value && (0...59).contains(value) ? Int(value) : -1
        }))
  }
  var body: some View {
    TextField(
      label,
      text: Binding(
        get: { text },
        set: { input in
          text = input
          let normalized = input.trimmingCharacters(in: .whitespaces).replacingOccurrences(
            of: Locale.current.decimalSeparator ?? ".", with: ".")
          value = Double(normalized) ?? .nan
        })
    ).accessibilityLabel(label)
  }
}
