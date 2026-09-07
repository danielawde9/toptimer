@preconcurrency import CoreData
import Foundation

public struct TimerPreset: Codable, Equatable, Sendable, Identifiable {
    public static let maximumCommandLength = 500
    public static let maximumTagCount = 20
    public static let maximumTagLength = 64
    public let id: UUID
    public let command: String
    public let commandKey: String
    public let tags: [String]
    public let useCount: UInt
    public let createdAt: Date
    public let lastUsed: Date
    public let deletedAt: Date?

    private enum CodingKeys: String, CodingKey, CaseIterable { case id, command, commandKey, tags, useCount, createdAt, lastUsed, deletedAt }

    public init(id: UUID = UUID(), command: String, tags: [String], useCount: UInt = 1, createdAt: Date, lastUsed: Date, deletedAt: Date? = nil) throws {
        let display = try Self.validatedDisplay(command)
        let normalizedTags = try Self.validatedTags(tags)
        try Self.validateDates(createdAt: createdAt, lastUsed: lastUsed, deletedAt: deletedAt)
        guard useCount >= 1 else { throw TimerRepositoryError.malformedPayload }
        self.id = id
        self.command = display
        commandKey = Self.key(display)
        self.tags = normalizedTags
        self.useCount = useCount
        self.createdAt = createdAt
        self.lastUsed = lastUsed
        self.deletedAt = deletedAt
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: AnyCodingKey.self)
        guard Set(raw.allKeys.map(\.stringValue)) == Set(CodingKeys.allCases.map(\.rawValue)) else { throw TimerRepositoryError.malformedPayload }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let command = try container.decode(String.self, forKey: .command)
        let commandKey = try container.decode(String.self, forKey: .commandKey)
        let tags = try container.decode([String].self, forKey: .tags)
        let useCount = try container.decode(UInt.self, forKey: .useCount)
        let createdAt = try container.decode(Date.self, forKey: .createdAt)
        let lastUsed = try container.decode(Date.self, forKey: .lastUsed)
        let deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        let validated = try TimerPreset(id: id, command: command, tags: tags, useCount: useCount, createdAt: createdAt, lastUsed: lastUsed, deletedAt: deletedAt)
        guard command == validated.command, commandKey == validated.commandKey, tags == validated.tags else { throw TimerRepositoryError.malformedPayload }
        self = validated
    }

    public func encode(to encoder: Encoder) throws {
        let validated = try TimerPreset(id: id, command: command, tags: tags, useCount: useCount, createdAt: createdAt, lastUsed: lastUsed, deletedAt: deletedAt)
        guard self == validated else { throw TimerRepositoryError.malformedPayload }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id); try container.encode(command, forKey: .command); try container.encode(commandKey, forKey: .commandKey)
        try container.encode(tags, forKey: .tags); try container.encode(useCount, forKey: .useCount); try container.encode(createdAt, forKey: .createdAt); try container.encode(lastUsed, forKey: .lastUsed); try container.encode(deletedAt, forKey: .deletedAt)
    }

    static func display(_ value: String) -> String { value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
    static func key(_ value: String) -> String { value.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX")) }
    static func normalizedTags(_ values: [String]) -> [String] {
        Array(Set(values.map { key(display($0)) }.filter { !$0.isEmpty })).sorted()
    }

    private static func validatedDisplay(_ value: String) throws -> String {
        let display = display(value)
        guard !display.isEmpty, display.count <= maximumCommandLength else { throw TimerRepositoryError.malformedPayload }
        return display
    }

    private static func validatedTags(_ values: [String]) throws -> [String] {
        guard values.count <= maximumTagCount else { throw TimerRepositoryError.malformedPayload }
        let normalized = normalizedTags(values)
        guard normalized.count <= maximumTagCount, normalized.allSatisfy({ $0.count <= maximumTagLength }) else { throw TimerRepositoryError.malformedPayload }
        return normalized
    }

    private static func validateDates(createdAt: Date, lastUsed: Date, deletedAt: Date?) throws {
        guard createdAt.timeIntervalSinceReferenceDate.isFinite, lastUsed.timeIntervalSinceReferenceDate.isFinite, lastUsed >= createdAt else { throw TimerRepositoryError.malformedPayload }
        guard deletedAt?.timeIntervalSinceReferenceDate.isFinite ?? true, deletedAt.map({ $0 >= lastUsed }) ?? true else { throw TimerRepositoryError.malformedPayload }
    }
}

public protocol PresetRepository: Sendable {
    func record(command: String, tags: [String], at: Date) async throws -> TimerPreset
    func suggestions(query: String, limit: Int) async throws -> [TimerPreset]
    func softDeletePreset(_ id: UUID, at: Date) async throws
    func recoverPreset(_ id: UUID) async throws
}

public enum PresetPayloadCodec {
    private struct Envelope: Codable {
        let version: Int; let payload: Data
        private enum CodingKeys: String, CodingKey, CaseIterable { case version, payload }
        init(version: Int, payload: Data) { self.version = version; self.payload = payload }
        init(from decoder: Decoder) throws {
            let raw = try decoder.container(keyedBy: AnyCodingKey.self)
            guard Set(raw.allKeys.map(\.stringValue)) == Set(CodingKeys.allCases.map(\.rawValue)) else { throw TimerRepositoryError.malformedPayload }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decode(Int.self, forKey: .version)
            payload = try container.decode(Data.self, forKey: .payload)
        }
    }
    private static let version = 1
    public static func encode(_ preset: TimerPreset) throws -> Data {
        try encoder.encode(Envelope(version: version, payload: try encoder.encode(preset)))
    }
    public static func decode(_ data: Data) throws -> TimerPreset {
        let envelope: Envelope
        do { envelope = try decoder.decode(Envelope.self, from: data) } catch { throw TimerRepositoryError.malformedPayload }
        guard envelope.version == version else { throw TimerRepositoryError.unsupportedPayloadVersion(envelope.version) }
        do { return try decoder.decode(TimerPreset.self, from: envelope.payload) } catch { throw TimerRepositoryError.malformedPayload }
    }
    private static let encoder: JSONEncoder = { let value = JSONEncoder(); value.outputFormatting = [.sortedKeys]; value.dateEncodingStrategy = .millisecondsSince1970; value.dataEncodingStrategy = .base64; return value }()
    private static let decoder: JSONDecoder = { let value = JSONDecoder(); value.dateDecodingStrategy = .millisecondsSince1970; value.dataDecodingStrategy = .base64; return value }()
}

private struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?
    init?(stringValue: String) { self.stringValue = stringValue; intValue = nil }
    init?(intValue: Int) { stringValue = String(intValue); self.intValue = intValue }
}

