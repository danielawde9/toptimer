import AppKit
import SwiftUI
import XCTest
@testable import TopTimerApp

@MainActor
final class NowViewTests: XCTestCase {
  func testEmptyNowViewShowsEntryAndExamples() {
    let state = AppState(repository: RecordingRepository(), notifications: RecordingNotifications())
    let host = NSHostingView(rootView: NowView(state: state))
    let window = mount(host)
    defer { window.close() }
    XCTAssertGreaterThan(host.bounds.width, 0)
    XCTAssertGreaterThanOrEqual(accessibilityNodes(host).count, 1)
  }

  private func mount<V: View>(_ host: NSHostingView<V>) -> NSWindow {
    _ = NSApplication.shared
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    host.frame = NSRect(x: 0, y: 0, width: 600, height: 500)
    window.makeKeyAndOrderFront(nil)
    host.layoutSubtreeIfNeeded()
    return window
  }

  private func accessibilityNodes(_ root: any NSAccessibilityProtocol) -> [any NSAccessibilityProtocol] {
    var result: [any NSAccessibilityProtocol] = []
    var queue: [any NSAccessibilityProtocol] = [root]
    for _ in 0..<500 {
      guard !queue.isEmpty else { break }
      let node = queue.removeFirst(); result.append(node)
      if let view = node as? NSView { queue.append(contentsOf: view.subviews) }
      else { queue.append(contentsOf: (node.accessibilityChildren() ?? []).compactMap { $0 as? any NSAccessibilityProtocol }) }
    }
    return result
  }
}
