@preconcurrency import CoreData
import Foundation

public enum CoreDataStoreError: Error, Equatable, Sendable {
    case persistentStoreLoadFailed(String)
}

public final class CoreDataStore: @unchecked Sendable {
    private let container: NSPersistentContainer
    let context: NSManagedObjectContext

    private init(description: NSPersistentStoreDescription) async throws {
        container = NSPersistentContainer(name: "TopTimer", managedObjectModel: TopTimerCoreDataModel.model)
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
        let description = NSPersistentStoreDescription(url: url)
        description.type = NSSQLiteStoreType
        description.shouldAddStoreAsynchronously = false
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        return try await CoreDataStore(description: description)
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

    private static func load(container: NSPersistentContainer) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            container.loadPersistentStores { _, error in
                if let error {
                    continuation.resume(throwing: CoreDataStoreError.persistentStoreLoadFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
