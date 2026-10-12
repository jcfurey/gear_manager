//
//  ModelContext+Save.swift
//  ShutterManager
//
//  A saving helper that logs failures instead of silently discarding them.
//

import SwiftData
import os

extension ModelContext {
    /// Save pending changes and report success. Failure is logged and shown as a toast.
    /// Explicit commit flows must check the result before dismissing or claiming success.
    /// No-ops when there are no pending changes; rollback policy belongs to the caller.
    @discardableResult
    func saveOrLog(_ operation: String = #function) -> Bool {
        guard hasChanges else { return true }
        do {
            try save()
            return true
        } catch {
            Logger(subsystem: Constants.App.loggerSubsystem, category: "Persistence")
                .error("SwiftData save failed (\(operation, privacy: .public)): \(error.localizedDescription, privacy: .public)")
            Task { @MainActor in
                ToastNotificationManager.shared.error("Changes not saved", message: "Please try again. Your changes have not been written to storage.")
            }
            return false
        }
    }
}