public actor PresetCoreDataRepository: PresetRepository {
    private static let defaultMaximumActivePresets = 10_000
    private let store: CoreDataStore
    private let maximumActivePresets: Int
    public init(store: CoreDataStore, maximumActivePresets: Int = 10_000) { self.store = store; self.maximumActivePresets = max(1, maximumActivePresets) }

    public func record(command: String, tags: [String], at date: Date) async throws -> TimerPreset {
        let candidate = try TimerPreset(command: command, tags: tags, createdAt: date, lastUsed: date)
        let maximum = maximumActivePresets
        return try await store.perform { context in
            do {
                let records = try Self.fetch(context, predicate: NSPredicate(format: "deletedAt == nil"), limit: maximum + 1)
                guard records.count <= maximum else { throw TimerRepositoryError.presetCapacityReached }
                let activeCount = records.count
                if let record = try records.first(where: { record in
                    let preset = try PresetPayloadCodec.decode(record.payload)
                    return preset.commandKey == candidate.commandKey && preset.tags == candidate.tags
                }) {
                    let old = try PresetPayloadCodec.decode(record.payload)
                    guard old.useCount < UInt.max else { throw TimerRepositoryError.presetUseCountOverflow }
                    let updated = try TimerPreset(id: old.id, command: candidate.command, tags: candidate.tags, useCount: old.useCount + 1, createdAt: old.createdAt, lastUsed: date)
                    record.createdAt = updated.createdAt; record.deletedAt = nil; record.payload = try PresetPayloadCodec.encode(updated)
                    try context.save(); return updated
                }
                guard activeCount < maximum else { throw TimerRepositoryError.presetCapacityReached }
                let record = PresetRecord(context: context)
                record.id = candidate.id; record.createdAt = candidate.createdAt; record.deletedAt = nil; record.payload = try PresetPayloadCodec.encode(candidate)
                try context.save(); return candidate
            } catch { context.rollback(); throw error }
        }
    }

    public func suggestions(query: String, limit: Int) async throws -> [TimerPreset] {
        guard query.count <= 2_048 else { throw TimerRepositoryError.invalidPresetQuery }
        let cap = min(20, max(1, limit)); let tokens = TimerPreset.normalizedTags(query.split(whereSeparator: { $0.isWhitespace }).map(String.init))
        guard tokens.count <= 12 else { throw TimerRepositoryError.invalidPresetQuery }
        let maximum = maximumActivePresets
        return try await store.perform { context in
            let records = try Self.fetch(context, predicate: NSPredicate(format: "deletedAt == nil"), limit: maximum + 1)
            guard records.count <= maximum else { throw TimerRepositoryError.presetCapacityReached }
            let values = try records.map { try PresetPayloadCodec.decode($0.payload) }
            return values.sorted { left, right in
                let lMatch = tokens.contains { token in left.tags.contains { $0.hasPrefix(token) } }
                let rMatch = tokens.contains { token in right.tags.contains { $0.hasPrefix(token) } }
                if lMatch != rMatch { return lMatch }
                if left.useCount != right.useCount { return left.useCount > right.useCount }
                if left.lastUsed != right.lastUsed { return left.lastUsed > right.lastUsed }
                if left.commandKey != right.commandKey { return left.commandKey < right.commandKey }
                return left.id.uuidString < right.id.uuidString
            }.prefix(cap).map { $0 }
        }
    }

    public func softDeletePreset(_ id: UUID, at date: Date) async throws { try await setDeleted(id, date) }
    public func recoverPreset(_ id: UUID) async throws { try await setDeleted(id, nil) }
    private func setDeleted(_ id: UUID, _ date: Date?) async throws {
        let maximum = maximumActivePresets
        try await store.perform { context in
            do { guard let record = try Self.fetch(context, predicate: NSPredicate(format: "id == %@", id as NSUUID), limit: 1).first else { throw TimerRepositoryError.timerNotFound }; let old = try PresetPayloadCodec.decode(record.payload); if old.deletedAt != nil && date != nil { return }; if old.deletedAt == nil && date == nil { return }; if date == nil { let active = try Self.fetch(context, predicate: NSPredicate(format: "deletedAt == nil"), limit: maximum + 1); guard active.count < maximum else { throw TimerRepositoryError.presetCapacityReached } }; let updated = try TimerPreset(id: old.id, command: old.command, tags: old.tags, useCount: old.useCount, createdAt: old.createdAt, lastUsed: old.lastUsed, deletedAt: date); record.deletedAt = date; record.payload = try PresetPayloadCodec.encode(updated); try context.save() } catch { context.rollback(); throw error }
        }
    }
    private static func fetch(_ context: NSManagedObjectContext, predicate: NSPredicate, limit: Int) throws -> [PresetRecord] { let request = NSFetchRequest<PresetRecord>(entityName: "PresetRecord"); request.predicate = predicate; request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true), NSSortDescriptor(key: "id", ascending: true)]; request.fetchLimit = limit; return try context.fetch(request) }
}
