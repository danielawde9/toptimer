import XCTest
@testable import TopTimerSystem

@MainActor
final class GlobalHotKeyControllerTests: XCTestCase {
    func testOnlyTwoSlotsAndDuplicateCombinationIsRejected() throws {
        let registrar = HotKeyRegistrarSpy()
        let controller = GlobalHotKeyController(registrar: registrar)
        let shortcut = try Shortcut(keyCode: 1, modifiers: 256)

        try controller.register(shortcut, for: .quickEntry)
        XCTAssertThrowsError(try controller.register(shortcut, for: .pauseResumePriority))
        XCTAssertEqual(controller.shortcut(for: .quickEntry), shortcut)
        XCTAssertNil(controller.shortcut(for: .pauseResumePriority))
    }

    func testReplacementRegistersBeforeUnregisteringOldShortcut() throws {
        let registrar = HotKeyRegistrarSpy()
        let controller = GlobalHotKeyController(registrar: registrar)
        try controller.register(try Shortcut(keyCode: 1, modifiers: 256), for: .quickEntry)
        try controller.register(try Shortcut(keyCode: 2, modifiers: 256), for: .quickEntry)

        XCTAssertEqual(registrar.operations, ["register:1", "register:2", "unregister:1"])
        XCTAssertEqual(controller.shortcut(for: .quickEntry)?.keyCode, 2)
    }

    func testRegisteringTheExistingShortcutIsIdempotent() throws {
        let registrar = HotKeyRegistrarSpy()
        let controller = GlobalHotKeyController(registrar: registrar)
        let shortcut = try Shortcut(keyCode: 1, modifiers: 256)

        try controller.register(shortcut, for: .quickEntry)
        try controller.register(shortcut, for: .quickEntry)

        XCTAssertEqual(registrar.operations, ["register:1"])
        XCTAssertEqual(controller.shortcut(for: .quickEntry), shortcut)
    }

    func testFailedReplacementPreservesPreviousRegistration() throws {
        let registrar = HotKeyRegistrarSpy(rejectedKeyCode: 2)
        let controller = GlobalHotKeyController(registrar: registrar)
        try controller.register(try Shortcut(keyCode: 1, modifiers: 256), for: .quickEntry)

        XCTAssertThrowsError(try controller.register(try Shortcut(keyCode: 2, modifiers: 256), for: .quickEntry))
        XCTAssertEqual(registrar.operations, ["register:1", "register:2"])
        XCTAssertEqual(controller.shortcut(for: .quickEntry)?.keyCode, 1)
    }

    func testOldUnregistrationFailureRollsBackReplacementAndPreservesState() throws {
        let registrar = HotKeyRegistrarSpy(rejectedUnregistrationToken: 1)
        let controller = GlobalHotKeyController(registrar: registrar)
        try controller.register(try Shortcut(keyCode: 1, modifiers: 256), for: .quickEntry)

        XCTAssertThrowsError(try controller.register(try Shortcut(keyCode: 2, modifiers: 256), for: .quickEntry))
        XCTAssertEqual(registrar.operations, ["register:1", "register:2", "unregister:1", "unregister:2"])
        XCTAssertEqual(controller.shortcut(for: .quickEntry)?.keyCode, 1)
        registrar.failingUnregistrationTokens = []
        try controller.shutdown()
    }

    func testShutdownUnregistersOwnedHotKeys() throws {
        let registrar = HotKeyRegistrarSpy()
        let controller = GlobalHotKeyController(registrar: registrar)
        try controller.register(try Shortcut(keyCode: 1, modifiers: 256), for: .quickEntry)
        try controller.register(try Shortcut(keyCode: 2, modifiers: 256), for: .pauseResumePriority)

        try controller.shutdown()
        XCTAssertEqual(registrar.operations, ["register:1", "register:2", "unregister:1", "unregister:2"])
    }

