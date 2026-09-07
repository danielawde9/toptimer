@preconcurrency import IOKit.pwr_mgt
import Foundation

public typealias SleepAssertionID = UInt32
public enum SleepAssertionError: Error, Sendable, Equatable { case negativeTimerCount, creationFailed(Int32), releaseFailed(Int32) }

@MainActor public protocol PowerAssertionClient: AnyObject, Sendable {
    func createPreventIdleSleepAssertion() throws -> SleepAssertionID
    func releaseAssertion(_ id: SleepAssertionID) throws
}

@MainActor public final class SleepAssertionController {
    private let client: any PowerAssertionClient
    public private(set) var assertionID: SleepAssertionID?

    public init(client: any PowerAssertionClient = IOPowerAssertionClient()) { self.client = client }
    isolated deinit {
        if let assertionID { try? client.releaseAssertion(assertionID) }
    }

    public func setRunningTimerCount(_ count: Int, enabled: Bool) throws {
        guard count >= 0 else { throw SleepAssertionError.negativeTimerCount }
        if count > 0 && enabled {
            guard assertionID == nil else { return }
            assertionID = try client.createPreventIdleSleepAssertion()
            return
        }
        try releaseIfNeeded()
    }

    public func releaseIfNeeded() throws {
        guard let assertionID else { return }
        try client.releaseAssertion(assertionID)
        self.assertionID = nil
    }
}

@MainActor public final class IOPowerAssertionClient: PowerAssertionClient {
    public init() {}
    public func createPreventIdleSleepAssertion() throws -> SleepAssertionID {
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "TopTimer" as CFString, &id)
        guard result == kIOReturnSuccess else { throw SleepAssertionError.creationFailed(result) }
        return id
    }
    public func releaseAssertion(_ id: SleepAssertionID) throws {
        let result = IOPMAssertionRelease(id)
        guard result == kIOReturnSuccess else { throw SleepAssertionError.releaseFailed(result) }
    }
}
