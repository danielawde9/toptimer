@preconcurrency import CoreData
import Foundation
import TopTimerDomain

public enum TimerRepositoryError: Error, Equatable, Sendable {
    case invalidCreation
    case timerNotFound
    case unsupportedPayloadVersion(Int)
    case malformedPayload
    case presetUseCountOverflow
    case presetCapacityReached
    case invalidPresetQuery
    case duplicatePreset
    case priorityCandidateCapacityReached
    case staleTimerUpdate
    case staleHistoryUpdate
}

public protocol TimerRepository: Sendable {
    func insert(_ timer: TimerItem) async throws -> TimerItem
    func update(_ timer: TimerItem) async throws
    func active(limit: Int) async throws -> [TimerItem]
    func due(at date: Date, limit: Int) async throws -> [TimerItem]
    func priority(at date: Date) async throws -> TimerItem?
    func activePage(limit: Int, after cursor: TimerPageCursor?) async throws -> TimerPage
    func complete(_ id: UUID, at date: Date) async throws -> CompletionOutcome
    func cancel(id: UUID, at date: Date) async throws -> TimerItem
    func softDelete(_ id: UUID, at date: Date) async throws
    func historyPage(from: Date?, through: Date?, query: String, limit: Int, after cursor: HistoryPageCursor?) async throws -> HistoryPage
    func updateHistory(_ history: HistoryEntry) async throws
    func softDeleteHistory(_ id: UUID, at date: Date) async throws
    func recoverHistory(_ id: UUID) async throws
    func purgeHistory(endedBefore cutoff: Date) async throws -> Int
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

public struct HistoryPageCursor: Codable, Equatable, Sendable {
    public let endedAt: Date
    public let id: UUID

    public init(endedAt: Date, id: UUID) {
        self.endedAt = endedAt
        self.id = id
    }
}

public struct HistoryPage: Equatable, Sendable {
    public let entries: [HistoryEntry]
    public let nextCursor: HistoryPageCursor?

