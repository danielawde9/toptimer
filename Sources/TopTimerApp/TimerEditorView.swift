import SwiftUI
import TopTimerDomain

public struct EditorDraft: Equatable, Sendable {
    public var title = ""; public var details = ""; public var tags: [String] = []; public var duration: TimeInterval = 300; public var volume = 1.0
    public init() {}
    public init(timer: TimerItem) { title = timer.title; details = timer.details; tags = timer.tags; duration = timer.duration ?? 300; volume = timer.alertVolume }
    public func validationError() -> String? {
        if title.count > TimerLimits.title { return "Title must be 80 characters or fewer." }
        if details.count > TimerLimits.details { return "Details must be 500 characters or fewer." }
        if tags.count > TimerLimits.tags { return "Use at most 12 tags." }
        if tags.contains(where: { $0.count > TimerLimits.tag }) { return "Tags must be 32 characters or fewer." }
        if !duration.isFinite || duration <= 0 || duration > TimerLimits.maximumDuration { return "Duration must be between 1 second and 1 year." }
        if !(0...1).contains(volume) { return "Volume must be between 0 and 1." }; return nil
    }
}

public struct TimerEditorView: View {
    @Binding var draft: EditorDraft; let save: () -> Void; @Environment(\.dismiss) private var dismiss
    public init(draft: Binding<EditorDraft>, save: @escaping () -> Void) { _draft = draft; self.save = save }
    public var body: some View { Form { TextField("Title", text: $draft.title).accessibilityIdentifier("timer-editor-title"); TextField("Details", text: $draft.details, axis: .vertical); TextField("Tags", text: Binding(get: { draft.tags.joined(separator: ", ") }, set: { draft.tags = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } })); Stepper("Duration: \(Int(draft.duration)) seconds", value: $draft.duration, in: 1...TimerLimits.maximumDuration); Slider(value: $draft.volume, in: 0...1) { Text("Volume") }; if let error = draft.validationError() { Text(error).foregroundStyle(.red) } }.padding().frame(width: 340).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { save(); dismiss() }.disabled(draft.validationError() != nil) } } }
}
