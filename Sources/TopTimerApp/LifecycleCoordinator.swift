import Foundation

public struct LifecycleCoordinator: Sendable {
    public enum Result: Equatable, Sendable { case success, failure }
    public enum Effect: Equatable, Sendable { case createResources, hideFailure, showFailure, beginClose, stopResources, reportCloseFailure, replyToTermination(Bool) }
    private var resourcesRunning = false; private var closing = false; private var terminationReplied = false; private var closeFailed = false
    public init() {}
    public mutating func startResult(_ result: Result) -> [Effect] {
        switch result { case .success where !resourcesRunning: resourcesRunning = true; return [.createResources, .hideFailure]; case .failure: return resourcesRunning ? [] : [.showFailure]; default: return [] }
    }
    public mutating func requestTermination() -> [Effect] { guard !closing, !terminationReplied else { return [] }; closing = true; return [.beginClose] + (resourcesRunning ? [.stopResources] : []) }
    public mutating func closeResult(_ result: Result) -> [Effect] { guard closing, !terminationReplied else { return [] }; if result == .failure { closeFailed = true; return [.reportCloseFailure] }; terminationReplied = true; resourcesRunning = false; return [.replyToTermination(true)] }
    public mutating func quitAfterCloseFailure() -> [Effect] { guard closing, closeFailed, !terminationReplied else { return [] }; terminationReplied = true; resourcesRunning = false; return [.replyToTermination(true)] }
}
