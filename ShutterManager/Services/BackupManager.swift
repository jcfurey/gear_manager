//
//  BackupManager.swift
//  ShutterManager
//
//  Local backups: scheduled and manual, verified before they're listed, with retention.

import Foundation
import SwiftData
import os

/// Manages automated backups with version history and cleanup
@MainActor
class BackupManager: ObservableObject {
    private let logger = Logger(subsystem: Constants.App.loggerSubsystem, category: "BackupManager")

    // MARK: - Configuration
    
    struct BackupConfiguration {
        var isEnabled: Bool = true
        var frequency: BackupFrequency = .daily
        var maxBackups: Int = 7
        /// Complete backups include both gallery and maintenance photos by default.
        var includePhotos: Bool = true
        
        enum BackupFrequency: String, CaseIterable {
            case daily = "Daily"
            case weekly = "Weekly"
            case manual = "Manual Only"
            
            var timeInterval: TimeInterval? {
                switch self {
                case .daily: return 86400 // 24 hours
                case .weekly: return 604800 // 7 days
                case .manual: return nil
                }
            }
        }
    }
    
    // MARK: - Properties
    
    @Published var configuration: BackupConfiguration
    @Published var availableBackups: [BackupMetadata] = []
    @Published var isBackingUp = false
    @Published var lastBackupDate: Date?
    @Published var lastBackupError: String?
    /// Set while the most recent automatic attempt failed; persisted, so it survives the app
    /// being suspended right after the attempt. Any successful backup clears it.
    @Published private(set) var lastAutomaticBackupFailure: AutomaticBackupFailure?
    /// NaN/±∞ or out-of-range values the most recent successful backup saved as defaults so it
    /// could be verified and restored (see `ComprehensiveExportData.replaceUnrestorableNumbers()`);
    /// 0 when none. The library itself keeps its values.
    @Published private(set) var lastBackupReplacedValueCount = 0

    /// Why the schedule stopped producing backups, for Backup Management.
    struct AutomaticBackupFailure: Equatable {
        let message: String
        let date: Date
    }

    private static var busyDirectories: Set<URL> = []
    private let fileManager = FileManager.default
    private let exportService: DataExportService
    private let backupsDirectory: URL
    private let defaults: UserDefaults

