import SwiftUI

struct EmptyStateView: View {
  let title: String
  let symbol: String
  var detail: String? = nil
  let actionTitle: String
  let action: () -> Void

  var body: some View {
    VStack(spacing: 14) {
      Image(systemName: symbol).font(.system(size: 40)).foregroundStyle(.tertiary)
        .accessibilityHidden(true)
      Text(title).font(.headline)
      if let detail { Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center) }
      Button(actionTitle, action: action).buttonStyle(.borderedProminent).help(actionTitle)
    }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
