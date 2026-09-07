@preconcurrency import ServiceManagement
import Foundation

public enum LoginItemStatus: Sendable, Equatable { case enabled, notRegistered, requiresApproval, notFound, unknown }
public enum LoginItemServiceError: Error, Sendable, Equatable { case registerFailed, unregisterFailed }
public enum LoginItemControllerError: Error, Sendable, Equatable { case registrationFailed, unregistrationFailed }

@MainActor public protocol LoginItemService: AnyObject {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
}

@MainActor public final class LoginItemController {
    private let service: any LoginItemService
    public init(service: any LoginItemService = SMAppLoginItemService()) { self.service = service }
    public var status: LoginItemStatus { service.status }
    public func setEnabled(_ enabled: Bool) throws {
        do { if enabled { try service.register() } else { try service.unregister() } }
        catch let error as LoginItemServiceError {
            switch error { case .registerFailed: throw LoginItemControllerError.registrationFailed; case .unregisterFailed: throw LoginItemControllerError.unregistrationFailed }
        } catch { throw enabled ? LoginItemControllerError.registrationFailed : LoginItemControllerError.unregistrationFailed }
    }
}

@MainActor public final class SMAppLoginItemService: LoginItemService {
    private let service: SMAppService
    public init(service: SMAppService = .mainApp) { self.service = service }
    public var status: LoginItemStatus {
        switch service.status {
        case .enabled: return .enabled
        case .notRegistered: return .notRegistered
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        @unknown default: return .unknown
        }
    }
    public func register() throws { do { try service.register() } catch { throw LoginItemServiceError.registerFailed } }
    public func unregister() throws { do { try service.unregister() } catch { throw LoginItemServiceError.unregisterFailed } }
}
