#if DEBUG
import CoreData
import SwiftData

/// Opt-in developer operation (`-initializeCloudKitSchema`), never part of a release build.
/// Uses Apple's SwiftData/Core Data bridge to include every field, even for unused model types.
/// Run on a development-signed device, then review/deploy the schema in CloudKit Console.
@MainActor
enum CloudKitSchemaInitializer {
    static func initialize(configuration: ModelConfiguration) throws {
        try autoreleasepool {
            guard let model = NSManagedObjectModel.makeManagedObjectModel(for: AppSchema.models) else {
                throw CocoaError(.persistentStoreInvalidType)
            }
            let description = NSPersistentStoreDescription(url: configuration.url)
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: iCloudSyncManager.containerIdentifier)
            description.shouldAddStoreAsynchronously = false
            let container = NSPersistentCloudKitContainer(name: "LibrarySchema", managedObjectModel: model)
            container.persistentStoreDescriptions = [description]
            // Always unload, including an initialization failure, before the caller removes the temporary store.
            defer {
                for store in container.persistentStoreCoordinator.persistentStores {
                    try? container.persistentStoreCoordinator.remove(store)
                }
            }
            var loadError: Error?
            container.loadPersistentStores { _, error in loadError = error }
            if let loadError { throw loadError }
            try container.initializeCloudKitSchema()
        }
    }
}
#endif
