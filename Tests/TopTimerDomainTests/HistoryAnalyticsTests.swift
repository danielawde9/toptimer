import Foundation
import XCTest
@testable import TopTimerDomain

final class HistoryAnalyticsTests: XCTestCase {
    private let day = Date(timeIntervalSince1970: 1_704_067_200)

    func testFiltersTitleDescriptionAndTagsCaseInsensitively() throws {
        let title = try entry(title: "Client call")
        let details = try entry(title: "Focus", details: "CLIENT notes")
        let tag = try entry(title: "Focus", tags: ["client-work"])
        let other = try entry(title: "Personal")

        XCTAssertEqual(
            try HistoryAnalytics(calendar: utcCalendar).filter([title, details, tag, other], query: "CLIENT").map(\.id),
            [title.id, details.id, tag.id]
        )
    }

    func testRejectsMoreThanTenThousandEntries() throws {
        let entry = try self.entry(title: "Focus")
        let entries = Array(repeating: entry, count: HistoryAnalytics.maximumEntries + 1)

        XCTAssertThrowsError(try HistoryAnalytics(calendar: utcCalendar).totalsByDay(entries)) { error in
            XCTAssertEqual(error as? HistoryAnalyticsError, .tooManyEntries)
        }
    }

    func testGroupsElapsedTimeByDayWeekTimerAndTag() throws {
        let first = try self.entry(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            timerID: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            title: "Focus",
            tags: ["Work", "Shared"],
            endedAt: day,
            elapsed: 60
        )
        let second = try self.entry(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            timerID: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            title: "Focus",
            tags: ["Work"],
            endedAt: day.addingTimeInterval(3_600),
            elapsed: 30
        )
        let analytics = HistoryAnalytics(calendar: utcCalendar)
        let entries = [first, second]

        XCTAssertEqual(try analytics.totalsByDay(entries), [day: 90])
        XCTAssertEqual(try analytics.totalsByWeek(entries), [day: 90])
        XCTAssertEqual(try analytics.totalsByTimer(entries), [first.timerID: 90])
        XCTAssertEqual(try analytics.totalsByTag(entries), ["shared": 60, "work": 90])
    }

    func testGroupsEachNormalizedTagAtMostOncePerEntry() throws {
        let entry = try self.entry(title: "Focus", tags: ["Work", "work", " WÓRK "], elapsed: 60)

        XCTAssertEqual(try HistoryAnalytics(calendar: utcCalendar).totalsByTag([entry]), ["work": 60])
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func entry(
        id: UUID = UUID(),
        timerID: UUID = UUID(),
        title: String,
        details: String = "",
        tags: [String] = [],
        endedAt: Date? = nil,
        elapsed: TimeInterval = 60
    ) throws -> HistoryEntry {
        try HistoryEntry(
            id: id,
            timerID: timerID,
            occurrenceID: UUID(),
            title: title,
            details: details,
            tags: tags,
            kind: .countdown,
            endedAt: endedAt ?? day,
            elapsedSeconds: elapsed,
            completionReason: .finished
        )
    }
}