    init(directory: URL? = nil, defaults: UserDefaults = .standard) {
        self.backupsDirectory = (directory ?? URL.documentsDirectory.appendingPathComponent("Backups", isDirectory: true)).standardizedFileURL
        self.defaults = defaults
        // Back up the same preferences a restore writes back.
        self.exportService = DataExportService(settingsStore: defaults)
        self.configuration = BackupConfiguration()
        self.lastBackupDate = defaults.object(forKey: Constants.UserDefaultsKeys.lastBackupDate) as? Date
        if let stored = defaults.dictionary(forKey: Constants.UserDefaultsKeys.lastAutomaticBackupFailure),
           let message = stored["message"] as? String, let date = stored["date"] as? Date {
            self.lastAutomaticBackupFailure = AutomaticBackupFailure(message: message, date: date)
        }
        self.configuration = loadConfiguration()
        do { try fileManager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true) }
        catch { lastBackupError = error.localizedDescription }
        loadAvailableBackups()
    }

    // MARK: - Backup Operations
    
    /// Create a new backup of all app data
    func createBackup(gearItems: [GearItem]) async throws {
        guard Self.busyDirectories.insert(backupsDirectory).inserted else { throw BackupError.busy }

        defer { Self.busyDirectories.remove(backupsDirectory) }
        isBackingUp = true
        lastBackupError = nil
        
        do {
            // Create backup configuration
            var backupConfig = DataExportService.ExportConfiguration(format: .json)
            backupConfig.includePhotos = configuration.includePhotos

            let exportURL = try await exportService.exportData(configuration: backupConfig, gearItems: gearItems)
            
            defer { try? fileManager.removeItem(at: exportURL) }
            let replacedValues = exportService.lastReplacedValueCount
            // Never advertise a backup that the restore path cannot read or validate.
            do {
                _ = try await Task.detached { try ImportDocument.decode(ImportDocument.read(exportURL)) }.value
            } catch ImportError.importFailed(let reason) {
                // "Import failed: …" would misdescribe a backup in Backup Management.
                throw BackupError.verificationFailed(reason)
            }

            // Move to backups directory with metadata
            let backupID = UUID()
            let backupURL = try moveToBackupsDirectory(from: exportURL, id: backupID)
            
            // Create metadata
            let metadata = BackupMetadata(
                id: backupID,
                date: Date(),
                fileURL: backupURL,
                fileSize: try fileSize(at: backupURL),
                itemCounts: BackupItemCounts(
                    gearItems: gearItems.count,
                    otherRecords: gearItems.reduce(0) { total, item in
                        total + (item.maintenanceRecords?.count ?? 0) + (item.maintenanceReminders?.count ?? 0)
                            + (item.shutterCountReadings?.count ?? 0) + (item.loans?.count ?? 0)
                    }
                ),
                includesPhotos: backupConfig.includePhotos
            )
            
            // Save metadata
            try saveBackupMetadata(metadata)
            
            // Update state
            await MainActor.run {
                self.lastBackupDate = Date()
                defaults.set(self.lastBackupDate, forKey: Constants.UserDefaultsKeys.lastBackupDate)
                // The library backs up again, so the schedule is no longer stuck.
                self.lastAutomaticBackupFailure = nil
                defaults.removeObject(forKey: Constants.UserDefaultsKeys.lastAutomaticBackupFailure)
                self.lastBackupReplacedValueCount = replacedValues
                self.loadAvailableBackups()
                self.isBackingUp = false
            }
            
            // Cleanup old backups
            try cleanupOldBackups()
            
        } catch {
            await MainActor.run {
                self.lastBackupError = error.localizedDescription
                self.isBackingUp = false
            }
            throw error
        }
    }
    
    /// Validate the complete payload before any replacement. Import owns the save/rollback boundary.
    func restoreBackup(_ metadata: BackupMetadata, to modelContext: ModelContext) async throws {
        guard Self.busyDirectories.insert(backupsDirectory).inserted else { throw BackupError.busy }
        defer { Self.busyDirectories.remove(backupsDirectory) }
        let url = try resolvedURL(for: metadata)
        guard fileManager.fileExists(atPath: url.path) else { throw BackupError.backupNotFound }
        let document = try await Task.detached {
            try ImportDocument.decode(ImportDocument.read(url))
        }.value
        try await DataImportService(settingsStore: defaults).apply(document, to: modelContext, strategy: .replace)
    }

    func deleteBackup(_ metadata: BackupMetadata) throws {
        guard !Self.busyDirectories.contains(backupsDirectory) else { throw BackupError.busy }
        try removeBackup(metadata)
    }

    private func removeBackup(_ metadata: BackupMetadata) throws {
        let url = try resolvedURL(for: metadata)
        if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
        try writeMetadata(loadAllBackupMetadata().filter { $0.fileURL.lastPathComponent != url.lastPathComponent })
        loadAvailableBackups()
    }

    private func resolvedURL(for metadata: BackupMetadata) throws -> URL {
        let url = backupsDirectory.appendingPathComponent(metadata.fileURL.lastPathComponent)
        guard url.pathExtension == "json", url.lastPathComponent != "metadata.json",
              url.resolvingSymlinksInPath().deletingLastPathComponent().path == backupsDirectory.resolvingSymlinksInPath().path else {
            throw BackupError.invalidBackupFile
        }
        return url
    }

    /// The scheduled backup: runs when due, reading the whole library from `context`. A failure
    /// used to be only logged, so one bad value could silently stop every automatic backup; it
    /// is now persisted for Backup Management until a backup succeeds. Never throws.
    /// - Returns: Whether a backup was created.
    @discardableResult
    func performAutomaticBackupIfDue(from context: ModelContext) async -> Bool {
        guard shouldCreateAutomaticBackup() else { return false }
        do {
            try await createBackup(gearItems: try context.fetch(FetchDescriptor<GearItem>()))
            return true
        } catch BackupError.busy {
            // A manual backup or restore is running; the schedule tries again next time.
            return false
        } catch {
            logger.error("Automatic backup failed: \(error.localizedDescription, privacy: .public)")
            recordAutomaticBackupFailure(error.localizedDescription)
            return false
        }
    }

    private func recordAutomaticBackupFailure(_ message: String, at date: Date = Date()) {
        lastAutomaticBackupFailure = AutomaticBackupFailure(message: message, date: date)
        defaults.set(["message": message, "date": date] as [String: Any],
                     forKey: Constants.UserDefaultsKeys.lastAutomaticBackupFailure)
    }

    /// Check if a backup is needed based on configuration
    func shouldCreateAutomaticBackup() -> Bool {
        guard configuration.isEnabled,
              let frequency = configuration.frequency.timeInterval else {
            return false
        }

        // An enabled schedule must seed itself. Requiring a previous manual backup here made
        // automatic backups permanently inert on every fresh install.
        guard let lastBackup = lastBackupDate else { return true }
        
        let timeSinceLastBackup = Date().timeIntervalSince(lastBackup)
        return timeSinceLastBackup >= frequency
    }
    
    // MARK: - Private Helpers
    
    private func moveToBackupsDirectory(from sourceURL: URL, id: UUID) throws -> URL {
        let filename = "backup_\(DateFormatter.fileTimestamp.string(from: Date()))_\(id.uuidString).json"
        let destination = backupsDirectory.appendingPathComponent(filename)
        try fileManager.moveItem(at: sourceURL, to: destination)
        return destination
    }

    private func fileSize(at url: URL) throws -> Int64 {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return attributes[.size] as? Int64 ?? 0
    }

    private func saveBackupMetadata(_ metadata: BackupMetadata) throws {
        // Loading may discover the newly moved file. Replace its recovered entry with precise metadata.
        let others = loadAllBackupMetadata().filter { $0.fileURL.lastPathComponent != metadata.fileURL.lastPathComponent }
        try writeMetadata(others + [metadata])
    }

    private func writeMetadata(_ metadata: [BackupMetadata]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(metadata).write(to: backupsDirectory.appendingPathComponent("metadata.json"), options: .atomic)
    }

    private func loadAllBackupMetadata() -> [BackupMetadata] {
        let metadataURL = backupsDirectory.appendingPathComponent("metadata.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var entries: [BackupMetadata] = []
        if fileManager.fileExists(atPath: metadataURL.path) {
            do { entries = try decoder.decode([BackupMetadata].self, from: Data(contentsOf: metadataURL)) }
            catch {
                logger.error("Backup index unreadable; recovering local files: \(error.localizedDescription, privacy: .public)")
                lastBackupError = "The backup index was damaged. Available files have been recovered; check their contents before restoring."
            }
        }
        var names = Set<String>()
        entries = entries.sorted { $0.date > $1.date }.compactMap { entry in
            guard let url = try? resolvedURL(for: entry), fileManager.fileExists(atPath: url.path),
                  names.insert(url.lastPathComponent).inserted else { return nil }
            var resolved = entry
            resolved.fileURL = url
            return resolved
        }
        // Do not decode photo-heavy payloads on launch. Recovered entries advertise unknown contents.
        if let files = try? fileManager.contentsOfDirectory(at: backupsDirectory, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey]) {
            for url in files where url.lastPathComponent.hasPrefix("backup_") && url.pathExtension == "json" && !names.contains(url.lastPathComponent) {
                let values = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
                entries.append(BackupMetadata(id: UUID(), date: values?.creationDate ?? .distantPast,
                    fileURL: url, fileSize: Int64(values?.fileSize ?? 0),
                    itemCounts: BackupItemCounts(gearItems: 0, otherRecords: 0),
                    isRecovered: true))
            }
        }
        return entries
    }

    private func loadAvailableBackups() {
        availableBackups = loadAllBackupMetadata().sorted { $0.date > $1.date }
    }

    private func cleanupOldBackups() throws {
        let limit = min(max(configuration.maxBackups, Constants.Backups.retentionRange.lowerBound), Constants.Backups.retentionRange.upperBound)
        for backup in Array(availableBackups.dropFirst(limit)) { try removeBackup(backup) }
    }

    private func loadConfiguration() -> BackupConfiguration {
        var config = BackupConfiguration()
        config.isEnabled = defaults.object(forKey: Constants.Backups.enabledKey) as? Bool ?? true
        if let raw = defaults.string(forKey: Constants.Backups.frequencyKey),
           let frequency = BackupConfiguration.BackupFrequency(rawValue: raw) { config.frequency = frequency }
        let limit = defaults.object(forKey: Constants.Backups.retentionKey) as? Int ?? 7
        config.maxBackups = min(max(limit, Constants.Backups.retentionRange.lowerBound), Constants.Backups.retentionRange.upperBound)
        // Previous versions silently persisted false even though the photo option was not exposed.
        config.includePhotos = defaults.bool(forKey: Constants.Backups.photoChoiceKey)
            ? defaults.bool(forKey: Constants.Backups.photosKey) : true
        return config
    }

    func saveConfiguration(confirmPhotoChoice: Bool = false) {
        defaults.set(configuration.isEnabled, forKey: Constants.Backups.enabledKey)
        defaults.set(configuration.frequency.rawValue, forKey: Constants.Backups.frequencyKey)
        defaults.set(configuration.maxBackups, forKey: Constants.Backups.retentionKey)
        defaults.set(configuration.includePhotos, forKey: Constants.Backups.photosKey)
        if confirmPhotoChoice { defaults.set(true, forKey: Constants.Backups.photoChoiceKey) }
    }

}

