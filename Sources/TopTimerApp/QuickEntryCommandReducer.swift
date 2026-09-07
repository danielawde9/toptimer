import Foundation

public enum QuickEntryCommand: Equatable, Sendable { case up, down, `return`, escape, space }
public struct QuickEntryCommandState: Equatable, Sendable {
  public var suggestionIndex: Int
  public var suggestionCount: Int
  public var text: String
  public var selectionIsEntireText: Bool
  public var isComposing: Bool
  public init(
    suggestionIndex: Int, suggestionCount: Int, text: String, selectionIsEntireText: Bool,
    isComposing: Bool
  ) {
    self.suggestionIndex = suggestionIndex
    self.suggestionCount = suggestionCount
    self.text = text
    self.selectionIsEntireText = selectionIsEntireText
    self.isComposing = isComposing
  }
}
public enum QuickEntryEffect: Equatable, Sendable {
  case passThrough, selectSuggestion
  case run(selectedSuggestion: Bool)
  case clear, close, togglePriority
}
public struct QuickEntryCommandResult: Equatable, Sendable {
  public var suggestionIndex: Int
  public var effect: QuickEntryEffect
}
public enum QuickEntryCommandReducer {
  public static func reduce(_ command: QuickEntryCommand, state: QuickEntryCommandState)
    -> QuickEntryCommandResult
  {
    guard !state.isComposing else {
      return .init(suggestionIndex: state.suggestionIndex, effect: .passThrough)
    }
    let upper = max(0, state.suggestionCount - 1)
    switch command {
    case .up:
      return .init(
        suggestionIndex: max(0, min(upper, state.suggestionIndex - 1)),
        effect: state.suggestionCount > 0 ? .selectSuggestion : .passThrough)
    case .down:
      return .init(
        suggestionIndex: max(0, min(upper, state.suggestionIndex + 1)),
        effect: state.suggestionCount > 0 ? .selectSuggestion : .passThrough)
    case .return:
      return .init(
        suggestionIndex: state.suggestionIndex,
        effect: .run(selectedSuggestion: state.suggestionCount > 0))
    case .escape: return .init(suggestionIndex: 0, effect: state.text.isEmpty ? .close : .clear)
    case .space:
      return .init(
        suggestionIndex: state.suggestionIndex,
        effect: state.text.isEmpty || state.selectionIsEntireText ? .togglePriority : .passThrough)
    }
  }
}
