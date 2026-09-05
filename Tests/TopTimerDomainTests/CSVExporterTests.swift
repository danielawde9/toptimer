import Foundation
import XCTest
@testable import TopTimerDomain

final class CSVExporterTests: XCTestCase {
    func testQuotesCommasQuotesCarriageReturnsAndNewlinesUsingCRLFLines() throws {
        let entry = try HistoryEntry(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            timerID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            occurrenceID: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            title: "A, \"quoted\"\r\nline",
            details: "Description\rline",
            tags: ["zeta", "alpha,tag"],
            kind: .countdown,
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 1),
            elapsedSeconds: 1.5,
            completionReason: .finished
        )

        let csv = try CSVExporter().export([entry])

        XCTAssertEqual(
            csv,
            "id,title,description,tags,kind,started_at,ended_at,elapsed_seconds,reason\r\n"
                + "00000000-0000-0000-0000-000000000001,\"A, \"\"quoted\"\"\r\nline\",\"Description\rline\",\"alpha,tag|zeta\",countdown,1970-01-01T00:00:00.000Z,1970-01-01T00:00:01.000Z,1.5,finished\r\n"
        )
        XCTAssertEqual(Array(csv.utf8), Array(Data(csv.utf8)))
    }

    func testAcceptsTenThousandEntriesAndRejectsTenThousandAndOne() throws {
        let entry = try HistoryEntry(
            timerID: UUID(),
            occurrenceID: UUID(),
            title: "Focus",
            kind: .countdown,
            endedAt: .now,
            elapsedSeconds: 1,
            completionReason: .finished
        )
        let exporter = CSVExporter()

        XCTAssertTrue(try exporter.export(Array(repeating: entry, count: CSVExporter.maximumEntries)).hasPrefix("id,title,"))
        XCTAssertThrowsError(try exporter.export(Array(repeating: entry, count: CSVExporter.maximumEntries + 1))) { error in
            XCTAssertEqual(error as? CSVExporterError, .tooManyEntries)
        }
    }
}
