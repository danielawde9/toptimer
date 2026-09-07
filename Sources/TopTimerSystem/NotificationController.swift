@preconcurrency import UserNotifications
import Foundation

public enum NotificationAuthorizationStatus: Sendable, Equatable { case notDetermined, authorized, denied, provisional, ephemeral }
public struct NotificationAction: Sendable, Equatable { public let identifier: String; public let title: String; public init(_ identifier: String, _ title: String) { self.identifier = identifier; self.title = title } }
public struct NotificationCategory: Sendable, Equatable { public let identifier: String; public let actions: [NotificationAction]; public init(identifier: String, actions: [NotificationAction]) { self.identifier = identifier; self.actions = actions } }
public struct PendingNotification: Sendable, Equatable { public let identifier: String; public let categoryIdentifier: String; public let body: String; public let createdAt: Date; public init(identifier: String, categoryIdentifier: String, body: String, createdAt: Date) { self.identifier = identifier; self.categoryIdentifier = categoryIdentifier; self.body = body; self.createdAt = createdAt } }
public struct NotificationRequest: Sendable, Equatable { public let identifier: String; public let title: String; public let body: String; public let categoryIdentifier: String; public let fireDate: Date; public init(identifier: String, title: String, body: String, categoryIdentifier: String, fireDate: Date) { self.identifier = identifier; self.title = title; self.body = body; self.categoryIdentifier = categoryIdentifier; self.fireDate = fireDate } }
public protocol NotificationCenterClient: Sendable { func authorizationStatus() async -> NotificationAuthorizationStatus; func requestAuthorization() async throws -> Bool; func setCategories(_ categories: [NotificationCategory]) async; func pendingRequests(limit: Int) async -> [PendingNotification]; func add(_ request: NotificationRequest) async throws; func removePendingRequests(identifiers: [String]) async }
public enum NotificationScheduleStatus: Sendable, Equatable { case scheduled, notAuthorized(NotificationAuthorizationStatus), authorizationDenied }
public enum NotificationControllerError: Error, Sendable, LocalizedError { case pendingRequestLimitExceeded
    public var errorDescription: String? { "TopTimer could not inspect pending notifications safely." }
}
public enum TimerNotificationAction: Sendable, Equatable { case stop(UUID), repeatTimer(UUID, duration: TimeInterval), snooze(UUID, seconds: TimeInterval), invalidPayload }

public struct NotificationController: Sendable {
    public static let categoryIdentifier = "TOPTIMER_TIMER"
    public static let maxPendingRequests = 64
    public static let maximumBodyCharacters = 120
    public static let maximumPendingInspection = 4_096
    private let center: any NotificationCenterClient
    public init(center: any NotificationCenterClient = UNNotificationCenterAdapter()) { self.center = center }
    public func schedule(timerID: UUID, title: String, details: String, fireDate: Date, requestAuthorizationForFirstSuccessfulCreation: Bool = false) async throws -> NotificationScheduleStatus {
        var status = await center.authorizationStatus()
        if status == .notDetermined && requestAuthorizationForFirstSuccessfulCreation {
            guard try await center.requestAuthorization() else { return .authorizationDenied }
            status = await center.authorizationStatus()
        }
        guard status == .authorized || status == .provisional || status == .ephemeral else { return .notAuthorized(status) }
        await center.setCategories([Self.category])
        let pending = await center.pendingRequests(limit: Self.maximumPendingInspection + 1)
        guard pending.count <= Self.maximumPendingInspection else { throw NotificationControllerError.pendingRequestLimitExceeded }
        let owned = pending.filter(Self.isOwned).sorted { lhs, rhs in
            lhs.createdAt == rhs.createdAt ? lhs.identifier < rhs.identifier : lhs.createdAt < rhs.createdAt
        }
        if owned.count >= Self.maxPendingRequests, let oldest = owned.first { await center.removePendingRequests(identifiers: [oldest.identifier]) }
        try await center.add(NotificationRequest(identifier: Self.identifier(for: timerID), title: title, body: Self.truncated(details), categoryIdentifier: Self.categoryIdentifier, fireDate: fireDate))
        return .scheduled
    }
    public func cancel(timerID: UUID) async throws { await center.removePendingRequests(identifiers: [Self.identifier(for: timerID)]) }
    public func route(actionIdentifier: String, requestIdentifier: String, savedDuration: TimeInterval?, snoozePreference: TimeInterval) -> TimerNotificationAction {
        guard let id = Self.timerID(from: requestIdentifier) else { return .invalidPayload }
        switch actionIdentifier {
        case "STOP": return .stop(id)
        case "REPEAT": guard let savedDuration, savedDuration > 0 else { return .invalidPayload }; return .repeatTimer(id, duration: savedDuration)
        case "SNOOZE": return .snooze(id, seconds: min(86_400, max(60, snoozePreference)))
        default: return .invalidPayload
        }
    }
    public static func identifier(for id: UUID) -> String { "timer-\(id.uuidString)" }
    private static var category: NotificationCategory { .init(identifier: categoryIdentifier, actions: [.init("STOP", "Stop"), .init("REPEAT", "Repeat"), .init("SNOOZE", "Snooze")]) }
    private static func truncated(_ value: String) -> String { String(value.prefix(maximumBodyCharacters)) }
    private static func isOwned(_ request: PendingNotification) -> Bool { request.categoryIdentifier == categoryIdentifier || timerID(from: request.identifier) != nil }
    private static func timerID(from identifier: String) -> UUID? { guard identifier.hasPrefix("timer-") else { return nil }; return UUID(uuidString: String(identifier.dropFirst(6))) }
}

public actor UNNotificationCenterAdapter: NotificationCenterClient {
    private let center: UNUserNotificationCenter
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
    public func requestAuthorization() async throws -> Bool { try await center.requestAuthorization(options: [.alert, .sound]) }
    public func setCategories(_ categories: [NotificationCategory]) async { center.setNotificationCategories(Set(categories.map { UNNotificationCategory(identifier: $0.identifier, actions: $0.actions.map { UNNotificationAction(identifier: $0.identifier, title: $0.title) }, intentIdentifiers: []) })) }
    public func pendingRequests(limit: Int) async -> [PendingNotification] {
        let requests = await center.pendingNotificationRequests()
        return requests.prefix(limit).map { request in
            .init(identifier: request.identifier, categoryIdentifier: request.content.categoryIdentifier, body: request.content.body, createdAt: Self.scheduledDate(for: request.trigger))
        }
    }
    private static func scheduledDate(for trigger: UNNotificationTrigger?) -> Date {
        if let trigger = trigger as? UNTimeIntervalNotificationTrigger { return trigger.nextTriggerDate() ?? .distantFuture }
        if let trigger = trigger as? UNCalendarNotificationTrigger { return trigger.nextTriggerDate() ?? .distantFuture }
        return .distantFuture
    }
    public func add(_ request: NotificationRequest) async throws { let content = UNMutableNotificationContent(); content.title = request.title; content.body = request.body; content.categoryIdentifier = request.categoryIdentifier; content.sound = .default; let interval = max(1, request.fireDate.timeIntervalSinceNow); try await center.add(UNNotificationRequest(identifier: request.identifier, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))) }
    public func removePendingRequests(identifiers: [String]) async { center.removePendingNotificationRequests(withIdentifiers: identifiers) }
}
