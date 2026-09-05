@preconcurrency import CoreData
import Foundation

public enum CoreDataStoreError: Error, Equatable, Sendable {
    case persistentStoreLoadFailed(domain: String, code: Int, description: String)
    case migrationFailed(domain: String, code: Int, description: String)
    case unsupportedStoreModel
}

public final class CoreDataStore: @unchecked Sendable {
    private let container: NSPersistentContainer
    private let context: NSManagedObjectContext

    // The context never leaves this object and every access is scheduled through
    // perform(_:), which is the invariant behind this narrow unchecked boundary.
    private init(description: NSPersistentStoreDescription, model: NSManagedObjectModel = TopTimerCoreDataModel.model) async throws {
        container = NSPersistentContainer(name: "TopTimer", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]
        try await Self.load(container: container)
        context = container.newBackgroundContext()
        context.mergePolicy = NSMergePolicy.error
        context.undoManager = nil
    }

    public static func inMemory() async throws -> CoreDataStore {
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.shouldAddStoreAsynchronously = false
        return try await CoreDataStore(description: description)
    }

    public static func sqlite(at url: URL) async throws -> CoreDataStore {
        try migrateIfNeeded(at: url)
        let description = sqliteDescription(at: url)
        return try await CoreDataStore(description: description)
    }

    static func legacyV1SQLite(at url: URL) async throws -> CoreDataStore {
        let description = sqliteDescription(at: url)
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        return try await CoreDataStore(description: description, model: TopTimerCoreDataModel.v1Model)
    }

    static func sqliteDescription(at url: URL) -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription(url: url)
        description.type = NSSQLiteStoreType
        description.shouldAddStoreAsynchronously = false
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        return description
    }

    func perform<Value: Sendable>(
        _ work: @escaping @Sendable (NSManagedObjectContext) throws -> Value
    ) async throws -> Value {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Value, Error>) in
            context.perform {
                do {
                    continuation.resume(returning: try work(self.context))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func close() async throws {
        try await perform { context in
            guard let coordinator = context.persistentStoreCoordinator else { return }
            for store in coordinator.persistentStores {
                try coordinator.remove(store)
            }
        }
    }

    private static func load(container: NSPersistentContainer) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            container.loadPersistentStores { _, error in
                if let error {
                    let failure = error as NSError
                    continuation.resume(throwing: CoreDataStoreError.persistentStoreLoadFailed(
                        domain: failure.domain,
                        code: failure.code,
                        description: errorDescription(for: failure)
                    ))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private static func migrateIfNeeded(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: url)
            if TopTimerCoreDataModel.model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) {
                return
            }
            guard TopTimerCoreDataModel.v1Model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) else {
                throw CoreDataStoreError.unsupportedStoreModel
            }
            let mapping = try NSMappingModel.inferredMappingModel(
                forSourceModel: TopTimerCoreDataModel.v1Model,
                destinationModel: TopTimerCoreDataModel.model
            )
            let temporaryURL = url.deletingLastPathComponent()
                .appendingPathComponent("TopTimer-migration-\(UUID().uuidString).sqlite")
            defer { try? FileManager.default.removeItem(at: temporaryURL) }
            let manager = NSMigrationManager(
                sourceModel: TopTimerCoreDataModel.v1Model,
                destinationModel: TopTimerCoreDataModel.model
            )
            try manager.migrateStore(
                from: url,
                sourceType: NSSQLiteStoreType,
                options: [NSPersistentHistoryTrackingKey: true],
                with: mapping,
                toDestinationURL: temporaryURL,
                destinationType: NSSQLiteStoreType,
                destinationOptions: [NSPersistentHistoryTrackingKey: true]
            )
            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: TopTimerCoreDataModel.model)
            try coordinator.replacePersistentStore(
                at: url,
                destinationOptions: nil,
                withPersistentStoreFrom: temporaryURL,
                sourceOptions: nil,
                ofType: NSSQLiteStoreType
            )
        } catch let error as CoreDataStoreError {
            throw error
        } catch {
            let failure = error as NSError
            throw CoreDataStoreError.migrationFailed(
                domain: failure.domain,
                code: failure.code,
                description: errorDescription(for: failure)
            )
        }
    }

    private static func errorDescription(for error: NSError) -> String {
        guard let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError else {
            return error.localizedDescription
        }
        return "\(error.localizedDescription) Underlying: \(underlying.domain) \(underlying.code) \(underlying.localizedDescription)"
    }
}