    func testShutdownRetainsFailedRegistrationRetriesItAndAttemptsOtherSlot() throws {
        let registrar = HotKeyRegistrarSpy(failingUnregistrationTokens: [1])
        let controller = GlobalHotKeyController(registrar: registrar)
        let quick = try Shortcut(keyCode: 1, modifiers: 256)
        try controller.register(quick, for: .quickEntry)
        try controller.register(try Shortcut(keyCode: 2, modifiers: 256), for: .pauseResumePriority)

        XCTAssertThrowsError(try controller.shutdown()) { error in
            XCTAssertEqual(error as? GlobalHotKeyControllerError, .shutdownFailed([.quickEntry]))
        }
        XCTAssertEqual(registrar.operations, ["register:1", "register:2", "unregister:1", "unregister:2"])
        XCTAssertEqual(controller.shortcut(for: .quickEntry), quick)
        XCTAssertNil(controller.shortcut(for: .pauseResumePriority))

        registrar.failingUnregistrationTokens = []
        try controller.shutdown()
        XCTAssertEqual(registrar.operations.last, "unregister:1")
        XCTAssertNil(controller.shortcut(for: .quickEntry))
    }

    func testEventDecoderRoutesOnlyTopTimerCommandIDsAndCallbacksRunOnMainActor() {
        XCTAssertEqual(HotKeyEventDecoder.slot(for: .init(signature: GlobalHotKeyController.signature, id: 1)), .quickEntry)
        XCTAssertEqual(HotKeyEventDecoder.slot(for: .init(signature: GlobalHotKeyController.signature, id: 2)), .pauseResumePriority)
        XCTAssertNil(HotKeyEventDecoder.slot(for: .init(signature: 0, id: 1)))
        XCTAssertNil(HotKeyEventDecoder.slot(for: .init(signature: GlobalHotKeyController.signature, id: 3)))
        XCTAssertEqual(HotKeyEventStatus.result(for: .init(signature: GlobalHotKeyController.signature, id: 1)), 0)
        XCTAssertNotEqual(HotKeyEventStatus.result(for: nil), 0)
        XCTAssertNotEqual(HotKeyEventStatus.result(for: .init(signature: 0, id: 1)), 0)

        var deliveries: [HotKeySlot] = []
        let controller = GlobalHotKeyController(registrar: HotKeyRegistrarSpy(), quickEntry: { deliveries.append(.quickEntry); XCTAssertTrue(Thread.isMainThread) }, pauseResumePriority: { deliveries.append(.pauseResumePriority); XCTAssertTrue(Thread.isMainThread) })
        controller.handle(.quickEntry)
        controller.handle(.pauseResumePriority)
        XCTAssertEqual(deliveries, [.quickEntry, .pauseResumePriority])
    }

    func testDeinitUnregistersOwnedHotKeys() throws {
        let registrar = HotKeyRegistrarSpy()
        weak var weakController: GlobalHotKeyController?
        do {
            var controller: GlobalHotKeyController? = GlobalHotKeyController(registrar: registrar)
            weakController = controller
            try controller?.register(try Shortcut(keyCode: 1, modifiers: 256), for: .quickEntry)
            controller = nil
        }
        XCTAssertNil(weakController)
        XCTAssertEqual(registrar.operations, ["register:1", "unregister:1"])
    }

    func testShortcutRejectsInvalidKeyCodeAndModifiers() {
        XCTAssertThrowsError(try Shortcut(keyCode: 128, modifiers: 256))
        XCTAssertThrowsError(try Shortcut(keyCode: 1, modifiers: 0))
        XCTAssertThrowsError(try Shortcut(keyCode: 1, modifiers: 1))
    }
}

@MainActor
private final class HotKeyRegistrarSpy: HotKeyRegistrar {
    private var nextToken = 0
    private let rejectedKeyCode: UInt32?
    var failingUnregistrationTokens: Set<Int>
    private(set) var operations: [String] = []

    init(rejectedKeyCode: UInt32? = nil, rejectedUnregistrationToken: Int? = nil, failingUnregistrationTokens: Set<Int> = []) { self.rejectedKeyCode = rejectedKeyCode; self.failingUnregistrationTokens = failingUnregistrationTokens.union(rejectedUnregistrationToken.map { [$0] } ?? []) }

    func register(_ shortcut: Shortcut, identifier: HotKeyIdentifier) throws -> HotKeyToken {
        operations.append("register:\(shortcut.keyCode)")
        if shortcut.keyCode == rejectedKeyCode { throw HotKeyRegistrarError.registrationFailed(-9878) }
        nextToken += 1
        return HotKeyToken(rawValue: nextToken)
    }

    func unregister(_ token: HotKeyToken) throws { operations.append("unregister:\(token.rawValue)"); if failingUnregistrationTokens.contains(token.rawValue) { throw HotKeyRegistrarError.unregistrationFailed(-9877) } }
}
