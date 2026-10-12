//
//  AppStoreController.swift
//  ShutterManager
//
//  Opens the library: CloudKit first, then local-only, then recovery.
//

import Foundation
import SwiftData
import SwiftUI
import os

/// Opening a failed store never deletes it or substitutes an empty library.
@MainActor
final class AppStoreController: ObservableObject {
    @Published private(set) var container: ModelContainer?
    @Published private(set) var errorMessage: String?
    let storeURL: URL
    let syncManager: iCloudSyncManager
    private let makeContainer: (ModelConfiguration) throws -> ModelContainer

    static var isSchemaInitialization: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-initializeCloudKitSchema")
        #else
        false
        #endif
    }

    init(storeURL: URL? = nil,
         makeContainer: @escaping (ModelConfiguration) throws -> ModelContainer = {
             try ModelContainer(for: AppSchema.schema, configurations: $0)
         }) {
        let url = storeURL ?? ModelConfiguration(schema: AppSchema.schema, cloudKitDatabase: .none).url
        self.storeURL = url
        self.syncManager = iCloudSyncManager(storeURL: url)
        self.makeContainer = makeContainer
        retry()
    }

    func retry() {
        // Recovery only: replacing a live container would invalidate open editors and contexts.
        guard container == nil else { return }
        syncManager.configure(storageMode: .opening)
        do {
            try openLibrary()
            errorMessage = nil
        } catch {
            container = nil
            errorMessage = error.localizedDescription
            syncManager.configure(storageMode: .unavailable)
            Logger(subsystem: Constants.App.loggerSubsystem, category: "ModelContainer")
                .error("Library could not be opened: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func openLibrary() throws {
        #if DEBUG
        if Self.isSchemaInitialization {
            // Schema setup must not open a device's existing Production library in the
            // Development environment. Use an empty temporary store, then an in-memory UI.
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CloudKitSchema-\(UUID())")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            try CloudKitSchemaInitializer.initialize(configuration: ModelConfiguration(
                schema: AppSchema.schema, url: directory.appendingPathComponent("schema.store"),
                cloudKitDatabase: .private(iCloudSyncManager.containerIdentifier)))
            container = try ModelContainer(for: AppSchema.schema, configurations: ModelConfiguration(
                schema: AppSchema.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
            syncManager.configure(storageMode: .localOnly("Development schema initialized. This developer session uses a temporary library; the existing library was not opened."))
            Logger(subsystem: Constants.App.loggerSubsystem, category: "ModelContainer").notice("Development CloudKit schema initialized successfully.")
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-uiTestStoreFailure") {
            throw CocoaError(.fileReadCorruptFile)
        }
        // Unit tests build their own containers, so the app hosting them shouldn't open the
        // simulator's library or start CloudKit setup underneath them.
        if ProcessInfo.processInfo.arguments.contains("-uiTestInMemory")
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            let temporaryContainer = try ModelContainer(for: AppSchema.schema, configurations: ModelConfiguration(
                schema: AppSchema.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
            #if RELEASE_SCREENSHOTS
            if ReleaseScreenshotData.isEnabled {
                try ReleaseScreenshotData.seed(temporaryContainer.mainContext)
            }
            #endif
            container = temporaryContainer
            syncManager.configure(storageMode: .localOnly("This session uses a temporary library with iCloud disabled."))
            return
        }
        #endif
        // Both attempts explicitly open the SAME file. Local fallback must never create a
        // separate empty library, and its writes must remain available on the next cloud launch.
        let cloudConfiguration = ModelConfiguration(schema: AppSchema.schema, url: storeURL,
            cloudKitDatabase: .private(iCloudSyncManager.containerIdentifier))
        do {
            container = try makeContainer(cloudConfiguration)
            syncManager.configure(storageMode: .cloudKit)
        } catch {
            let reason = error.localizedDescription
            Logger(subsystem: Constants.App.loggerSubsystem, category: "ModelContainer")
                .error("CloudKit initialization failed; trying the local store: \(reason, privacy: .public)")
            container = try makeContainer(ModelConfiguration(schema: AppSchema.schema, url: storeURL, cloudKitDatabase: .none))
            syncManager.configure(storageMode: .localOnly(reason))
        }
    }

    /// Include the complete store directory: SQLite sidecars and external photo storage too.
    /// File coordination supplies a zipped snapshot; copy it before the accessor returns.
    func exportRecoveryCopy() async throws -> URL {
        let directory = storeURL.deletingLastPathComponent()
        return try await Task.detached(priority: .userInitiated) {
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("LibraryRecovery-\(UUID().uuidString).zip")
            let coordinator = NSFileCoordinator()
            var coordinationError: NSError?
            var outcome: Result<URL, Error> = .failure(CocoaError(.fileReadUnknown))
            coordinator.coordinate(readingItemAt: directory, options: .forUploading, error: &coordinationError) { snapshot in
                outcome = Result {
                    try FileManager.default.copyItem(at: snapshot, to: destination)
                    return destination
                }
            }
            if let coordinationError { throw coordinationError }
            return try outcome.get()
        }.value
    }
}
