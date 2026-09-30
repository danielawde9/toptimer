import SwiftUI

struct DataCleanupControls: View {
  @ObservedObject var state: AppState
  @State private var confirming = false
  @State private var clearEverything = false
  var body: some View {
    HStack {
      Button("Delete all timers") {
        clearEverything = false
        confirming = true
      }
      .help("Delete all timers")
      Spacer()
      Button("Clear everything…") {
        clearEverything = true
        confirming = true
      }
      .help("Clear everything")
    }.controlSize(.small).disabled(state.clearingData)
      .alert(clearEverything ? "Clear everything?" : "Delete all timers?", isPresented: $confirming)
    {
      Button("Cancel", role: .cancel) {}
      Button(clearEverything ? "Clear everything" : "Delete all timers", role: .destructive) {
        let all = clearEverything
        state.perform { _ = await state.deleteAllTimers(clearEverything: all) }
      }
    } message: {
      Text(
        clearEverything
          ? "Permanently remove every timer, history entry, deleted item, saved suggestion, and saved sequence. App settings and imported sounds stay."
          : "Permanently remove all timers, including Recently Deleted, and stop the sequence. History and saved suggestions stay."
      )
    }
  }
}
