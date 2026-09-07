import XCTest
@testable import TopTimerSystem

final class NotificationControllerTests: XCTestCase {
    func testAuthorizedScheduleUsesStableIDTruncatedUnicodeBodyAndCategory() async throws {
        let center = NotificationCenterSpy(status: .authorized)
        let controller = NotificationController(center: center)
        let id = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        let result = try await controller.schedule(timerID: id, title: "Focus", details: String(repeating: "👩🏽‍💻", count: 100), fireDate: .now)
        XCTAssertEqual(result, .scheduled)
        let request = await center.requests.single
        XCTAssertEqual(request?.identifier, "timer-\(id.uuidString)")
        XCTAssertEqual(request?.categoryIdentifier, NotificationController.categoryIdentifier)
        XCTAssertLessThanOrEqual(request?.body.unicodeScalars.count ?? .max, 120)
        let categoryCount = await center.categories.count
        XCTAssertEqual(categoryCount, 1)
    }

    func testDeniedDoesNotSchedule() async throws {
        let center = NotificationCenterSpy(status: .denied)
        let result = try await NotificationController(center: center).schedule(timerID: UUID(), title: "x", details: "y", fireDate: .now)
        XCTAssertEqual(result, .notAuthorized(.denied))
        let requestsAreEmpty = await center.requests.isEmpty
        XCTAssertTrue(requestsAreEmpty)
    }

    func testFirstCreationRequestsAuthorizationAndSurfacesDenial() async throws {
        let center = NotificationCenterSpy(status: .notDetermined, authorizationResult: false)
        let result = try await NotificationController(center: center).schedule(timerID: UUID(), title: "x", details: "y", fireDate: .now, requestAuthorizationForFirstSuccessfulCreation: true)
        XCTAssertEqual(result, .authorizationDenied)
        let authorizationCalls = await center.authorizationCalls
        XCTAssertEqual(authorizationCalls, 1)
    }

    func testCapRemovesOldestTopTimerRequestOnly() async throws {
        let center = NotificationCenterSpy(status: .authorized, pending: (0..<64).map { .init(identifier: "timer-\($0)", categoryIdentifier: NotificationController.categoryIdentifier, body: "", createdAt: Date(timeIntervalSince1970: TimeInterval($0))) } + [.init(identifier: "other", categoryIdentifier: "other", body: "", createdAt: .distantPast)])
        let controller = NotificationController(center: center)
        _ = try await controller.schedule(timerID: UUID(), title: "x", details: "", fireDate: .now)
        let removed = await center.removed
        XCTAssertEqual(removed, ["timer-0"])
    }

    func testCancelAndActionsValidatePayload() async throws {
        let center = NotificationCenterSpy(status: .authorized)
        let controller = NotificationController(center: center)
        let id = UUID()
        try await controller.cancel(timerID: id)
        let removed = await center.removed
        XCTAssertEqual(removed, ["timer-\(id.uuidString)"])
        XCTAssertEqual(controller.route(actionIdentifier: "STOP", requestIdentifier: "timer-\(id.uuidString)", savedDuration: 90, snoozePreference: 2), .stop(id))
        XCTAssertEqual(controller.route(actionIdentifier: "REPEAT", requestIdentifier: "timer-\(id.uuidString)", savedDuration: 90, snoozePreference: 2), .repeatTimer(id, duration: 90))
        XCTAssertEqual(controller.route(actionIdentifier: "SNOOZE", requestIdentifier: "timer-\(id.uuidString)", savedDuration: 90, snoozePreference: 2), .snooze(id, seconds: 60))
        XCTAssertEqual(controller.route(actionIdentifier: "STOP", requestIdentifier: "bad", savedDuration: 90, snoozePreference: 2), .invalidPayload)
    }
}

actor NotificationCenterSpy: NotificationCenterClient {
    var status: NotificationAuthorizationStatus
    let authorizationResult: Bool
    var requests: [PendingNotification]
    var removed: [String] = []
    var categories: [NotificationCategory] = []
    var authorizationCalls = 0
    init(status: NotificationAuthorizationStatus, authorizationResult: Bool = true, pending: [PendingNotification] = []) { self.status = status; self.authorizationResult = authorizationResult; self.requests = pending }
    func authorizationStatus() async -> NotificationAuthorizationStatus { status }
    func requestAuthorization() async throws -> Bool { authorizationCalls += 1; return authorizationResult }
    func setCategories(_ categories: [NotificationCategory]) async { self.categories = categories }
    func pendingRequests(limit: Int) async -> [PendingNotification] { Array(requests.prefix(limit)) }
    func add(_ request: NotificationRequest) async throws { requests.append(.init(identifier: request.identifier, categoryIdentifier: request.categoryIdentifier, body: request.body, createdAt: .now)) }
    func removePendingRequests(identifiers: [String]) async { removed.append(contentsOf: identifiers); requests.removeAll { identifiers.contains($0.identifier) } }
}

private extension Array { var single: Element? { count == 1 ? first : nil } }
