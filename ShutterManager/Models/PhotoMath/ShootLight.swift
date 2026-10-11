//
//  ShootLight.swift
//  ShutterManager
//
//  Which golden hours a shoot can use, for its heads-up. Foundation-only.
//  See docs/PHOTO_MATH_REFERENCES.md § Sun and moon for how golden hour is found.
//

import Foundation

enum ShootLight {
    /// The most days of a long shoot to look at.
    static let maximumDays = 3

    /// The golden hours that overlap `shoot`, from the days it spans (up to `maximumDays`). If none
    /// overlap, the first one after it starts that day or the next, so a short midday shoot still
    /// hears about the evening light. Windows that run past midnight, as near the poles in summer,
    /// come back as one.
    static func goldenHours(for shoot: DateInterval, observer: GeoCoordinate, timeZone: TimeZone) -> [DateInterval] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let firstDay = calendar.startOfDay(for: shoot.start)
        var windows: [DateInterval] = []
        var day = firstDay
        for index in 0..<maximumDays {
            // Always the first day and the one after (for the "next window" fallback); later days
            // only while the shoot lasts.
            guard index < 2 || day < shoot.end else { break }
            windows += SkyDay(date: day, observer: observer, timeZone: timeZone).goldenHours
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        let merged = merge(windows)
        let overlapping = merged.filter { $0.intersects(shoot) && $0.end > shoot.start && $0.start < shoot.end }
        if !overlapping.isEmpty { return overlapping }
        return merged.first { $0.start >= shoot.start }.map { [$0] } ?? []
    }

    /// Joins windows that touch (a day's last window and the next day's first, at midnight).
    static func merge(_ windows: [DateInterval]) -> [DateInterval] {
        var result: [DateInterval] = []
        for window in windows.sorted(by: { $0.start < $1.start }) {
            if let last = result.last, window.start.timeIntervalSince(last.end) <= 2 {
                result[result.count - 1] = DateInterval(start: last.start, end: max(last.end, window.end))
            } else {
                result.append(window)
            }
        }
        return result
    }
}
