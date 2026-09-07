import XCTest
@testable import TopTimerSystem

@MainActor
final class LoginItemControllerTests: XCTestCase {
    func testStatusIsExposedWithoutRegistration() {
        let service = LoginItemServiceSpy(status: .requiresApproval)
        XCTAssertEqual(LoginItemController(service: service).status, .requiresApproval)
        XCTAssertEqual(service.operations, [])
    }

    func testRegistrationAndUnregistrationErrorsAreMapped() {
        let service = LoginItemServiceSpy(status: .notRegistered, registerError: .registerFailed)
        let controller = LoginItemController(service: service)
        XCTAssertThrowsError(try controller.setEnabled(true)) { error in
            XCTAssertEqual(error as? LoginItemControllerError, .registrationFailed)
        }
        XCTAssertEqual(service.operations, ["register"])
    }

    func testAllKnownStatusesAndUnregistrationErrorAreExposed() {
        for status in [LoginItemStatus.enabled, .notRegistered, .requiresApproval, .notFound, .unknown] {
            XCTAssertEqual(LoginItemController(service: LoginItemServiceSpy(status: status)).status, status)
        }
        let service = LoginItemServiceSpy(status: .enabled, unregisterError: .unregisterFailed)
        XCTAssertThrowsError(try LoginItemController(service: service).setEnabled(false)) { error in
            XCTAssertEqual(error as? LoginItemControllerError, .unregistrationFailed)
        }
    }
}

@MainActor
private final class LoginItemServiceSpy: LoginItemService {
    var status: LoginItemStatus
    let registerError: LoginItemServiceError?
    let unregisterError: LoginItemServiceError?
    private(set) var operations: [String] = []
    init(status: LoginItemStatus, registerError: LoginItemServiceError? = nil, unregisterError: LoginItemServiceError? = nil) { self.status = status; self.registerError = registerError; self.unregisterError = unregisterError }
    func register() throws { operations.append("register"); if let registerError { throw registerError } }
    func unregister() throws { operations.append("unregister"); if let unregisterError { throw unregisterError } }
}
