@preconcurrency import CoreData
import Foundation

public struct TimerPreset: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let command: String
    public let commandKey: String
    public let tags: [String]
    public let useCount: UInt
    public let createdAt: Date
    public let lastUsed: Date
    public let deletedAt: Date?

    public init(id: UUID = UUID(), command: String, tags: [String], useCount: UInt = 1, createdAt: Date, lastUsed: Date, deletedAt: Date? = nil) throws {
        let display = Self.display(command)
        guard !display.isEmpty else { throw TimerRepositoryError.malformedPayload }
        self.id = id
        self.command = display
        commandKey = Self.key(display)
        self.tags = Self.normalizedTags(tags)
        self.useCount = useCount
        self.createdAt = createdAt
        self.lastUsed = lastUsed
        self.deletedAt = deletedAt
    }

    static func display(_ value: String) -> String { value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
    static func key(_ value: String) -> String { value.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current) }
    static func normalizedTags(_ values: [String]) -> [String] {
        Array(Set(values.map { key(display($0)) }.filter { !$0.isEmpty })).sorted()
    }
}

public protocol PresetRepository: Sendable {
    func record(command: String, tags: [String], at: Date) async throws -> TimerPreset
    func suggestions(query: String, limit: Int) async throws -> [TimerPreset]
    func softDeletePreset(_ id: UUID, at: Date) async throws
    func recoverPreset(_ id: UUID) async throws
}

public enum PresetPayloadCodec {
    private struct Envelope: Codable { let version: Int; let payload: Data }
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

public actor PresetCoreDataRepository: PresetRepository {
    private static let scanLimit = 10_000
    private let store: CoreDataStore
    public init(store: CoreDataStore) { self.store = store }

    public func record(command: String, tags: [String], at date: Date) async throws -> TimerPreset {
        let candidate = try TimerPreset(command: command, tags: tags, createdAt: date, lastUsed: date)
        return try await store.perform { context in
            do {
                let records = try Self.fetch(context)
                if let record = try records.first(where: { record in
                    let preset = try PresetPayloadCodec.decode(record.payload)
                    return preset.commandKey == candidate.commandKey && preset.tags == candidate.tags
                }) {
                    let old = try PresetPayloadCodec.decode(record.payload)
                    guard old.useCount < UInt.max else { throw TimerRepositoryError.malformedPayload }
                    let updated = try TimerPreset(id: old.id, command: candidate.command, tags: candidate.tags, useCount: old.useCount + 1, createdAt: old.createdAt, lastUsed: date)
                    record.createdAt = updated.createdAt; record.deletedAt = nil; record.payload = try PresetPayloadCodec.encode(updated)
                    try context.save(); return updated
                }
                let record = PresetRecord(context: context)
                record.id = candidate.id; record.createdAt = candidate.createdAt; record.deletedAt = nil; record.payload = try PresetPayloadCodec.encode(candidate)
                try context.save(); return candidate
            } catch { context.rollback(); throw error }
        }
    }

    public func suggestions(query: String, limit: Int) async throws -> [TimerPreset] {
        let cap = min(20, max(1, limit)); let tokens = TimerPreset.normalizedTags(query.split(whereSeparator: { $0.isWhitespace }).map(String.init))
        return try await store.perform { context in
            let values = try Self.fetch(context).compactMap { record -> TimerPreset? in let preset = try PresetPayloadCodec.decode(record.payload); return preset.deletedAt == nil ? preset : nil }
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
        try await store.perform { context in
            do { guard let record = try Self.fetch(context).first(where: { $0.id == id }) else { throw TimerRepositoryError.timerNotFound }; let old = try PresetPayloadCodec.decode(record.payload); let updated = try TimerPreset(id: old.id, command: old.command, tags: old.tags, useCount: old.useCount, createdAt: old.createdAt, lastUsed: old.lastUsed, deletedAt: date); record.deletedAt = date; record.payload = try PresetPayloadCodec.encode(updated); try context.save() } catch { context.rollback(); throw error }
        }
    }
    private static func fetch(_ context: NSManagedObjectContext) throws -> [PresetRecord] { let request = NSFetchRequest<PresetRecord>(entityName: "PresetRecord"); request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true), NSSortDescriptor(key: "id", ascending: true)]; request.fetchLimit = scanLimit; return try context.fetch(request) }
}
