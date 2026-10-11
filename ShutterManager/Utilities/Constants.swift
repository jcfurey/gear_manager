//
//  Constants.swift
//  ShutterManager
//
//  Single source of truth for app-wide magic numbers and configuration: app metadata, data
//  limits, backup and notification keys, maintenance presets, photo storage, UserDefaults keys,
//  and base UI values. Organized as nested enum namespaces (Constants.App.*, Constants.Photos.*).
//

import Foundation

/// App-wide constants, grouped by functional area into nested enum namespaces.
enum Constants {
    enum DataLimits {
        // Generous bounds for imported libraries; reject pathological files before allocating DTOs.
        static let maximumImportBytes = 256 * 1024 * 1024
        static let maximumPhotoBytes = 25 * 1024 * 1024
        static let maximumRecords = 100_000
        /// Bound for physical measurements (focal length, aperture, filter thread, distance…).
        static let maximumMeasurement = 1_000_000.0
        /// Bound for counts that legitimately run high: shutter actuations, charge cycles.
        static let maximumCount = 1_000_000_000.0
        static let maximumMoney = 1_000_000_000_000.0
    }

    enum Backups {
        static let enabledKey = "backup.isEnabled"
        static let frequencyKey = "backup.frequency"
        static let retentionKey = "backup.maxBackups"
        static let photosKey = "backup.includePhotos"
        static let photoChoiceKey = "backup.photoChoiceConfirmed"
        static let retentionRange = 1...30
    }

    enum Notifications {
        /// The revision last scheduled for each gear reminder (sensor cleaning, loans due back),
        /// so a delivered reminder isn't reissued on every foreground.
        static let gearReminderRevisionsKey = "notifications.gearReminderRevisions"
    }

    // MARK: - App Information

    enum App {
        static let name = "Shutter Manager"

        /// Current app version from bundle info; falls back to "1.0.0".
        static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"

        static let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

        /// `os.Logger` subsystem for every log line the app writes.
        static let loggerSubsystem = "jcameronfurey.shuttermanager"
    }

    // MARK: - Maintenance

    enum Maintenance {
        /// One selectable reminder cadence. `days == 0` means "not tracked".
        struct IntervalOption: Identifiable, Hashable {
            let label: String
            let days: Int
            var id: Int { days }
        }

        /// Sensor-cleaning cadences. How often a sensor needs cleaning depends on how often lenses
        /// are changed and where, so it's per body and user-selectable.
        static let sensorCleaningIntervalOptions: [IntervalOption] = [
            IntervalOption(label: "Off", days: 0),
            IntervalOption(label: "Monthly", days: 30),
            IntervalOption(label: "Every 3 months", days: 90),
            IntervalOption(label: "Every 6 months", days: 180),
            IntervalOption(label: "Yearly", days: 365)
        ]

        /// Default time of day for gear reminders.
        static let defaultReminderHour = 10
    }

    // MARK: - Shutter

    enum Shutter {
        /// Share of the rated shutter life at which a body is flagged as nearing it.
        static let nearEndOfLifeFraction = 0.9
    }

    // MARK: - Photos

    /// Limits applied when a picked photo is stored.
    ///
    /// Gear photos mirror to the user's private CloudKit database, so whatever is stored here is
    /// also uploaded and re-downloaded on every other device. Originals from a modern camera run
    /// to tens of megabytes, and a collection with a few photos per item would push hundreds of
    /// megabytes through the user's iCloud quota for detail no phone screen can show.
    /// `@Attribute(.externalStorage)` keeps the SQLite file small but changes none of that.
    enum Photos {
        static let thumbnailCacheCountLimit = 100
        static let thumbnailCacheByteLimit = 32 * 1024 * 1024
        /// Longest-edge cap in pixels. Comfortably above a full-screen Retina view (a 3x 430pt
        /// display is 1290px), so zooming into a serial-number plate still resolves.
        static let maxStoredPixelSize: CGFloat = 2048

        /// JPEG quality for stored photos.
        static let storageCompressionQuality: CGFloat = 0.8
    }

    // MARK: - User Defaults Keys

    /// Every persisted preference key, in one place.
    enum UserDefaultsKeys {
        static let lastBackupDate = "lastBackupDate"
        /// The most recent automatic-backup failure, as `["message": String, "date": Date]`;
        /// removed by the next successful backup.
        static let lastAutomaticBackupFailure = "backup.lastAutomaticFailure"

        /// Gear reminders (sensor cleaning, loans due back). The reminder *time* is per item.
        static let gearRemindersEnabled = "notifications.gearRemindersEnabled"

        // Exportable app settings (the export/import "settings" contract)
        static let hapticFeedback = "hapticFeedback"
        static let darkModePreference = "darkModePreference"

        /// The settings keys that export writes and import is allowed to restore. Each one needs
        /// a validation rule in `ImportedSettings`; a key without one is never imported.
        static let exportableSettings: [String] = [hapticFeedback, darkModePreference]
    }

    // MARK: - UI Constants

    enum UI {
        static let cornerRadius: CGFloat = 12
        static let shadowRadius: CGFloat = 4
        static let standardSpacing: CGFloat = 16
        static let compactSpacing: CGFloat = 8
    }
}
