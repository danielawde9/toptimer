import XCTest
@testable import TopTimerApp

final class QuickEntryCommandReducerTests: XCTestCase {
    func testArrowKeysKeepSelectionWithinSuggestionBounds() {
        XCTAssertEqual(QuickEntryCommandReducer.reduce(.down, state: .init(suggestionIndex: 0, suggestionCount: 2, text: "5m", selectionIsEntireText: false, isComposing: false)).suggestionIndex, 1)
        XCTAssertEqual(QuickEntryCommandReducer.reduce(.down, state: .init(suggestionIndex: 1, suggestionCount: 2, text: "5m", selectionIsEntireText: false, isComposing: false)).suggestionIndex, 1)
        XCTAssertEqual(QuickEntryCommandReducer.reduce(.up, state: .init(suggestionIndex: 0, suggestionCount: 2, text: "5m", selectionIsEntireText: false, isComposing: false)).suggestionIndex, 0)
    }

    func testReturnSelectsSuggestionThenUsesTheSameRunAction() {
        let result = QuickEntryCommandReducer.reduce(.return, state: .init(suggestionIndex: 1, suggestionCount: 2, text: "5", selectionIsEntireText: false, isComposing: false))
        XCTAssertEqual(result.effect, .run(selectedSuggestion: true))
    }

    func testCompositionDoesNotInterceptCommands() {
        let result = QuickEntryCommandReducer.reduce(.space, state: .init(suggestionIndex: 0, suggestionCount: 1, text: "", selectionIsEntireText: true, isComposing: true))
        XCTAssertEqual(result.effect, .passThrough)
    }

    func testSpacePausesOnlyForEmptyOrWholeSelection() {
        XCTAssertEqual(QuickEntryCommandReducer.reduce(.space, state: .init(suggestionIndex: 0, suggestionCount: 0, text: "", selectionIsEntireText: false, isComposing: false)).effect, .togglePriority)
        XCTAssertEqual(QuickEntryCommandReducer.reduce(.space, state: .init(suggestionIndex: 0, suggestionCount: 0, text: "5m", selectionIsEntireText: true, isComposing: false)).effect, .togglePriority)
        XCTAssertEqual(QuickEntryCommandReducer.reduce(.space, state: .init(suggestionIndex: 0, suggestionCount: 0, text: "5m", selectionIsEntireText: false, isComposing: false)).effect, .passThrough)
    }

    func testEscapeClearsThenCloses() {
        XCTAssertEqual(QuickEntryCommandReducer.reduce(.escape, state: .init(suggestionIndex: 0, suggestionCount: 1, text: "5m", selectionIsEntireText: false, isComposing: false)).effect, .clear)
        XCTAssertEqual(QuickEntryCommandReducer.reduce(.escape, state: .init(suggestionIndex: 0, suggestionCount: 0, text: "", selectionIsEntireText: false, isComposing: false)).effect, .close)
    }
}
