//
//  DateFormatters.swift
//  ShutterManager
//
//  Single source of truth for date/time and duration display. Global helpers
//  (formatDuration, formatDate, formatDetailedDate) plus cached DateFormatter
//  extensions reused across the app.
//

import Foundation

// MARK: - Duration Formatting

/// Format a duration in seconds into a human-readable time string.
/// Displays hours when present, otherwise shows minutes:seconds format.
/// Used for timers.
/// 
/// - Parameter duration: Duration in seconds (TimeInterval)
/// - Returns: Formatted time string (e.g., "1:23:45" or "23:45")
func formatDuration(_ duration: TimeInterval) -> String {
    // Finite values can also overflow Int. Invalid persisted/imported totals remain renderable.
    guard duration.isFinite, duration < Double(Int.max) else { return "—" }
    let total = Int(max(0, duration))
    let hours = total / 3600
    let minutes = total % 3600 / 60
    let seconds = total % 60
    
    if hours > 0 {
        // Include hours: "1:23:45"
        return "\(hours):" + String(format: "%02d:%02d", minutes, seconds)
    } else {
        // Minutes and seconds only: "23:45"
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Date Formatting (User-Friendly Display)

/// Cached DateFormatter for time-only display (e.g., "2:30 PM").
private let timeOnlyFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return formatter
}()

/// Cached DateFormatter for short date+time display (e.g., "12/25/23, 2:30 PM").
private let shortDateTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    return formatter
}()

/// Format a date with relative descriptions for recent dates: "Today, 2:30 PM" /
/// "Yesterday, 2:30 PM", otherwise short date+time.
/// - Parameter date: Date to format
/// - Returns: Human-readable date string
func formatDate(_ date: Date) -> String {
    let calendar = Calendar.current
    
    if calendar.isDate(date, inSameDayAs: Date()) {
        return "Today, " + timeOnlyFormatter.string(from: date)
    } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()),
              calendar.isDate(date, inSameDayAs: yesterday) {
        return "Yesterday, " + timeOnlyFormatter.string(from: date)
    } else {
        return shortDateTimeFormatter.string(from: date)
    }
}

/// Cached DateFormatter for medium date+time display (e.g., "Dec 25, 2023 at 2:30 PM").
private let mediumDateTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
}()

/// Format a date with medium detail (e.g., "Dec 25, 2023 at 2:30 PM") for reports and
/// detailed views.
/// - Parameter date: Date to format
/// - Returns: Medium-detail formatted date string
func formatDetailedDate(_ date: Date) -> String {
    return mediumDateTimeFormatter.string(from: date)
}

// MARK: - DateFormatter Extensions (Cached Formatters)

/// DateFormatter extension providing cached, reusable formatter instances.
/// Improves performance by avoiding repeated DateFormatter creation.
extension DateFormatter {
    /// Cached formatter for short month-day display (e.g., "Jan 15").
    /// Used primarily in charts, analytics, and compact date displays.
    static let dayMonth: DateFormatter = {
        let formatter = DateFormatter()
        // A template, not a fixed "MMM d" pattern: the fixed pattern forced US field order on
        // every locale ("Sept. 27" in German, "9月 27" in Japanese instead of "27. Sept." /
        // "9月27日"). en_US still renders "Jan 15".
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }()

    /// Cached formatter for filesystem-safe timestamps in filenames (e.g., "2026-05-14_15-30-22").
    /// Used by backup and export services. Pinned to the POSIX locale + Gregorian calendar so a
    /// fixed `yyyy` pattern always emits the Gregorian year — otherwise a device on a non-Gregorian
    /// calendar (e.g. Buddhist th_TH, year +543) would name files "backup_2569-..." and sort them
    /// inconsistently with Gregorian-named ones.
    static let fileTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()
}
