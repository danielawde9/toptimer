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

    func testTerminateFailureIsDeterministicAndReentrantRequestsAreIgnored() {
        var coordinator = LifecycleCoordinator()
        _ = coordinator.startResult(.success)
        XCTAssertEqual(coordinator.requestTermination(), [.beginClose, .stopResources])
        XCTAssertEqual(coordinator.requestTermination(), [])
        XCTAssertEqual(coordinator.closeResult(.failure), [.reportCloseFailure, .replyToTermination(true)])
        XCTAssertEqual(coordinator.closeResult(.success), [])
    }
}
