import XCTest
@preconcurrency import CoreData
import TopTimerDomain
@testable import TopTimerPersistence

final class BulkCleanupTests: XCTestCase {
    func testRemoveAllTimersIncludesEveryStateAndPreservesHistoryAndPresets() async throws {
        let (store, timers, _) = try await fixture()
        let expected = try await seed(store)
        let removed = try await timers.removeAllTimers()
        XCTAssertEqual(Set(removed), Set(expected))
        let counts = try await counts(store)
        XCTAssertEqual(counts, [0, 251, 251])
        let second = try await timers.removeAllTimers()
        XCTAssertTrue(second.isEmpty)
    }

    func testClearAllDataIncludesDeletedHistoryAndPresetsBeyondPageLimits() async throws {
        let (store, timers, _) = try await fixture()
        let expected = try await seed(store)
        let removed = try await timers.clearAllData()
        XCTAssertEqual(Set(removed), Set(expected))
        let counts = try await counts(store)
        XCTAssertEqual(counts, [0, 0, 0])
        let second = try await timers.clearAllData()
        XCTAssertTrue(second.isEmpty)
    }

    func testRemoveAllPresetsPermanentlyRemovesDeletedRowsAndPreservesTimersAndHistory() async throws {
        let (store, _, presets) = try await fixture()
        _ = try await seed(store)
        try await presets.removeAllPresets()
        let counts = try await counts(store)
        XCTAssertEqual(counts, [251, 251, 0])
        try await presets.removeAllPresets()
    }

    func testLegacyPresetConformerRejectsUnsupportedBulkCleanup() async throws {
        let repository: any PresetRepository = LegacyPresetRepository()
        do {
            try await repository.removeAllPresets()
            XCTFail("Default cleanup must not silently succeed")
        } catch {
            XCTAssertEqual(error as? TimerRepositoryError, .unsupportedOperation)
        }
    }

    private func fixture() async throws -> (CoreDataStore, TimerCoreDataRepository, PresetCoreDataRepository) {
        let store = try await CoreDataStore.inMemory()
        return (store, TimerCoreDataRepository(store: store), PresetCoreDataRepository(store: store))
    }

    private func counts(_ store: CoreDataStore) async throws -> [Int] {
        try await store.perform { context in
            try ["TimerRecord", "HistoryRecord", "PresetRecord"].map {
                try context.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: $0))
            }
        }
    }

    // Deliberately seed raw rows to cover hidden states and deleted records without
    // depending on bounded presentation queries or payload decoding for cleanup.
    private func seed(_ store: CoreDataStore) async throws -> [UUID] {
        try await store.perform { context in
            let date = Date(timeIntervalSinceReferenceDate: 1_000)
            let states: [TimerState] = [.idle, .running, .paused, .completed, .acknowledged, .cancelled]
            var ids: [UUID] = []
            for index in 0..<251 {
                let id = UUID()
                ids.append(id)
                let timer = TimerRecord(context: context)
                timer.id = id
                timer.occurrenceID = UUID()
                timer.state = states[index % states.count].rawValue
                timer.createdAt = date
                timer.deletedAt = index.isMultiple(of: 2) ? date : nil
                timer.payload = Data()
                let history = HistoryRecord(context: context)
                history.id = UUID()
                history.timerID = id
                history.occurrenceID = timer.occurrenceID
                history.endedAt = date
                history.deletedAt = index.isMultiple(of: 2) ? date : nil
                history.payload = Data()
                let preset = PresetRecord(context: context)
                preset.id = UUID()
                preset.createdAt = date
                preset.deletedAt = index.isMultiple(of: 2) ? date : nil
                preset.payload = Data()
            }
            try context.save()
            return ids
        }
    }
}

private struct LegacyPresetRepository: PresetRepository {
    func record(command: String, tags: [String], at: Date) async throws -> TimerPreset {
        try TimerPreset(command: command, tags: tags, createdAt: at, lastUsed: at)
    }
    func suggestions(query: String, limit: Int) async throws -> [TimerPreset] { [] }
    func softDeletePreset(_ id: UUID, at: Date) async throws {}
    func recoverPreset(_ id: UUID) async throws {}
}
