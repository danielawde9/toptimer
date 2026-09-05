@preconcurrency import CoreData
import Foundation
import TopTimerDomain

public enum TimerRepositoryError: Error, Equatable, Sendable {
    case invalidLimit
    case timerNotFound
    case unsupportedPayloadVersion(Int)
    case malformedPayload
}

public protocol TimerRepository: Sendable {
    func insert(_ timer: TimerItem) async throws -> TimerItem
    func update(_ timer: TimerItem) async throws
    func active(limit: Int) async throws -> [TimerItem]
    func activePage(limit: Int, after cursor: TimerPageCursor?) async throws -> TimerPage
    func complete(_ id: UUID, at date: Date) async throws -> CompletionOutcome
    func softDelete(_ id: UUID, at date: Date) async throws
    func historyCount(for timerID: UUID, limit: Int) async throws -> Int
    func successors(of occurrenceID: UUID, limit: Int) async throws -> [TimerItem]
    func timer(id: UUID) async throws -> TimerItem
}

public struct TimerPageCursor: Codable, Equatable, Sendable {
    public let createdAt: Date
    public let id: UUID

    public init(createdAt: Date, id: UUID) {
        self.createdAt = createdAt
        self.id = id
    }
}

public struct TimerPage: Equatable, Sendable {
    public let timers: [TimerItem]
    public let nextCursor: TimerPageCursor?

    public init(timers: [TimerItem], nextCursor: TimerPageCursor?) {
        self.timers = timers
        self.nextCursor = nextCursor
    }
}

public enum TimerPayloadCodec {
    private static let legacyVersion = 1
    private static let version = 2

    private struct Envelope: Codable {
        let version: Int
        let payload: Data
    }

    public static func encodeTimer(_ timer: TimerItem) throws -> Data {
        let payload = try canonicalTimerPayload(timer)
        return try encoder().encode(Envelope(version: version, payload: payload))
    }

    public static func decodeTimer(_ data: Data) throws -> TimerItem {
        let envelope: Envelope
        do {
            envelope = try decoder().decode(Envelope.self, from: data)
        } catch {
            throw TimerRepositoryError.malformedPayload
        }
        guard envelope.version == legacyVersion || envelope.version == version else {
            throw TimerRepositoryError.unsupportedPayloadVersion(envelope.version)
        }
        do {
            return try payloadDecoder(for: envelope.version).decode(TimerItem.self, from: envelope.payload)
        } catch {
            throw TimerRepositoryError.malformedPayload
        }
    }

    static func encodeHistory(_ history: HistoryEntry) throws -> Data {
        try encoder().encode(Envelope(version: version, payload: try canonicalHistoryPayload(history)))
    }

    static func decodeHistory(_ data: Data) throws -> HistoryEntry {
        let envelope: Envelope
        do {
            envelope = try decoder().decode(Envelope.self, from: data)
        } catch {
            throw TimerRepositoryError.malformedPayload
        }
        guard envelope.version == legacyVersion || envelope.version == version else {
            throw TimerRepositoryError.unsupportedPayloadVersion(envelope.version)
        }
        do {
            return try payloadDecoder(for: envelope.version).decode(HistoryEntry.self, from: envelope.payload)
        } catch {
            throw TimerRepositoryError.malformedPayload
        }
    }

