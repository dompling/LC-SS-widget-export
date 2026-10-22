//
//  BaseEntity.swift
//  AltStore
//
//  Created by Magesh K on 28/01/25.
//  Copyright © 2025 SideStore. All rights reserved.
//

import CoreData

@objc public enum SerializationFormat: Int {
    case json
    case plist
}

public class BaseEntity: NSManagedObject, Fetchable
{
    @nonobjc class func fetchRequest<T>() -> NSFetchRequest<T>
    {
        fatalError("method not implemented, subclass needs to provide an implementation")
    }

    internal override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
        
//        debugLog("\(BaseEntity.self):\(type(of: self)): Inserting: \(entity.name ?? "nil") into context: \(String(describing: context))")
    }
    
    @objc(serializeWithFormat:)
    public func serialize(format: SerializationFormat) -> Data? {
        verboseLog("[BaseEntity] serialize(format: \(format)) started for \(self.entity.name ?? "Entity")")
        let dict = self.serializeToDictionary(format: format)
        
        switch format {
        case .json:
            return try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
        case .plist:
            return try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        }
    }
    
    @objc(serializeToStringWithFormat:)
    public func serializeToString(format: SerializationFormat) -> String? {
        guard let data = self.serialize(format: format) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    @objc(deserializeFromData:format:context:)
    public class func deserialize(from data: Data, format: SerializationFormat, context: NSManagedObjectContext) -> BaseEntity? {
        verboseLog("[BaseEntity] deserialize(from:format: \(format)) started for \(self.entity().name ?? "Entity")")
        let parsedDict: [String: Any]?
        switch format {
        case .json:
            parsedDict = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any]
        case .plist:
            parsedDict = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
        }
        
        guard let dict = parsedDict else {
            debugLog("[BaseEntity] deserialize failed: unable to parse data to dictionary for \(self.entity().name ?? "Entity")")
            return nil
        }
        return self.restore(from: dict, context: context)
    }
    
    @objc(deserializeFromString:format:context:)
    public class func deserialize(from string: String, format: SerializationFormat, context: NSManagedObjectContext) -> BaseEntity? {
        guard let data = string.data(using: .utf8) else { return nil }
        return self.deserialize(from: data, format: format, context: context)
    }
    
    // Internal helper that serializes to a raw dictionary
    private func serializeToDictionary(format: SerializationFormat) -> [String: Any] {
        verboseLog("[BaseEntity] serializeToDictionary started for \(self.entity.name ?? "Entity")")
        var dictionary = [String: Any]()
        
        // 1. Serialize primitive attributes
        for (name, attribute) in self.entity.attributesByName {
            guard !attribute.isTransient else { continue }
            if let value = self.value(forKey: name) {
                if format == .json, let dateValue = value as? Date {
                    dictionary[name] = ["$date": dateValue.timeIntervalSince1970]
                } else {
                    dictionary[name] = value
                }
            }
        }
        
        // 2. Traverse and serialize relationships
        for (name, relationship) in self.entity.relationshipsByName {
            guard !relationship.isTransient else { continue }
            
            // Avoid loop: Skip inverse relationship if the parent owns us via Cascade delete rule
            if let inverse = relationship.inverseRelationship, inverse.deleteRule == .cascadeDeleteRule {
                verboseLog("[BaseEntity] Skipping inverse relationship loop: \(name) for \(self.entity.name ?? "Entity")")
                continue
            }
            
            if let value = self.value(forKey: name) {
                if relationship.isToMany {
                    if let set = value as? Set<NSManagedObject> {
                        if relationship.deleteRule == .cascadeDeleteRule {
                            // Composition (Owned): Serialize recursively by value
                            verboseLog("[BaseEntity] Serializing composition to-many relationship recursively: \(name)")
                            dictionary[name] = set.compactMap { ($0 as? BaseEntity)?.serializeToDictionary(format: format) }
                        } else {
                            // Association (Referenced): Serialize only lookup keys
                            verboseLog("[BaseEntity] Serializing association to-many relationship keys: \(name)")
                            dictionary[name] = set.map { ($0 as! BaseEntity).referenceKeysRepresentation(format: format) }
                        }
                    }
                } else {
                    if let object = value as? NSManagedObject {
                        if relationship.deleteRule == .cascadeDeleteRule {
                            // Composition (Owned): Serialize recursively by value
                            verboseLog("[BaseEntity] Serializing composition to-one relationship recursively: \(name)")
                            dictionary[name] = (object as? BaseEntity)?.serializeToDictionary(format: format)
                        } else {
                            // Association (Referenced): Serialize only lookup keys
                            verboseLog("[BaseEntity] Serializing association to-one relationship keys: \(name)")
                            dictionary[name] = (object as! BaseEntity).referenceKeysRepresentation(format: format)
                        }
                    }
                }
            }
        }
        
        verboseLog("[BaseEntity] serializeToDictionary completed for \(self.entity.name ?? "Entity")")
        return dictionary
    }
    
    // Helper to generate the minimum lookup key(s) for a referenced entity
    private func referenceKeysRepresentation(format: SerializationFormat) -> [String: Any] {
        var keys = [String: Any]()
        let entity = self.entity
        
        // Use uniqueness constraints if defined
        if let constraints = entity.uniquenessConstraints as? [[String]] {
            for constraintGroup in constraints {
                for keyName in constraintGroup {
                    if let val = self.value(forKey: keyName) {
                        if format == .json, let dateVal = val as? Date {
                            keys[keyName] = ["$date": dateVal.timeIntervalSince1970]
                        } else {
                            keys[keyName] = val
                        }
                    }
                }
            }
        }
        
        // Fallback identifier keys
        if keys.isEmpty {
            for keyName in ["identifier", "bundleIdentifier"] {
                if entity.attributesByName[keyName] != nil, let val = self.value(forKey: keyName) {
                    if format == .json, let dateVal = val as? Date {
                        keys[keyName] = ["$date": dateVal.timeIntervalSince1970]
                    } else {
                        keys[keyName] = val
                    }
                }
            }
        }
        
        return keys
    }
    
    // Internal helper that restores from a raw dictionary
    internal class func restore(from dictionary: [String: Any], context: NSManagedObjectContext) -> BaseEntity? {
        let entityDesc = self.entity()
        guard let entityName = entityDesc.name else { return nil }
        verboseLog("[BaseEntity] restore(from:context:) started for \(entityName)")
        
        var lookupKeys = [String: Any]()
        if let constraints = entityDesc.uniquenessConstraints as? [[String]] {
            for constraintGroup in constraints {
                for keyName in constraintGroup {
                    if let val = dictionary[keyName] {
                        lookupKeys[keyName] = val
                    }
                }
            }
        }
        
        let object: BaseEntity
        if !lookupKeys.isEmpty, let existing = self.fetchExisting(matching: lookupKeys, context: context) {
            debugLog("[BaseEntity] restore: found existing \(entityName) matching unique constraints \(lookupKeys). Reusing in-place.")
            object = existing
        } else {
            debugLog("[BaseEntity] restore: no existing \(entityName) found matching unique constraints \(lookupKeys). Inserting new object.")
            object = NSEntityDescription.insertNewObject(forEntityName: entityName, into: context) as! BaseEntity
        }
        
        // Populate attributes
        for (name, attribute) in entityDesc.attributesByName {
            guard !attribute.isTransient else { continue }
            if let value = dictionary[name] {
                object.setValue(self.unwrapJsonValue(value), forKey: name)
            }
        }
        
        // Reconstruct relationships
        for (name, relationship) in entityDesc.relationshipsByName {
            guard !relationship.isTransient else { continue }
            
            // Skip inverse relationship back to the parent to prevent loops
            if let inverse = relationship.inverseRelationship, inverse.deleteRule == .cascadeDeleteRule {
                verboseLog("[BaseEntity] restore: skipping inverse relationship \(name) to prevent loops")
                continue
            }
            
            guard let relationData = dictionary[name] else { continue }
            
            guard let destClassName = relationship.destinationEntity?.managedObjectClassName,
                  let destinationClass = NSClassFromString(destClassName) as? BaseEntity.Type else {
                continue
            }
            
            if relationship.isToMany {
                if let array = relationData as? [[String: Any]] {
                    verboseLog("[BaseEntity] restore: processing to-many relationship \(name) for \(entityName) with \(array.count) items")
                    var childObjects = Set<NSManagedObject>()
                    for childDict in array {
                        if relationship.deleteRule == .cascadeDeleteRule {
                            // Composition: Restore child recursively
                            if let child = destinationClass.restore(from: childDict, context: context) {
                                if let inverseName = relationship.inverseRelationship?.name {
                                    child.setValue(object, forKey: inverseName)
                                }
                                childObjects.insert(child)
                            }
                        } else {
                            // Association: Match existing child by keys
                            if let child = destinationClass.fetchExisting(matching: childDict, context: context) {
                                childObjects.insert(child)
                            } else {
                                verboseLog("[BaseEntity] restore: association child for to-many relationship \(name) not found matching \(childDict)")
                            }
                        }
                    }
                    object.setValue(childObjects, forKey: name)
                }
            } else {
                if let childDict = relationData as? [String: Any] {
                    verboseLog("[BaseEntity] restore: processing to-one relationship \(name) for \(entityName)")
                    if relationship.deleteRule == .cascadeDeleteRule {
                        // Composition: Restore child recursively
                        if let child = destinationClass.restore(from: childDict, context: context) {
                            if let inverseName = relationship.inverseRelationship?.name {
                                child.setValue(object, forKey: inverseName)
                            }
                            object.setValue(child, forKey: name)
                        }
                    } else {
                        // Association: Match existing child by keys
                        if let child = destinationClass.fetchExisting(matching: childDict, context: context) {
                            object.setValue(child, forKey: name)
                        } else {
                            verboseLog("[BaseEntity] restore: association child for to-one relationship \(name) not found matching \(childDict)")
                        }
                    }
                }
            }
        }
        
        verboseLog("[BaseEntity] restore completed successfully for \(entityName)")
        return object
    }
    
    private class func fetchExisting(matching keys: [String: Any], context: NSManagedObjectContext) -> BaseEntity? {
        let entityName = self.entity().name!
        verboseLog("[BaseEntity] fetchExisting matching keys \(keys) started for \(entityName)")
        var predicates = [NSPredicate]()
        for (key, val) in keys {
            let unwrapped = self.unwrapJsonValue(val)
            predicates.append(NSPredicate(format: "%K == %@", key, unwrapped as! CVarArg))
        }
        guard !predicates.isEmpty else {
            verboseLog("[BaseEntity] fetchExisting for \(entityName): empty lookup keys, returning nil")
            return nil
        }
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        let results = try? context.fetch(fetchRequest) as? [BaseEntity]
        verboseLog("[BaseEntity] fetchExisting for \(entityName) matching \(keys) result: \(results?.first != nil ? "FOUND" : "NOT FOUND")")
        return results?.first
    }
    
    private class func unwrapJsonValue(_ value: Any) -> Any {
        if let dict = value as? [String: Any], let timeInterval = dict["$date"] as? TimeInterval {
            return Date(timeIntervalSince1970: timeInterval)
        }
        return value
    }
}
