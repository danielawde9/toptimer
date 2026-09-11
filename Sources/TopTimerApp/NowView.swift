import SwiftUI
import TopTimerDomain

public struct NowView: View {
  @ObservedObject private var state: AppState
  private let start: (String) -> Void
  private let quit: () -> Void

  public init(state: AppState, start: @escaping (String) -> Void = { _ in }, quit: @escaping () -> Void = {}) {
    self.state = state; self.start = start; self.quit = quit
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack { Text("TopTimer").font(.title2.bold()); Spacer(); Button("Quit", action: quit) }
      if state.activeTimers.isEmpty {
        Text("Start a timer").font(.headline)
        HStack { TextField("25m focus", text: $state.quickEntryText); Button("Start") { start(state.quickEntryText) } }
        Text("Try: “10m tea” · “1h meeting” · “stopwatch reading”").foregroundStyle(.secondary)
      } else {
        Text("NOW").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        ForEach(state.activeTimers.prefix(3), id: \.id) { timer in
          VStack(alignment: .leading) {
            Text(timer.title.isEmpty ? "Untitled timer" : timer.title).font(.headline)
            Text(timer.state == .paused ? "Paused" : "Running")
            HStack { Button(timer.state == .paused ? "Resume" : "Pause") { state.perform { _ = await (timer.state == .paused ? state.start(timer.id) : state.pause(timer.id)) } }; Button("Stop") {} }
          }
        }
      }
      Spacer()
    }.padding(24).frame(minWidth: 460, minHeight: 360)
  }
}
