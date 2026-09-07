import XCTest
@testable import TopTimerApp

final class LifecycleCoordinatorTests: XCTestCase {
    func testStartFailureCanRetryWithoutDuplicatingResources() {
        var coordinator = LifecycleCoordinator()
        XCTAssertEqual(coordinator.startResult(.failure), [.showFailure])
        XCTAssertEqual(coordinator.startResult(.success), [.createResources, .hideFailure])
        XCTAssertEqual(coordinator.startResult(.success), [])
    }

    func testTerminateSuccessCleansResourcesAndRepliesOnce() {
        var coordinator = LifecycleCoordinator()
        _ = coordinator.startResult(.success)
        XCTAssertEqual(coordinator.requestTermination(), [.beginClose, .stopResources])
        XCTAssertEqual(coordinator.closeResult(.success), [.replyToTermination(true)])
    }

    func testTerminateFailureStaysPendingUntilAnExplicitQuit() {
        var coordinator = LifecycleCoordinator()
        _ = coordinator.startResult(.success)
        XCTAssertEqual(coordinator.requestTermination(), [.beginClose, .stopResources])
        XCTAssertEqual(coordinator.requestTermination(), [])
        XCTAssertEqual(coordinator.closeResult(.failure), [.reportCloseFailure])
        XCTAssertEqual(coordinator.requestTermination(), [])
        XCTAssertEqual(coordinator.quitAfterCloseFailure(), [.replyToTermination(true)])
    }
    func testRetryAfterCloseFailureRepliesOnlyAfterSuccess() {
        var coordinator = LifecycleCoordinator(); _ = coordinator.startResult(.success); _ = coordinator.requestTermination()
        XCTAssertEqual(coordinator.closeResult(.failure), [.reportCloseFailure])
        XCTAssertEqual(coordinator.closeResult(.success), [.replyToTermination(true)])
    }
}
