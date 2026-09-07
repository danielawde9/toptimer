import Foundation
import TopTimerSystem
@preconcurrency import UserNotifications

@MainActor protocol NotificationDelegateRegistering: AnyObject {
  var delegate: (any UNUserNotificationCenterDelegate)? { get set }
}
extension UNUserNotificationCenter: NotificationDelegateRegistering {}

/// The center holds its delegate weakly; the application owns this adapter until shutdown.
@MainActor final class TimerNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
  private weak var state: AppState?
  init(state: AppState) { self.state = state }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping @Sendable () -> Void
  ) {
    DispatchQueue.main.async { [weak self] in
      self?.receive(
        request: response.notification.request, actionIdentifier: response.actionIdentifier)
      completionHandler()
    }
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler:
      @escaping @Sendable (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler(Self.ownedTimerID(notification.request) == nil ? [] : [.banner, .list])
  }

  func receive(request: UNNotificationRequest, actionIdentifier: String) {
    guard let id = Self.ownedTimerID(request),
      ["STOP", "REPEAT", "SNOOZE"].contains(actionIdentifier),
      let state
    else { return }
    state.perform {
      await state.handleNotificationResponse(timerID: id, actionIdentifier: actionIdentifier)
    }
  }

  nonisolated static func ownedTimerID(_ request: UNNotificationRequest) -> UUID? {
    guard request.content.categoryIdentifier == NotificationController.categoryIdentifier,
      request.content.userInfo["version"] as? Int == 1,
      let value = request.content.userInfo["timerID"] as? String,
      let id = UUID(uuidString: value),
      request.identifier == NotificationController.identifier(for: id)
    else { return nil }
    return id
  }
}
