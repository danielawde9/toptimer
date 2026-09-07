import XCTest
@testable import TopTimerSystem

@MainActor
final class SleepAssertionControllerTests: XCTestCase {
    func testOneAssertionIsOwnedUntilNoTimerRuns() throws {
        let client = PowerAssertionSpy()
        let controller = SleepAssertionController(client: client)
        try controller.setRunningTimerCount(2, enabled: true)
        try controller.setRunningTimerCount(1, enabled: true)
        try controller.setRunningTimerCount(0, enabled: true)

        XCTAssertEqual(client.created, 1)
        XCTAssertEqual(client.released, [1])
    }

    func testCreateFailureLeavesNoOwnedAssertion() {
        let client = PowerAssertionSpy(createError: .creationFailed(-1))
        let controller = SleepAssertionController(client: client)
        XCTAssertThrowsError(try controller.setRunningTimerCount(1, enabled: true))
        XCTAssertNil(controller.assertionID)
    }

    func testDisableAndRepeatedReleaseAreHarmless() throws {
        let client = PowerAssertionSpy()
        let controller = SleepAssertionController(client: client)
        try controller.setRunningTimerCount(1, enabled: true)
        try controller.setRunningTimerCount(1, enabled: false)
        try controller.setRunningTimerCount(0, enabled: false)
        XCTAssertEqual(client.released, [1])
    }

    func testNegativeCountIsRejected() {
        XCTAssertThrowsError(try SleepAssertionController(client: PowerAssertionSpy()).setRunningTimerCount(-1, enabled: true))
    }

    func testReleaseFailureIsSurfacedAndKeepsOwnershipForRetry() throws {
        let client = PowerAssertionSpy(releaseError: .releaseFailed(-2))
        let controller = SleepAssertionController(client: client)
        try controller.setRunningTimerCount(1, enabled: true)
        XCTAssertThrowsError(try controller.setRunningTimerCount(0, enabled: true))
        XCTAssertEqual(controller.assertionID, 1)
        client.releaseError = nil
        try controller.releaseIfNeeded()
    }

    func testDeinitReleasesOwnedAssertion() throws {
        let client = PowerAssertionSpy()
        weak var weakController: SleepAssertionController?
        do {
            var controller: SleepAssertionController? = SleepAssertionController(client: client)
            weakController = controller
            try controller?.setRunningTimerCount(1, enabled: true)
            controller = nil
        }
        XCTAssertNil(weakController)
        XCTAssertEqual(client.released, [1])
    }
}

@MainActor
private final class PowerAssertionSpy: PowerAssertionClient {
    let createError: SleepAssertionError?
    var releaseError: SleepAssertionError?
    private(set) var created = 0
    private(set) var released: [SleepAssertionID] = []

    init(createError: SleepAssertionError? = nil, releaseError: SleepAssertionError? = nil) { self.createError = createError; self.releaseError = releaseError }
    func createPreventIdleSleepAssertion() throws -> SleepAssertionID {
        if let createError { throw createError }
        created += 1
        return SleepAssertionID(created)
    }
    func releaseAssertion(_ id: SleepAssertionID) throws { released.append(id); if let releaseError { throw releaseError } }
}