    private static func canonicalTimerPayload(_ timer: TimerItem) throws -> Data {
        let raw = try encoder().encode(timer)
        guard var object = try JSONSerialization.jsonObject(with: raw) as? [String: Any] else {
            throw TimerRepositoryError.malformedPayload
        }
        if var recurrence = object["recurrence"] as? [String: Any],
           var selected = recurrence["selectedWeekdays"] as? [String: Any],
           let weekdays = selected["weekdays"] as? [NSNumber] {
            selected["weekdays"] = weekdays.sorted { $0.intValue < $1.intValue }
            recurrence["selectedWeekdays"] = selected
            object["recurrence"] = recurrence
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private static func canonicalHistoryPayload(_ history: HistoryEntry) throws -> Data {
        try encoder().encode(history)
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.dataEncodingStrategy = .base64
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        decoder.dataDecodingStrategy = .base64
        return decoder
    }

    private static func payloadDecoder(for version: Int) -> JSONDecoder {
        version == legacyVersion ? JSONDecoder() : decoder()
    }
}

public actor TimerCoreDataRepository: TimerRepository {
    private static let maximumLimit = 200
    private let store: CoreDataStore
    private let recurrence: RecurrenceService

    public init(store: CoreDataStore, calendar: Calendar = .autoupdatingCurrent) {
        self.store = store
        recurrence = RecurrenceService(calendar: calendar)
    }

    public func insert(_ timer: TimerItem) async throws -> TimerItem {
        return try await store.perform { context in
            do {
                let record = TimerRecord(context: context)
                try Self.apply(timer, to: record)
                try context.save()
                return timer
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    public func update(_ timer: TimerItem) async throws {
        try await store.perform { context in
            do {
                let record = try Self.timerRecord(id: timer.id, in: context)
                try Self.apply(timer, to: record)
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    public func active(limit: Int) async throws -> [TimerItem] {
        try Self.validate(limit: limit)
        return try await store.perform { context in
            let request = NSFetchRequest<TimerRecord>(entityName: "TimerRecord")
            request.predicate = NSPredicate(
                format: "deletedAt == nil AND (state == %@ OR state == %@ OR state == %@)",
                TimerState.idle.rawValue, TimerState.running.rawValue, TimerState.paused.rawValue
            )
            request.sortDescriptors = [
                NSSortDescriptor(key: "deadline", ascending: true),
                NSSortDescriptor(key: "createdAt", ascending: true),
                NSSortDescriptor(key: "id", ascending: true)
            ]
            request.fetchLimit = limit
            return try context.fetch(request).map { try TimerPayloadCodec.decodeTimer($0.payload) }
        }
    }

    public func activePage(limit: Int, after cursor: TimerPageCursor? = nil) async throws -> TimerPage {
        try Self.validate(limit: limit)
        return try await store.perform { context in
            let request = NSFetchRequest<TimerRecord>(entityName: "TimerRecord")
            let active = NSPredicate(
                format: "deletedAt == nil AND (state == %@ OR state == %@ OR state == %@)",
                TimerState.idle.rawValue, TimerState.running.rawValue, TimerState.paused.rawValue
            )
            if let cursor {
                let after = NSPredicate(
                    format: "createdAt > %@ OR (createdAt == %@ AND id > %@)",
                    cursor.createdAt as NSDate, cursor.createdAt as NSDate, cursor.id as NSUUID
                )
                request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [active, after])
            } else {
                request.predicate = active
            }
            request.sortDescriptors = [
                NSSortDescriptor(key: "createdAt", ascending: true),
                NSSortDescriptor(key: "id", ascending: true)
            ]
            request.fetchLimit = limit
            let records = try context.fetch(request)
            let timers = try records.map { try TimerPayloadCodec.decodeTimer($0.payload) }
            let nextCursor = records.count == limit ? TimerPageCursor(createdAt: records[limit - 1].createdAt, id: records[limit - 1].id) : nil
            return TimerPage(timers: timers, nextCursor: nextCursor)
        }
    }

    public func complete(_ id: UUID, at date: Date) async throws -> CompletionOutcome {
        try await store.perform { context in
            do {
                let record = try Self.timerRecord(id: id, in: context)
                let existing = try TimerPayloadCodec.decodeTimer(record.payload)
                let outcome = try self.recurrence.complete(existing, at: date)
                if outcome.completed == existing {
                    return outcome
                }
                try Self.apply(outcome.completed, to: record)
                let history = try Self.history(for: outcome.completed, at: date)
                let historyRecord = HistoryRecord(context: context)
                try Self.apply(history, to: historyRecord)
                if let successor = outcome.successor {
                    let successorRecord = TimerRecord(context: context)
                    try Self.apply(successor, to: successorRecord)
                }
                try context.save()
                return outcome
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    public func softDelete(_ id: UUID, at date: Date) async throws {
        try await store.perform { context in
            do {
                let record = try Self.timerRecord(id: id, in: context)
                let payload = try Self.payloadWithDeletedDate(record.payload, date: date)
                _ = try TimerPayloadCodec.decodeTimer(payload)
                record.deletedAt = date
                record.payload = payload
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    public func historyCount(for timerID: UUID, limit: Int = 200) async throws -> Int {
        try Self.validate(limit: limit)
        return try await store.perform { context in
            let request = NSFetchRequest<HistoryRecord>(entityName: "HistoryRecord")
            request.predicate = NSPredicate(format: "timerID == %@", timerID as NSUUID)
            request.sortDescriptors = [NSSortDescriptor(key: "endedAt", ascending: false), NSSortDescriptor(key: "id", ascending: true)]
            request.fetchLimit = limit
            request.resultType = .managedObjectIDResultType
            return try context.fetch(request).count
        }
    }

    public func timer(id: UUID) async throws -> TimerItem {
        try await store.perform { context in
            let record = try Self.timerRecord(id: id, in: context)
            return try TimerPayloadCodec.decodeTimer(record.payload)
        }
    }

    public func successors(of occurrenceID: UUID, limit: Int = 200) async throws -> [TimerItem] {
        try Self.validate(limit: limit)
        return try await store.perform { context in
            let request = NSFetchRequest<TimerRecord>(entityName: "TimerRecord")
            request.predicate = NSPredicate(format: "predecessorOccurrenceID == %@", occurrenceID as NSUUID)
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true), NSSortDescriptor(key: "id", ascending: true)]
            request.fetchLimit = limit
            return try context.fetch(request).map { try TimerPayloadCodec.decodeTimer($0.payload) }
        }
    }

    public func insertHistory(_ history: HistoryEntry) async throws {
        try await store.perform { context in
            do {
                let record = HistoryRecord(context: context)
                try Self.apply(history, to: record)
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    private static func validate(limit: Int) throws {
        guard (1...maximumLimit).contains(limit) else {
            throw TimerRepositoryError.invalidLimit
        }
    }

    private static func timerRecord(id: UUID, in context: NSManagedObjectContext) throws -> TimerRecord {
        let request = NSFetchRequest<TimerRecord>(entityName: "TimerRecord")
        request.predicate = NSPredicate(format: "id == %@", id as NSUUID)
        request.fetchLimit = 1
        request.sortDescriptors = [NSSortDescriptor(key: "id", ascending: true)]
        guard let record = try context.fetch(request).first else {
            throw TimerRepositoryError.timerNotFound
        }
        return record
    }

    private static func apply(_ timer: TimerItem, to record: TimerRecord) throws {
        record.id = timer.id
        record.occurrenceID = timer.occurrenceID
        record.predecessorOccurrenceID = timer.predecessorOccurrenceID
        record.state = timer.state.rawValue
        record.deadline = timer.deadline
        record.createdAt = timer.createdAt
        record.completedAt = timer.completedAt
        record.deletedAt = timer.deletedAt
        record.payload = try TimerPayloadCodec.encodeTimer(timer)
    }

    private static func apply(_ history: HistoryEntry, to record: HistoryRecord) throws {
        record.id = history.id
        record.timerID = history.timerID
        record.occurrenceID = history.occurrenceID
        record.endedAt = history.endedAt
        record.deletedAt = history.deletedAt
        record.payload = try TimerPayloadCodec.encodeHistory(history)
    }

    private static func history(for timer: TimerItem, at date: Date) throws -> HistoryEntry {
        let elapsed: TimeInterval
        switch timer.kind {
        case .countdown:
            elapsed = timer.duration ?? 0
        case .stopwatch:
            guard let startedAt = timer.startedAt else { throw TimerTransitionError.invalidState }
            elapsed = max(0, date.timeIntervalSince(startedAt) - timer.accumulatedPause)
        }
        return try HistoryEntry(
            timerID: timer.id,
            occurrenceID: timer.occurrenceID,
            title: timer.title,
            details: timer.details,
            tags: timer.tags,
            kind: timer.kind,
            startedAt: timer.startedAt,
            endedAt: date,
            elapsedSeconds: elapsed,
            completionReason: .finished
        )
    }

    private static func payloadWithDeletedDate(_ data: Data, date: Date) throws -> Data {
        guard var envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let encoded = envelope["payload"] as? String,
              let payload = Data(base64Encoded: encoded),
              var timer = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            throw TimerRepositoryError.malformedPayload
        }
        timer["deletedAt"] = date.timeIntervalSince1970 * 1_000
        let timerData = try JSONSerialization.data(withJSONObject: timer, options: [.sortedKeys])
        envelope["payload"] = timerData.base64EncodedString()
        return try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
    }
}
