import XCTest
@testable import TopTimerApp

final class EditorDraftTests: XCTestCase {
    func testDraftRejectsMetadataAndVolumeOutsideEditorBounds() {
        var draft = EditorDraft(); draft.title = String(repeating: "x", count: 81)
        XCTAssertEqual(draft.validationError(), "Title must be 80 characters or fewer.")
        draft.title = "OK"; draft.volume = 2
        XCTAssertEqual(draft.validationError(), "Volume must be between 0 and 1.")
    }
}
