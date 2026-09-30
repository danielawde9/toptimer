import Foundation
import TopTimerDomain

extension AppState {
  public func startSequence(steps: [SequenceStep], repeats: Bool) async -> Bool {
    guard !clearingData else { return false }
    do {
      let timers = try await sequenceCoordinator.start(
        steps: steps, repeats: repeats, at: now(), alertName: preferences.defaultAlertName,
        alertVolume: preferences.alertVolume)
      sequenceSession = sequenceCoordinator.session
      for timer in timers {
        notificationStatus = try await notifications.scheduleCreatedTimer(timer)
        try sequenceCoordinator.markScheduled(timer.id)
      }
      sequenceError = nil
      await publishActive()
      return true
    } catch {
      sequenceSession = sequenceCoordinator.session
      sequenceError = error.localizedDescription
      await publishActive()
      return false
    }
  }
  func reconcileSequence(at date: Date) async {
    do {
      let timers = try await sequenceCoordinator.reconcile(at: date)
      sequenceSession = sequenceCoordinator.session
      for timer in timers {
        notificationStatus = try await notifications.schedule(timer)
        try sequenceCoordinator.markScheduled(timer.id)
      }
      sequenceError = nil
    } catch { sequenceError = "Could not advance the sequence: \(error.localizedDescription)" }
  }
  public func stopSequence() async -> Bool {
    do {
      if let id = try await sequenceCoordinator.stop(at: now()) { await cancelAfterPersistence(id) }
      sequenceSession = sequenceCoordinator.session
      sequenceError = nil
      await publishActive()
      await refreshHistoryConsumers()
      return true
    } catch {
      sequenceError = error.localizedDescription
      return false
    }
  }
  public func removeSuggestion(_ command: String) async {
    guard !clearingData, let presets else { return }
    do {
      let matches = try await presets.suggestions(query: command, limit: 200)
      for preset in matches where preset.command == command {
        try await presets.softDeletePreset(preset.id, at: now())
      }
      await refreshSuggestions(query: quickEntryText)
    } catch { inlineError = "Could not remove saved suggestion." }
  }
  public func clearSuggestions() async -> Bool {
    guard !clearingData else { return false }
    do {
      try await presets?.removeAllPresets()
      await refreshSuggestions(query: quickEntryText)
      return true
    } catch {
      inlineError = "Could not clear saved suggestions."
      return false
    }
  }
  public func deleteAllTimers(clearEverything: Bool = false) async -> Bool {
    guard !clearingData else { return false }
    clearingData = true
    defer { clearingData = false }
    do {
      if let id = try await sequenceCoordinator.stop(at: now()) { await cancelAfterPersistence(id) }
      if clearEverything { try sequenceCoordinator.clear() }
      sequenceSession = sequenceCoordinator.session
      let ids =
        try await (clearEverything ? repository.clearAllData() : repository.removeAllTimers())
      inlineError = nil
      for id in ids { await cancelAfterPersistence(id) }
      selectedEditorTimer = nil
      quickEntryText = ""
      startupRecovery = .none
      sequenceError = nil
      await publishActive()
      await refreshHistoryConsumers()
      await refreshSuggestions(query: "")
      return true
    } catch {
      inlineError = "Could not clear timer data. Try again."
      return false
    }
  }
}
