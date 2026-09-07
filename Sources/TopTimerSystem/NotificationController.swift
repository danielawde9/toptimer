import Foundation
import TopTimerDomain
@preconcurrency import UserNotifications

public enum NotificationAuthorizationStatus: Sendable, Equatable {
  case notDetermined, authorized, denied, provisional, ephemeral
}
public struct NotificationAction: Sendable, Equatable {
  public let identifier: String
  public let title: String
  public init(_ identifier: String, _ title: String) {
    self.identifier = identifier
    self.title = title
  }
}
public struct NotificationCategory: Sendable, Equatable {
  public let identifier: String
  public let actions: [NotificationAction]
  public init(identifier: String, actions: [NotificationAction]) {
    self.identifier = identifier
    self.actions = actions
  }
}
public struct PendingNotification: Sendable, Equatable {
  public let identifier: String
  public let categoryIdentifier: String
  public let body: String
  public let createdAt: Date
  public init(identifier: String, categoryIdentifier: String, body: String, createdAt: Date) {
    self.identifier = identifier
    self.categoryIdentifier = categoryIdentifier
    self.body = body
    self.createdAt = createdAt
  }
}
public struct NotificationRequest: Sendable, Equatable {
  public let identifier: String
  public let title: String
  public let body: String
  public let categoryIdentifier: String
  public let fireDate: Date
  public let soundName: String?
  public init(
    identifier: String, title: String, body: String, categoryIdentifier: String, fireDate: Date,
    soundName: String? = nil
  ) {
    self.identifier = identifier
    self.title = title
    self.body = body
    self.categoryIdentifier = categoryIdentifier
    self.fireDate = fireDate
    self.soundName = soundName
  }
}
public protocol NotificationCenterClient: Sendable {
  func authorizationStatus() async -> NotificationAuthorizationStatus
  func requestAuthorization() async throws -> Bool
  func prepareSound(named: String?) async throws -> String?
  func setCategories(_ categories: [NotificationCategory]) async
  func pendingRequests(limit: Int) async -> [PendingNotification]
  func add(_ request: NotificationRequest) async throws
  func removePendingRequests(identifiers: [String]) async
}
extension NotificationCenterClient {
  public func prepareSound(named name: String?) async throws -> String? { name }
}
public enum NotificationScheduleStatus: Sendable, Equatable {
  case scheduled
  case notAuthorized(NotificationAuthorizationStatus)
  case authorizationDenied
}
public enum NotificationControllerError: Error, Sendable, LocalizedError {
  case pendingRequestLimitExceeded
  public var errorDescription: String? {
    "TopTimer could not inspect pending notifications safely."
  }
}
public enum TimerNotificationAction: Sendable, Equatable {
  case stop(UUID)
  case repeatTimer(UUID, duration: TimeInterval)
  case snooze(UUID, seconds: TimeInterval)
  case invalidPayload
}

public struct NotificationController: Sendable {
  public static let categoryIdentifier = "TOPTIMER_TIMER"
  public static let maxPendingRequests = 64
  public static let maximumBodyCharacters = 120
  public static let maximumPendingInspection = 4_096
  private let center: any NotificationCenterClient
  public init(center: any NotificationCenterClient = UNNotificationCenterAdapter()) {
    self.center = center
  }
  public func validateSound(name: String?) async throws {
    _ = try await center.prepareSound(named: name)
  }
  public func schedule(
    timerID: UUID, title: String, details: String, fireDate: Date,
    requestAuthorizationForFirstSuccessfulCreation: Bool = false, alertName: String? = nil
  ) async throws -> NotificationScheduleStatus {
    var status = await center.authorizationStatus()
    if status == .notDetermined && requestAuthorizationForFirstSuccessfulCreation {
      guard try await center.requestAuthorization() else { return .authorizationDenied }
      status = await center.authorizationStatus()
    }
    guard status == .authorized || status == .provisional || status == .ephemeral else {
      return .notAuthorized(status)
    }
    let preparedSound = try await center.prepareSound(named: alertName)
    await center.setCategories([Self.category])
    let pending = await center.pendingRequests(limit: Self.maximumPendingInspection + 1)
    guard pending.count <= Self.maximumPendingInspection else {
      throw NotificationControllerError.pendingRequestLimitExceeded
    }
    let owned = pending.filter(Self.isOwned).sorted { lhs, rhs in
      lhs.createdAt == rhs.createdAt
        ? lhs.identifier < rhs.identifier : lhs.createdAt < rhs.createdAt
    }
    let identifier = Self.identifier(for: timerID)
    let existing = owned.filter { $0.identifier == identifier }
    let otherOwned = owned.filter { $0.identifier != identifier }
    let removalCount = max(0, otherOwned.count + 1 - Self.maxPendingRequests)
    let removals = existing.map(\.identifier) + otherOwned.prefix(removalCount).map(\.identifier)
    if !removals.isEmpty { await center.removePendingRequests(identifiers: removals) }
    try await center.add(
      NotificationRequest(
        identifier: identifier, title: title, body: Self.truncated(details),
        categoryIdentifier: Self.categoryIdentifier, fireDate: fireDate, soundName: preparedSound))
    return .scheduled
  }
  public func cancel(timerID: UUID) async throws {
    await center.removePendingRequests(identifiers: [Self.identifier(for: timerID)])
  }
  public func route(
    actionIdentifier: String, categoryIdentifier: String, requestIdentifier: String,
    savedDuration: TimeInterval?, snoozePreference: TimeInterval
  ) -> TimerNotificationAction {
    Self.routeAction(
      actionIdentifier: actionIdentifier, categoryIdentifier: categoryIdentifier,
      requestIdentifier: requestIdentifier, savedDuration: savedDuration,
      snoozePreference: snoozePreference)
  }
  public static func routeAction(
    actionIdentifier: String, categoryIdentifier: String, requestIdentifier: String,
    savedDuration: TimeInterval?, snoozePreference: TimeInterval
  ) -> TimerNotificationAction {
    guard categoryIdentifier == Self.categoryIdentifier,
      let id = Self.timerID(from: requestIdentifier)
    else { return .invalidPayload }
    switch actionIdentifier {
    case "STOP": return .stop(id)
    case "REPEAT":
      guard let savedDuration, savedDuration.isFinite, savedDuration > 0,
        savedDuration <= TimerLimits.maximumDuration
      else { return .invalidPayload }
      return .repeatTimer(id, duration: savedDuration)
    case "SNOOZE": return .snooze(id, seconds: min(86_400, max(60, snoozePreference)))
    default: return .invalidPayload
    }
  }
  public static func identifier(for id: UUID) -> String { "timer-\(id.uuidString)" }
  private static var category: NotificationCategory {
    .init(
      identifier: categoryIdentifier,
      actions: [.init("STOP", "Stop"), .init("REPEAT", "Repeat"), .init("SNOOZE", "Snooze")])
  }
  private static func truncated(_ value: String) -> String {
    String(value.prefix(maximumBodyCharacters))
  }
  private static func isOwned(_ request: PendingNotification) -> Bool {
    request.categoryIdentifier == categoryIdentifier || timerID(from: request.identifier) != nil
  }
  private static func timerID(from identifier: String) -> UUID? {
    guard identifier.hasPrefix("timer-") else { return nil }
    return UUID(uuidString: String(identifier.dropFirst(6)))
  }
}

