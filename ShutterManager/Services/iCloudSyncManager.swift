//
//  iCloudSyncManager.swift
//  ShutterManager
//
//  Reports storage mode, iCloud account status and SwiftData's CloudKit mirroring events.
//

import CloudKit
import CoreData
import Foundation
import os

/// Observes SwiftData's CloudKit mirroring; never writes CloudKit records or forces a sync.
/// Owned by the library so setup/import/export events are observed before Settings opens.
@MainActor
@Observable
final class iCloudSyncManager {
    static let containerIdentifier = "iCloud.jcameronfurey.shuttermanager"
    private static let logger = Logger(subsystem: Constants.App.loggerSubsystem, category: "iCloudSync")

    enum StorageMode: Equatable {
        case opening
        case cloudKit
        case localOnly(String)
        case unavailable
    }

    enum SyncStatus: Equatable {
        case unknown, available, syncing, noAccount, restricted, temporarilyUnavailable
        case localOnly, unavailable
        case error(String)

        var displayText: String {
            switch self {
            case .unknown: return "Checking…"
            case .available: return "iCloud enabled"
            case .syncing: return "Syncing…"
            case .noAccount: return "Not signed in"
            case .restricted: return "iCloud restricted"
            case .temporarilyUnavailable: return "iCloud unavailable"
            case .localOnly: return "On this device only"
            case .unavailable: return "Library unavailable"
            case .error: return "Sync needs attention"
            }
        }

        var icon: String {
            switch self {
            case .available: return "icloud"
            case .syncing: return "arrow.triangle.2.circlepath.icloud"
            case .noAccount, .restricted, .temporarilyUnavailable, .localOnly: return "exclamationmark.icloud"
            case .error, .unavailable: return "xmark.icloud"
            case .unknown: return "icloud"
            }
        }
    }

    /// Value snapshot also lets tests exercise failures without an iCloud account.
    struct SyncEvent {
        enum Kind: Hashable { case setup, download, upload }
        let id: UUID
        let kind: Kind
        let start: Date
        let end: Date?
        let succeeded: Bool
        let error: String?
    }