// MARK: - Supporting Types

struct BackupMetadata: Codable, Identifiable {
    let id: UUID
    let date: Date
    var fileURL: URL
    let fileSize: Int64
    let itemCounts: BackupItemCounts
    
    var includesPhotos: Bool? = nil
    var isRecovered: Bool = false

    var photoSummary: String {
        switch includesPhotos {
        case true: return "Photos included"
        case false: return "Photos omitted"
        case nil: return "Photo completeness unknown"
        }
    }

    var restoreMessage: String {
        let base = "This replaces current records with the backup."
        switch includesPhotos {
        case true: return base + " Photos saved in this backup will be restored."
        case false: return base + " This backup omits photos. Existing photos will be removed. Create a complete backup first if you want to keep them."
        case nil: return base + " This older or recovered backup may omit photos. Existing photos absent from the backup will be removed. Create a complete backup first if you want to keep them."
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, date, timestamp, fileName, fileURL, fileSize, itemCounts, includesPhotos, isRecovered
    }

    init(id: UUID, date: Date, fileURL: URL, fileSize: Int64, itemCounts: BackupItemCounts,
         includesPhotos: Bool? = nil, isRecovered: Bool = false) {
        self.id = id; self.date = date; self.fileURL = fileURL; self.fileSize = fileSize
        self.itemCounts = itemCounts; self.includesPhotos = includesPhotos; self.isRecovered = isRecovered
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        // Retain sub-second ordering. JSONEncoder's ISO-8601 strategy truncates it,
        // which otherwise lets retention delete a newer rapid backup before an older one.
        if let timestamp = try values.decodeIfPresent(TimeInterval.self, forKey: .timestamp), timestamp.isFinite {
            date = Date(timeIntervalSince1970: timestamp)
        } else {
            date = try values.decode(Date.self, forKey: .date)
        }
        if let name = try values.decodeIfPresent(String.self, forKey: .fileName) {
            fileURL = URL(fileURLWithPath: name)
        } else {
            fileURL = try values.decode(URL.self, forKey: .fileURL)
        }
        fileSize = try values.decode(Int64.self, forKey: .fileSize)
        itemCounts = try values.decode(BackupItemCounts.self, forKey: .itemCounts)
        includesPhotos = try values.decodeIfPresent(Bool.self, forKey: .includesPhotos)
        isRecovered = try values.decodeIfPresent(Bool.self, forKey: .isRecovered) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(date, forKey: .date)
        try values.encode(date.timeIntervalSince1970, forKey: .timestamp)
        try values.encode(fileURL.lastPathComponent, forKey: .fileName)
        try values.encode(fileSize, forKey: .fileSize)
        try values.encode(itemCounts, forKey: .itemCounts)
        try values.encodeIfPresent(includesPhotos, forKey: .includesPhotos)
        try values.encode(isRecovered, forKey: .isRecovered)
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
    
    var formattedDate: String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

struct BackupItemCounts: Codable {
    let gearItems: Int
    /// Maintenance records and reminders, shutter-count readings and loans.
    let otherRecords: Int

    var totalItems: Int { gearItems + otherRecords }
}

enum BackupError: LocalizedError {
    case backupNotFound
    case busy
    case invalidBackupFile
    case restoreFailed
    /// The written file failed the same validation a restore applies.
    case verificationFailed(String)

    var errorDescription: String? {
        switch self {
        case .verificationFailed(let reason):
            return "The backup could not be verified: \(reason)"
        case .busy:
            return "A backup operation is already in progress. Please try again when it finishes."
        case .backupNotFound:
            return "Backup file not found"
        case .invalidBackupFile:
            return "Invalid backup file format"
        case .restoreFailed:
            return "Failed to restore backup"
        }
    }
}
