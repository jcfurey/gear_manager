//
//  ShutterManagerApp.swift
//  ShutterManager
//
//  App entry point: opens the library (or the recovery screen), and keeps reminders, the icon
//  badge and automatic backups in step with app lifecycle and sync events.
//

import SwiftUI
import SwiftData
import CoreData
import UIKit
import UserNotifications
import os

@main
struct ShutterManagerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store: AppStoreController

    init() {
        _store = StateObject(wrappedValue: AppStoreController())
        guard !AppStoreController.isSchemaInitialization else { return }
        // Without a delegate, iOS discards notifications delivered while the app is active.
        // Installed before launch finishes.
        UNUserNotificationCenter.current().delegate = NotificationPresentationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if AppStoreController.isSchemaInitialization {
                ContentUnavailableView(
                    store.errorMessage == nil ? "Development schema initialized" : "Schema initialization failed",
                    systemImage: store.errorMessage == nil ? "checkmark.icloud" : "exclamationmark.icloud",
                    description: Text(store.errorMessage ?? "The existing library was not opened. Review the schema in CloudKit Console before deploying it."))
            } else {
                libraryContent
            }
            #else
            libraryContent
            #endif
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard !AppStoreController.isSchemaInitialization else { return }
            if newPhase == .active {
                // `.active` covers launch and every return from the background.
                Task { await store.syncManager.refresh() }
                NotificationManager.shared.clearBadge()
                refreshGearReminders()
            } else if newPhase == .background {
                performAutomaticBackupIfNeeded()
            }
        }
    }

    @ViewBuilder
    private var libraryContent: some View {
        if let container = store.container {
            ContentView()
                .modelContainer(container)
                .environment(store.syncManager)
                .task {
                    refreshGearReminders()
                    await store.syncManager.refresh()
                }
                // Imports, restores and other devices' changes can all move due dates.
                .onReceive(NotificationCenter.default.publisher(for: DataImportService.didImportNotification).receive(on: DispatchQueue.main)) { _ in
                    refreshGearReminders()
                }
                .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange).receive(on: DispatchQueue.main)) { _ in
                    refreshGearReminders()
                }
        } else {
            StoreRecoveryView(store: store)
        }
    }

    /// Reconciles gear reminders and the shoots' golden-hour heads-ups with the library.
    private func refreshGearReminders() {
        Task { @MainActor in
            guard let context = store.container?.mainContext else { return }
            do {
                let items = try context.fetch(FetchDescriptor<GearItem>())
                await NotificationManager.shared.refreshGearReminders(for: items)
                await ShootAlertScheduler.refresh(in: context)
            } catch {
                Logger(subsystem: Constants.App.loggerSubsystem, category: "Notifications")
                    .error("Could not refresh reminders: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Runs on every move to the background and creates a backup if one is due. This isn't a
    /// `BGTaskScheduler` task: the app isn't woken while suspended, it just uses a lifecycle event
    /// it already observes. Never throws; a failure is logged and persisted by `BackupManager`,
    /// and Backup Management shows it.
    private func performAutomaticBackupIfNeeded() {
        #if DEBUG
        guard !ProcessInfo.processInfo.arguments.contains("-uiTestInMemory") else { return }
        #endif
        Task { @MainActor in
            let backupManager = BackupManager()
            guard backupManager.shouldCreateAutomaticBackup() else { return }
            // This starts as iOS is about to suspend the app, so hold a background-task assertion
            // for its duration; otherwise suspension mid-backup can strand a file on disk with no
            // index entry.
            let backgroundTask = BackgroundTaskHolder(name: "AutomaticBackup")
            defer { backgroundTask.end() }
            guard let context = store.container?.mainContext else { return }
            await backupManager.performAutomaticBackupIfDue(from: context)
        }
    }
}

/// Holds a one-shot UIKit background-task assertion and ends it exactly once: from the system's
/// expiration handler if time runs out, otherwise from `end()` when the work completes.
@MainActor
private final class BackgroundTaskHolder {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    init(name: String) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            self?.end()
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