    public init(entries: [HistoryEntry], nextCursor: HistoryPageCursor?) {
        self.entries = entries
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
    private static let defaultMaximumPriorityCandidates = 10_000
    // Search may inspect at most 10,000 raw rows per call; callers continue with the cursor.
    private static let maximumHistorySearchScan = 10_000
    private let store: CoreDataStore
    private let recurrence: RecurrenceService
    private let maximumPriorityCandidates: Int

    public init(store: CoreDataStore, calendar: Calendar = .autoupdatingCurrent, maximumPriorityCandidates: Int = 10_000) {
        self.store = store
        recurrence = RecurrenceService(calendar: calendar)
        self.maximumPriorityCandidates = min(Self.defaultMaximumPriorityCandidates, max(1, maximumPriorityCandidates))
    }

    public func insert(_ timer: TimerItem) async throws -> TimerItem {
        try Self.validateCreation(timer)
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
                let stored = try TimerPayloadCodec.decodeTimer(record.payload)
                try Self.validateUpdate(timer, against: stored)
                try Self.apply(timer, to: record)
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    public func active(limit: Int) async throws -> [TimerItem] {
        let limit = Self.boundedLimit(limit)
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

    public func due(at date: Date, limit: Int) async throws -> [TimerItem] {
        guard date.timeIntervalSinceReferenceDate.isFinite else { return [] }
        let limit = min(100, Self.boundedLimit(limit))
        return try await store.perform { context in
            let request = NSFetchRequest<TimerRecord>(entityName: "TimerRecord")
            request.predicate = NSPredicate(format: "deletedAt == nil AND state == %@ AND deadline != nil AND deadline <= %@", TimerState.running.rawValue, date as NSDate)
            request.sortDescriptors = [NSSortDescriptor(key: "deadline", ascending: true), NSSortDescriptor(key: "id", ascending: true)]
            request.fetchLimit = limit
            return try context.fetch(request).map { try TimerPayloadCodec.decodeTimer($0.payload) }
        }
    }

    public func priority(at date: Date) async throws -> TimerItem? {
        guard date.timeIntervalSinceReferenceDate.isFinite else { return nil }
        let maximum = maximumPriorityCandidates
        return try await store.perform { context in
            let request = NSFetchRequest<TimerRecord>(entityName: "TimerRecord")
            request.predicate = NSPredicate(format: "deletedAt == nil AND state == %@", TimerState.running.rawValue)
            request.sortDescriptors = [NSSortDescriptor(key: "id", ascending: true)]
            request.fetchLimit = maximum + 1
            let records = try context.fetch(request)
            guard records.count <= maximum else { throw TimerRepositoryError.priorityCandidateCapacityReached }
            return TimerPriority.select(from: try records.map { try TimerPayloadCodec.decodeTimer($0.payload) }, at: date)
        }
    }

    public func activePage(limit: Int, after cursor: TimerPageCursor? = nil) async throws -> TimerPage {
        let limit = Self.boundedLimit(limit)
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
            let nextCursor = try records.last.flatMap { last in
                let probe = NSFetchRequest<NSManagedObjectID>(entityName: "TimerRecord")
                let after = NSPredicate(
                    format: "createdAt > %@ OR (createdAt == %@ AND id > %@)",
                    last.createdAt as NSDate, last.createdAt as NSDate, last.id as NSUUID
                )
                probe.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [active, after])
                probe.sortDescriptors = request.sortDescriptors
                probe.fetchLimit = 1
                probe.resultType = .managedObjectIDResultType
                return try context.fetch(probe).isEmpty ? nil : TimerPageCursor(createdAt: last.createdAt, id: last.id)
            }
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

    public func cancel(id: UUID, at date: Date) async throws -> TimerItem {
        try await store.perform { context in
            do {
                let record = try Self.timerRecord(id: id, in: context)
                var timer = try TimerPayloadCodec.decodeTimer(record.payload)
                if timer.state == .cancelled {
                    return timer
                }
                try timer.cancel(at: date)
                try Self.apply(timer, to: record)
                let historyRecord = HistoryRecord(context: context)
                try Self.apply(try Self.history(for: timer, at: date, reason: .cancelled), to: historyRecord)
                try context.save()
                return timer
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
                var timer = try TimerPayloadCodec.decodeTimer(record.payload)
                if timer.deletedAt != nil {
                    return
                }
                try timer.softDelete(at: date)
                try Self.apply(timer, to: record)
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    public func historyPage(
        from: Date?,
        through: Date?,
        query: String,
        limit: Int,
        after cursor: HistoryPageCursor? = nil
    ) async throws -> HistoryPage {
        let limit = Self.boundedLimit(limit)
        return try await store.perform { context in
            let request = NSFetchRequest<HistoryRecord>(entityName: "HistoryRecord")
            let range = Self.historyRangePredicate(from: from, through: through, excludingDeleted: true)
            if let cursor {
                let after = NSPredicate(
                    format: "endedAt < %@ OR (endedAt == %@ AND id < %@)",
                    cursor.endedAt as NSDate, cursor.endedAt as NSDate, cursor.id as NSUUID
                )
                request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [range, after])
            } else {
                request.predicate = range
            }
            request.sortDescriptors = [
                NSSortDescriptor(key: "endedAt", ascending: false),
                NSSortDescriptor(key: "id", ascending: false)
            ]
            var matches: [HistoryEntry] = []
            var scanCursor = cursor
            var lastScanned: HistoryRecord?
            var scannedCount = 0
            var exhausted = false
            while matches.count < limit && scannedCount < Self.maximumHistorySearchScan {
                let batchSize = min(Self.maximumLimit, Self.maximumHistorySearchScan - scannedCount)
                let batchRequest = request.copy() as! NSFetchRequest<HistoryRecord>
                batchRequest.fetchLimit = batchSize
                if let scanCursor {
                    let after = NSPredicate(
                        format: "endedAt < %@ OR (endedAt == %@ AND id < %@)",
                        scanCursor.endedAt as NSDate, scanCursor.endedAt as NSDate, scanCursor.id as NSUUID
                    )
                    batchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [range, after])
                }
                let records = try context.fetch(batchRequest)
                if records.isEmpty {
                    exhausted = true
                    break
                }
                for record in records {
                    lastScanned = record
                    scannedCount += 1
                    let entry = try TimerPayloadCodec.decodeHistory(record.payload)
                    if Self.matchesSearch(entry, query: query) {
                        matches.append(entry)
                    }
                    if matches.count == limit {
                        break
                    }
                }
                scanCursor = lastScanned.map { HistoryPageCursor(endedAt: $0.endedAt, id: $0.id) }
                if records.count < batchSize || matches.count == limit {
                    exhausted = matches.count == limit ? false : records.count < batchSize
                    break
                }
            }
            let nextCursor = exhausted ? nil : lastScanned.map { HistoryPageCursor(endedAt: $0.endedAt, id: $0.id) }
            return HistoryPage(entries: matches, nextCursor: nextCursor)
        }
    }

    public func updateHistory(_ history: HistoryEntry) async throws {
        try await store.perform { context in
            do {
                let record = try Self.historyRecord(id: history.id, in: context)
                let stored = try TimerPayloadCodec.decodeHistory(record.payload)
                try Self.validateHistoryUpdate(history, against: stored)
                try Self.apply(history, to: record)
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    public func softDeleteHistory(_ id: UUID, at date: Date) async throws {
        try await updateHistoryDeletion(id, deletedAt: date, onlyWhenDeleted: false)
    }

    public func recoverHistory(_ id: UUID) async throws {
        try await updateHistoryDeletion(id, deletedAt: nil, onlyWhenDeleted: true)
    }

    public func purgeHistory(endedBefore cutoff: Date) async throws -> Int {
        try await store.perform { context in
            do {
                let request = NSFetchRequest<HistoryRecord>(entityName: "HistoryRecord")
                request.predicate = NSPredicate(format: "endedAt < %@", cutoff as NSDate)
                request.sortDescriptors = [
                    NSSortDescriptor(key: "endedAt", ascending: true),
                    NSSortDescriptor(key: "id", ascending: true)
                ]
                request.fetchLimit = Self.maximumLimit
                let records = try context.fetch(request)
                for record in records {
                    context.delete(record)
                }
                try context.save()
                return records.count
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    public func historyCount(for timerID: UUID, limit: Int = 200) async throws -> Int {
        let limit = Self.boundedLimit(limit)
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
        let limit = Self.boundedLimit(limit)
        return try await store.perform { context in
            let request = NSFetchRequest<TimerRecord>(entityName: "TimerRecord")
            request.predicate = NSPredicate(format: "predecessorOccurrenceID == %@", occurrenceID as NSUUID)
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true), NSSortDescriptor(key: "id", ascending: true)]
            request.fetchLimit = limit
            return try context.fetch(request).map { try TimerPayloadCodec.decodeTimer($0.payload) }
        }
    }

    func insertHistory(_ history: HistoryEntry) async throws {
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

    private static func boundedLimit(_ limit: Int) -> Int {
        min(maximumLimit, max(1, limit))
    }

    private static func validateCreation(_ timer: TimerItem) throws {
        guard timer.predecessorOccurrenceID == nil,
              timer.successorID == nil,
              timer.completedAt == nil,
              timer.deletedAt == nil else {
            throw TimerRepositoryError.invalidCreation
        }
        switch timer.state {
        case .idle:
            guard timer.revision == 0 else { throw TimerRepositoryError.invalidCreation }
        case .running:
            guard timer.revision == 1,
                  let startedAt = timer.startedAt,
                  timer.lastTransitionAt == startedAt,
                  timer.pausedAt == nil else {
                throw TimerRepositoryError.invalidCreation
            }
            switch timer.kind {
            case .countdown:
                guard timer.deadline != nil, timer.remaining == nil else {
                    throw TimerRepositoryError.invalidCreation
                }
            case .stopwatch:
                guard timer.deadline == nil, timer.remaining == nil, timer.accumulatedPause == 0 else {
                    throw TimerRepositoryError.invalidCreation
                }
            }
        case .paused, .completed, .acknowledged, .cancelled:
            throw TimerRepositoryError.invalidCreation
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

    private static func historyRecord(id: UUID, in context: NSManagedObjectContext) throws -> HistoryRecord {
        let request = NSFetchRequest<HistoryRecord>(entityName: "HistoryRecord")
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

    private static func validateUpdate(_ incoming: TimerItem, against stored: TimerItem) throws {
        guard incoming.id == stored.id,
              incoming.occurrenceID == stored.occurrenceID,
              incoming.predecessorOccurrenceID == stored.predecessorOccurrenceID,
              incoming.successorID == stored.successorID,
              stored.deletedAt == nil,
              incoming.deletedAt == nil,
              stored.revision < Int.max,
              incoming.revision == stored.revision + 1,
              isPermittedUpdate(incoming, from: stored) else {
            throw TimerRepositoryError.staleTimerUpdate
        }
    }

    private static func isPermittedUpdate(_ incoming: TimerItem, from stored: TimerItem) -> Bool {
        guard incoming.state == .idle || incoming.state == .running || incoming.state == .paused else {
            return false
        }
        switch (stored.state, incoming.state) {
        case (.idle, .idle), (.paused, .paused):
            return matchesMetadataUpdate(incoming, from: stored)
        case (.running, .running):
            return matchesMetadataUpdate(incoming, from: stored) || matchesTransition(incoming, from: stored) { timer, date in
                try timer.restart(at: date)
            }
        case (.idle, .running):
            return matchesTransition(incoming, from: stored) { timer, date in
                try timer.start(at: date)
            }
        case (.running, .paused):
            return matchesTransition(incoming, from: stored) { timer, date in
                try timer.pause(at: date)
            }
        case (.paused, .running):
            return matchesTransition(incoming, from: stored) { timer, date in
                try timer.resume(at: date)
            } || matchesTransition(incoming, from: stored) { timer, date in
                try timer.restart(at: date)
            }
        default:
            return false
        }
    }

    private static func matchesMetadataUpdate(_ incoming: TimerItem, from stored: TimerItem) -> Bool {
        do {
            var expected = stored
            try expected.updateMetadata(title: incoming.title, details: incoming.details, tags: incoming.tags)
            return expected == incoming
        } catch {
            return false
        }
    }

    private static func matchesTransition(
        _ incoming: TimerItem,
        from stored: TimerItem,
        operation: (inout TimerItem, Date) throws -> Void
    ) -> Bool {
        guard let date = incoming.lastTransitionAt else { return false }
        do {
            var expected = stored
            try operation(&expected, date)
            return expected == incoming
        } catch {
            return false
        }
    }

    private static func apply(_ history: HistoryEntry, to record: HistoryRecord) throws {
        record.id = history.id
        record.timerID = history.timerID
        record.occurrenceID = history.occurrenceID
        record.endedAt = history.endedAt
        record.deletedAt = history.deletedAt
        record.payload = try TimerPayloadCodec.encodeHistory(history)
    }

    private func updateHistoryDeletion(_ id: UUID, deletedAt: Date?, onlyWhenDeleted: Bool) async throws {
        try await store.perform { context in
            do {
                let record = try Self.historyRecord(id: id, in: context)
                let stored = try TimerPayloadCodec.decodeHistory(record.payload)
                guard (stored.deletedAt != nil) == onlyWhenDeleted else { return }
                let updated = try Self.history(from: stored, deletedAt: deletedAt)
                try Self.apply(updated, to: record)
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    private static func historyRangePredicate(from: Date?, through: Date?, excludingDeleted: Bool) -> NSPredicate {
        var predicates = [NSPredicate]()
        if excludingDeleted {
            predicates.append(NSPredicate(format: "deletedAt == nil"))
        }
        if let from {
            predicates.append(NSPredicate(format: "endedAt >= %@", from as NSDate))
        }
        if let through {
            predicates.append(NSPredicate(format: "endedAt <= %@", through as NSDate))
        }
        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    private static func matchesSearch(_ history: HistoryEntry, query: String) -> Bool {
        let normalizedQuery = normalizeSearchValue(query)
        guard !normalizedQuery.isEmpty else { return true }
        return ([history.title, history.details] + history.tags).contains {
            normalizeSearchValue($0).contains(normalizedQuery)
        }
    }

    private static func normalizeSearchValue(_ value: String) -> String {
        value
            .precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func validateHistoryUpdate(_ incoming: HistoryEntry, against stored: HistoryEntry) throws {
        guard stored.deletedAt == nil,
              incoming.deletedAt == nil,
              incoming.id == stored.id,
              incoming.timerID == stored.timerID,
              incoming.occurrenceID == stored.occurrenceID,
              incoming.kind == stored.kind,
              incoming.startedAt == stored.startedAt,
              incoming.endedAt == stored.endedAt,
              incoming.elapsedSeconds == stored.elapsedSeconds,
              incoming.completionReason == stored.completionReason else {
            throw TimerRepositoryError.staleHistoryUpdate
        }
    }

    private static func history(from existing: HistoryEntry, deletedAt: Date?) throws -> HistoryEntry {
        try HistoryEntry(
            id: existing.id,
            timerID: existing.timerID,
            occurrenceID: existing.occurrenceID,
            title: existing.title,
            details: existing.details,
            tags: existing.tags,
            kind: existing.kind,
            startedAt: existing.startedAt,
            endedAt: existing.endedAt,
            elapsedSeconds: existing.elapsedSeconds,
            completionReason: existing.completionReason,
            deletedAt: deletedAt
        )
    }

    private static func history(for timer: TimerItem, at date: Date, reason: CompletionReason = .finished) throws -> HistoryEntry {
        let elapsed: TimeInterval
        switch timer.kind {
        case .countdown:
            let duration = timer.duration ?? 0
            elapsed = reason == .cancelled ? max(0, duration - (timer.remaining ?? 0)) : duration
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
            completionReason: reason
        )
    }

}
