//
//  PreviewModelContainer.swift
//  ShutterManager
//
//  Isolated SwiftData storage for Xcode previews.
//

import SwiftData

/// Builds a fresh, in-memory container for Xcode previews.
///
/// Preview containers must opt out of CloudKit explicitly: an in-memory store cannot mirror to
/// CloudKit, and previews should never open the app's persistent store. Registering the complete
/// model graph also keeps relationship-backed previews from depending on which root types a
/// particular view happened to list.
enum PreviewModelContainer {
    @MainActor
    static func make() -> ModelContainer {
        let schema = AppSchema.schema
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("Unable to create preview ModelContainer: \(error)")
        }
    }
}
