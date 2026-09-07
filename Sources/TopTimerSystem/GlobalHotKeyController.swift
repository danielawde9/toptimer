@preconcurrency import Carbon
import Foundation

public struct Shortcut: Sendable, Equatable, Hashable {
    public static let supportedModifiers: UInt32 = 256 | 512 | 2048 | 4096
    public let keyCode: UInt32
    public let modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) throws {
        guard keyCode < 128 else { throw GlobalHotKeyControllerError.invalidShortcut }
        guard modifiers != 0, modifiers & ~Self.supportedModifiers == 0 else { throw GlobalHotKeyControllerError.invalidShortcut }
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public enum HotKeySlot: CaseIterable, Sendable, Equatable { case quickEntry, pauseResumePriority }
public struct HotKeyIdentifier: Sendable, Equatable { public let signature: UInt32; public let id: UInt32; public init(signature: UInt32, id: UInt32) { self.signature = signature; self.id = id } }
public struct HotKeyToken: Sendable, Equatable, Hashable { public let rawValue: Int; public init(rawValue: Int) { self.rawValue = rawValue } }
public enum HotKeyRegistrarError: Error, Sendable, Equatable { case registrationFailed(Int32), unregistrationFailed(Int32) }
public enum GlobalHotKeyControllerError: Error, Sendable, Equatable { case invalidShortcut, shortcutConflict, registrationFailed, unregistrationFailed, shutdownFailed([HotKeySlot]) }

@MainActor public protocol HotKeyRegistrar: AnyObject, Sendable {
    func register(_ shortcut: Shortcut, identifier: HotKeyIdentifier) throws -> HotKeyToken
    func unregister(_ token: HotKeyToken) throws
}

@MainActor public final class GlobalHotKeyController {
    public nonisolated static let signature: UInt32 = 0x5454_4D52 // TTMR
    private let registrar: any HotKeyRegistrar
    private let quickEntry: @MainActor @Sendable () -> Void
    private let pauseResumePriority: @MainActor @Sendable () -> Void
    private var registrations: [HotKeySlot: Registration] = [:]

    public init(registrar: any HotKeyRegistrar = CarbonHotKeyRegistrar(), quickEntry: @escaping @MainActor @Sendable () -> Void = {}, pauseResumePriority: @escaping @MainActor @Sendable () -> Void = {}) {
        self.registrar = registrar
        self.quickEntry = quickEntry
        self.pauseResumePriority = pauseResumePriority
        (registrar as? CarbonHotKeyRegistrar)?.attach(controller: self)
    }

    isolated deinit {
        for registration in registrations.values {
            do { try registrar.unregister(registration.token) }
            catch { assertionFailure("TopTimer could not unregister an owned hotkey during deinitialization: \(error)") }
        }
    }

    public func shortcut(for slot: HotKeySlot) -> Shortcut? { registrations[slot]?.shortcut }

    public func register(_ shortcut: Shortcut, for slot: HotKeySlot) throws {
        guard registrations.allSatisfy({ $0.key == slot || $0.value.shortcut != shortcut }) else { throw GlobalHotKeyControllerError.shortcutConflict }
        let replacement: HotKeyToken
        do { replacement = try registrar.register(shortcut, identifier: Self.identifier(for: slot)) }
        catch { throw Self.map(error) }
        let previous = registrations[slot]
        if let previous {
            do { try registrar.unregister(previous.token) }
            catch {
                do { try registrar.unregister(replacement) }
                catch { preconditionFailure("TopTimer could not roll back a replacement hotkey: \(error)") }
                throw Self.map(error)
            }
        }
        registrations[slot] = Registration(shortcut: shortcut, token: replacement)
    }

    public func shutdown() throws {
        var failedSlots: [HotKeySlot] = []
        for slot in HotKeySlot.allCases {
            guard let registration = registrations[slot] else { continue }
            do { try registrar.unregister(registration.token); registrations.removeValue(forKey: slot) }
            catch { failedSlots.append(slot) }
        }
        guard failedSlots.isEmpty else { throw GlobalHotKeyControllerError.shutdownFailed(failedSlots) }
    }

    func handle(_ slot: HotKeySlot) {
        switch slot { case .quickEntry: quickEntry(); case .pauseResumePriority: pauseResumePriority() }
    }

    private static func identifier(for slot: HotKeySlot) -> HotKeyIdentifier {
        .init(signature: signature, id: slot == .quickEntry ? 1 : 2)
    }

    private static func map(_ error: Error) -> GlobalHotKeyControllerError {
        if let error = error as? HotKeyRegistrarError, case .unregistrationFailed = error { return .unregistrationFailed }
        return .registrationFailed
    }

    private struct Registration { let shortcut: Shortcut; let token: HotKeyToken }
}

enum HotKeyEventDecoder {
    static func slot(for identifier: HotKeyIdentifier) -> HotKeySlot? {
        guard identifier.signature == GlobalHotKeyController.signature else { return nil }
        switch identifier.id { case 1: return .quickEntry; case 2: return .pauseResumePriority; default: return nil }
    }
}

@MainActor public final class CarbonHotKeyRegistrar: HotKeyRegistrar {
    private var references: [HotKeyToken: EventHotKeyRef] = [:]
    private var nextToken = 0
    private var handler: EventHandlerRef?
    private weak var controller: GlobalHotKeyController?

    public init() {}
    isolated deinit {
        for reference in references.values {
            if UnregisterEventHotKey(reference) != noErr { assertionFailure("TopTimer could not unregister a retained Carbon hotkey during deinitialization.") }
        }
        references.removeAll()
        if let handler { RemoveEventHandler(handler) }
    }

    public func attach(controller: GlobalHotKeyController) { self.controller = controller }

    public func register(_ shortcut: Shortcut, identifier: HotKeyIdentifier) throws -> HotKeyToken {
        try installHandlerIfNeeded()
        var hotKey: EventHotKeyRef?
        let eventID = EventHotKeyID(signature: identifier.signature, id: identifier.id)
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, eventID, GetApplicationEventTarget(), 0, &hotKey)
        guard status == noErr, let hotKey else { throw HotKeyRegistrarError.registrationFailed(status) }
        nextToken += 1
        let token = HotKeyToken(rawValue: nextToken)
        references[token] = hotKey
        return token
    }

    public func unregister(_ token: HotKeyToken) throws {
        guard let reference = references[token] else { return }
        let status = UnregisterEventHotKey(reference)
        guard status == noErr else { throw HotKeyRegistrarError.unregistrationFailed(status) }
        references.removeValue(forKey: token)
    }

    private func installHandlerIfNeeded() throws {
        guard handler == nil else { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            let registrar = Unmanaged<CarbonHotKeyRegistrar>.fromOpaque(userData).takeUnretainedValue()
            registrar.route(event)
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { throw HotKeyRegistrarError.registrationFailed(status) }
    }

    private func route(_ event: EventRef) {
        var eventID = EventHotKeyID()
        guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &eventID) == noErr else { return }
        let identifier = HotKeyIdentifier(signature: eventID.signature, id: eventID.id)
        guard let slot = HotKeyEventDecoder.slot(for: identifier) else { return }
        Task { @MainActor [weak controller] in controller?.handle(slot) }
    }
}