    private(set) var storageMode: StorageMode = .opening
    private(set) var lastUpload: Date?
    private(set) var lastDownload: Date?
    private(set) var isCheckingAccount = false
    private var account: CKAccountStatus?
    private var accountError: String?
    private var activeEvents: [UUID: SyncEvent] = [:]
    private var completedEvents: [SyncEvent.Kind: Date] = [:]
    private var failures: [SyncEvent.Kind: String] = [:]
    private var eventsSince = Date.distantPast
    @ObservationIgnored private var refreshGeneration = 0
    @ObservationIgnored private let accountStatusProvider: () async throws -> CKAccountStatus
    @ObservationIgnored private let notificationCenter: NotificationCenter
    @ObservationIgnored private let storeURL: URL?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(storeURL: URL? = nil, notificationCenter: NotificationCenter = .default,
         accountStatusProvider: @escaping () async throws -> CKAccountStatus = {
             try await CKContainer(identifier: iCloudSyncManager.containerIdentifier).accountStatus()
         }) {
        self.storeURL = storeURL?.standardizedFileURL
        self.notificationCenter = notificationCenter
        self.accountStatusProvider = accountStatusProvider
        observers.append(notificationCenter.addObserver(forName: .CKAccountChanged, object: nil, queue: nil) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.accountDidChange()
                await self.refresh()
            }
        })
        observers.append(notificationCenter.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: nil
        ) { [weak self] notification in
            Task { @MainActor [weak self] in self?.receive(notification) }
        })
    }

    deinit {
        for observer in observers { notificationCenter.removeObserver(observer) }
    }

    var status: SyncStatus {
        switch storageMode {
        case .opening: return .unknown
        case .localOnly: return .localOnly
        case .unavailable: return .unavailable
        case .cloudKit: break
        }
        if let accountError { return .error(accountError) }
        switch account {
        case .noAccount: return .noAccount
        case .restricted: return .restricted
        case .couldNotDetermine, .temporarilyUnavailable: return .temporarilyUnavailable
        default: break
        }
        // A successful import must not hide an upload failure (or vice versa).
        for kind in [SyncEvent.Kind.setup, .upload, .download] {
            if let error = failures[kind] { return .error(error) }
        }
        guard account == .available else { return .unknown }
        return activeEvents.isEmpty ? .available : .syncing
    }

    var isAvailable: Bool { status == .available || status == .syncing }

    var detailText: String {
        switch status {
        case .localOnly:
            return "Your library is saved on this device, but iCloud sync could not start. Restart the app to retry."
        case .noAccount:
            return "Sign in to iCloud in system Settings and enable iCloud for Shutter Manager."
        case .restricted:
            return "iCloud access is restricted on this device. Check your account or device restrictions in system Settings."
        case .temporarilyUnavailable:
            return "iCloud could not be reached. Check your connection and try checking the status again."
        case .error:
            return "Your saved library is still on this device. If sync does not recover, restart the app."
        case .unavailable:
            return "The library could not be opened. Use library recovery to retry or export a recovery copy."
        default:
            return "Your library syncs automatically between devices using the same Apple Account. Transfers may take time."
        }
    }

    var diagnosticMessage: String? {
        if case .localOnly(let reason) = storageMode { return reason }
        if case .error(let reason) = status { return reason }
        return nil
    }

    func configure(storageMode: StorageMode) {
        self.storageMode = storageMode
        if storageMode != .cloudKit {
            refreshGeneration += 1
            isCheckingAccount = false
            account = nil
            accountError = nil
            resetActivity()
        }
    }

    /// This rechecks account availability only. SwiftData schedules all transfers itself.
    func refresh() async {
        guard storageMode == .cloudKit else { return }
        refreshGeneration += 1
        let generation = refreshGeneration
        isCheckingAccount = true
        do {
            let result = try await accountStatusProvider()
            guard generation == refreshGeneration else { return }
            // A temporary account-check failure does not invalidate transfer history or
            // resolve an earlier mirroring error. Only a confirmed sign-out clears it.
            if result == .noAccount {
                eventsSince = Date()
                resetActivity()
            }
            account = result
            accountError = nil
        } catch {
            guard generation == refreshGeneration else { return }
            accountError = error.localizedDescription
            Self.logger.error("iCloud account check failed: \(error.localizedDescription, privacy: .public)")
        }
        isCheckingAccount = false
    }

    func accountDidChange() {
        refreshGeneration += 1
        account = nil
        accountError = nil
        isCheckingAccount = false
        eventsSince = Date()
        resetActivity()
    }

    private func resetActivity() {
        activeEvents.removeAll()
        completedEvents.removeAll()
        failures.removeAll()
        lastUpload = nil
        lastDownload = nil
    }

    private func receive(_ notification: Notification) {
        guard let cloudContainer = notification.object as? NSPersistentCloudKitContainer,
              let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event,
              let storeURL,
              cloudContainer.persistentStoreDescriptions.contains(where: {
                  $0.url?.standardizedFileURL == storeURL &&
                  $0.cloudKitContainerOptions?.containerIdentifier == Self.containerIdentifier
              }),
              cloudContainer.persistentStoreCoordinator.persistentStores.contains(where: {
                  $0.identifier == event.storeIdentifier && $0.url?.standardizedFileURL == storeURL
              }) else { return }
        let kind: SyncEvent.Kind
        switch event.type {
        case .setup: kind = .setup
        case .import: kind = .download
        case .export: kind = .upload
        @unknown default: return
        }
        record(SyncEvent(id: event.identifier, kind: kind, start: event.startDate,
                         end: event.endDate, succeeded: event.succeeded,
                         error: event.error?.localizedDescription))
    }

    func record(_ event: SyncEvent) {
        guard storageMode == .cloudKit, event.start >= eventsSince else { return }
        if let end = event.end {
            activeEvents[event.id] = nil
            guard end > (completedEvents[event.kind] ?? .distantPast) else { return }
            completedEvents[event.kind] = end
            if event.succeeded {
                failures[event.kind] = nil
                if event.kind == .upload { lastUpload = end }
                if event.kind == .download { lastDownload = end }
                // Setup runs once per launch, so a failed setup used to stay on screen all session
                // even after transfers succeeded. A transfer that completes after the failed setup
                // shows mirroring recovered. It clears only the setup failure: the latest
                // upload/download keeps its own failure until one of the same kind succeeds.
                if event.kind != .setup, failures[.setup] != nil,
                   end > (completedEvents[.setup] ?? .distantPast) {
                    failures[.setup] = nil
                }
            } else {
                let message = event.error ?? "iCloud did not complete the transfer. If the problem persists, restart the app."
                Self.logger.error("CloudKit \(String(describing: event.kind), privacy: .public) failed: \(message, privacy: .public)")
                // A setup failure delivered after a later transfer already succeeded is stale.
                let latestTransfer = [lastUpload, lastDownload].compactMap { $0 }.max() ?? .distantPast
                if event.kind != .setup || latestTransfer < end {
                    failures[event.kind] = message
                }
            }
        } else if event.start > (completedEvents[event.kind] ?? .distantPast) {
            activeEvents[event.id] = event
        }
    }
}
