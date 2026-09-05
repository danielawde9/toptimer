@preconcurrency import CoreData
import Foundation

@objc(TimerRecord)
final class TimerRecord: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var occurrenceID: UUID
    @NSManaged var predecessorOccurrenceID: UUID?
    @NSManaged var predecessorKey: String?
    @NSManaged var state: String
    @NSManaged var deadline: Date?
    @NSManaged var createdAt: Date
    @NSManaged var completedAt: Date?
    @NSManaged var deletedAt: Date?
    @NSManaged var payload: Data
}

@objc(HistoryRecord)
final class HistoryRecord: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var timerID: UUID
    @NSManaged var occurrenceID: UUID
    @NSManaged var endedAt: Date
    @NSManaged var deletedAt: Date?
    @NSManaged var payload: Data
}

@objc(PresetRecord)
final class PresetRecord: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var createdAt: Date
    @NSManaged var deletedAt: Date?
    @NSManaged var payload: Data
}

enum TopTimerCoreDataModel {
    static let model = makeModel(identifier: "TopTimerModelV2", legacy: false)
    static let v1Model = makeModel(identifier: "TopTimerModelV1", legacy: true)

    private static func makeModel(identifier: String, legacy: Bool) -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        model.versionIdentifiers = [identifier]
        model.entities = [timerEntity(legacy: legacy), historyEntity(legacy: legacy), presetEntity(legacy: legacy)]
        return model
    }

    private static func timerEntity(legacy: Bool) -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "TimerRecord"
        entity.managedObjectClassName = legacy ? NSStringFromClass(NSManagedObject.self) : NSStringFromClass(TimerRecord.self)
        var properties = [
            attribute("id", .UUIDAttributeType, optional: false),
            attribute("occurrenceID", .UUIDAttributeType, optional: false),
            attribute("predecessorOccurrenceID", .UUIDAttributeType, optional: true),
            attribute("state", .stringAttributeType, optional: false),
            attribute("deadline", .dateAttributeType, optional: true),
            attribute("createdAt", .dateAttributeType, optional: false),
            attribute("completedAt", .dateAttributeType, optional: true),
            attribute("deletedAt", .dateAttributeType, optional: true),
            attribute("payload", .binaryDataAttributeType, optional: false)
        ]
        if legacy {
            properties.insert(attribute("predecessorKey", .stringAttributeType, optional: true), at: 3)
        }
        entity.properties = properties
        entity.uniquenessConstraints = legacy
            ? [["id"], ["occurrenceID"], ["predecessorKey"]]
            : [["id"], ["occurrenceID"], ["predecessorOccurrenceID"]]
        entity.indexes = [
            index("timer_active", entity, ["deletedAt", "state", "deadline", "createdAt", "id"]),
            index("timer_active_page", entity, ["deletedAt", "state", "createdAt", "id"]),
            index("timer_predecessor", entity, [legacy ? "predecessorKey" : "predecessorOccurrenceID"])
        ]
        return entity
    }

    private static func historyEntity(legacy: Bool) -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "HistoryRecord"
        entity.managedObjectClassName = legacy ? NSStringFromClass(NSManagedObject.self) : NSStringFromClass(HistoryRecord.self)
        entity.properties = [
            attribute("id", .UUIDAttributeType, optional: false),
            attribute("timerID", .UUIDAttributeType, optional: false),
            attribute("occurrenceID", .UUIDAttributeType, optional: false),
            attribute("endedAt", .dateAttributeType, optional: false),
            attribute("deletedAt", .dateAttributeType, optional: true),
            attribute("payload", .binaryDataAttributeType, optional: false)
        ]
        entity.uniquenessConstraints = [["id"], ["occurrenceID"]]
        entity.indexes = [index("history_timeline", entity, ["timerID", "deletedAt", "endedAt", "id"])]
        return entity
    }

    private static func presetEntity(legacy: Bool) -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "PresetRecord"
        entity.managedObjectClassName = legacy ? NSStringFromClass(NSManagedObject.self) : NSStringFromClass(PresetRecord.self)
        entity.properties = [
            attribute("id", .UUIDAttributeType, optional: false),
            attribute("createdAt", .dateAttributeType, optional: false),
            attribute("deletedAt", .dateAttributeType, optional: true),
            attribute("payload", .binaryDataAttributeType, optional: false)
        ]
        entity.uniquenessConstraints = [["id"]]
        entity.indexes = [index("preset_recovery", entity, ["createdAt", "deletedAt"])]
        return entity
    }

    private static func attribute(
        _ name: String,
        _ type: NSAttributeType,
        optional: Bool
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = optional
        return attribute
    }

    private static func index(
        _ name: String,
        _ entity: NSEntityDescription,
        _ propertyNames: [String]
    ) -> NSFetchIndexDescription {
        let elements = propertyNames.compactMap { propertyName in
            entity.propertiesByName[propertyName].map {
                NSFetchIndexElementDescription(property: $0, collationType: .binary)
            }
        }
        return NSFetchIndexDescription(name: name, elements: elements)
    }
}
