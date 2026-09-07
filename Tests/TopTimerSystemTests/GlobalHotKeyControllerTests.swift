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
    }

    func testShutdownUnregistersOwnedHotKeys() throws {
        let registrar = HotKeyRegistrarSpy()
        let controller = GlobalHotKeyController(registrar: registrar)
        try controller.register(try Shortcut(keyCode: 1, modifiers: 256), for: .quickEntry)
        try controller.register(try Shortcut(keyCode: 2, modifiers: 256), for: .pauseResumePriority)

        controller.shutdown()
        XCTAssertEqual(registrar.operations, ["register:1", "register:2", "unregister:1", "unregister:2"])
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
    private let rejectedUnregistrationToken: Int?
    private(set) var operations: [String] = []

    init(rejectedKeyCode: UInt32? = nil, rejectedUnregistrationToken: Int? = nil) { self.rejectedKeyCode = rejectedKeyCode; self.rejectedUnregistrationToken = rejectedUnregistrationToken }

    func register(_ shortcut: Shortcut, identifier: HotKeyIdentifier) throws -> HotKeyToken {
        operations.append("register:\(shortcut.keyCode)")
        if shortcut.keyCode == rejectedKeyCode { throw HotKeyRegistrarError.registrationFailed(-9878) }
        nextToken += 1
        return HotKeyToken(rawValue: nextToken)
    }

    func unregister(_ token: HotKeyToken) throws { operations.append("unregister:\(token.rawValue)"); if token.rawValue == rejectedUnregistrationToken { throw HotKeyRegistrarError.unregistrationFailed(-9877) } }
}