public actor UNNotificationCenterAdapter: NotificationCenterClient {
  private let center: UNUserNotificationCenter
  private let sounds = LocalNotificationSoundPreparer()
  public func prepareSound(named name: String?) async throws -> String? {
    try await sounds.prepare(name: name)
  }
  public init(center: UNUserNotificationCenter = .current()) { self.center = center }
  public func authorizationStatus() async -> NotificationAuthorizationStatus {
    let settings = await center.notificationSettings()
    switch settings.authorizationStatus {
    case .notDetermined: return .notDetermined
    case .authorized: return .authorized
    case .denied: return .denied
    case .provisional: return .provisional
    case .ephemeral: return .ephemeral
    @unknown default: return .denied
    }
  }
  public func requestAuthorization() async throws -> Bool {
    try await center.requestAuthorization(options: [.alert, .sound])
  }
  public func setCategories(_ categories: [NotificationCategory]) async {
    center.setNotificationCategories(
      Set(
        categories.map {
          UNNotificationCategory(
            identifier: $0.identifier,
            actions: $0.actions.map {
              UNNotificationAction(identifier: $0.identifier, title: $0.title)
            }, intentIdentifiers: [])
        }))
  }
  public func pendingRequests(limit: Int) async -> [PendingNotification] {
    let requests = await center.pendingNotificationRequests()
    return requests.prefix(limit).map { request in
      .init(
        identifier: request.identifier, categoryIdentifier: request.content.categoryIdentifier,
        body: request.content.body, createdAt: Self.scheduledDate(for: request.trigger))
    }
  }
  private static func scheduledDate(for trigger: UNNotificationTrigger?) -> Date {
    if let trigger = trigger as? UNTimeIntervalNotificationTrigger {
      return trigger.nextTriggerDate() ?? .distantFuture
    }
    if let trigger = trigger as? UNCalendarNotificationTrigger {
      return trigger.nextTriggerDate() ?? .distantFuture
    }
    return .distantFuture
  }
  public static func content(for request: NotificationRequest, preparedSoundName: String?)
    -> UNMutableNotificationContent
  {
    let content = UNMutableNotificationContent()
    content.title = request.title
    content.body = request.body
    content.categoryIdentifier = request.categoryIdentifier
    if request.identifier.hasPrefix("timer-"),
      let id = UUID(uuidString: String(request.identifier.dropFirst(6)))
    {
      content.userInfo = ["version": 1, "timerID": id.uuidString]
    }
    content.sound =
      preparedSoundName.map { UNNotificationSound(named: UNNotificationSoundName($0)) } ?? .default
    return content
  }
  public func add(_ request: NotificationRequest) async throws {
    let content = Self.content(for: request, preparedSoundName: request.soundName)
    let interval = max(1, request.fireDate.timeIntervalSinceNow)
    try await center.add(
      UNNotificationRequest(
        identifier: request.identifier, content: content,
        trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)))
  }
  public func removePendingRequests(identifiers: [String]) async {
    center.removePendingNotificationRequests(withIdentifiers: identifiers)
  }
}
