//
//  ShootAlertScheduler.swift
//  ShutterManager
//
//  Works out each planned shoot's golden-hour heads-up and hands them to NotificationManager.
//

import Foundation
import SwiftData
import os

/// What one shoot needs for its alerts, as values, so the sky math runs off the main actor.
struct ShootAlertPlan: Sendable {
    let shootID: UUID
    let title: String
    let placeName: String
    let interval: DateInterval
    let coordinate: GeoCoordinate
    let timeZone: TimeZone
    let minutesBefore: Int

    /// Nil for a shoot without a heads-up, a place, or a future within the lookahead.
    init?(shoot: Shoot, now: Date) {
        let horizon = now.addingTimeInterval(Double(Constants.Shoots.alertLookaheadDays) * 86_400)
        guard shoot.goldenHourAlertMinutes > 0, shoot.endDate > now, shoot.startDate < horizon,
              let place = shoot.place else { return nil }
        shootID = shoot.id
        title = shoot.displayTitle
        placeName = place.name
        interval = shoot.interval
        coordinate = place.coordinate
        timeZone = place.timeZone
        minutesBefore = shoot.goldenHourAlertMinutes
    }

    /// One alert per golden hour the shoot can use, `minutesBefore` it starts.
    func alerts(after now: Date) -> [ShootAlert] {
        ShootLight.goldenHours(for: interval, observer: coordinate, timeZone: timeZone).enumerated()
            .compactMap { index, window in
                let date = window.start.addingTimeInterval(-Double(minutesBefore) * 60)
                guard date > now else { return nil }
                let start = window.start.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone))
                let place = placeName.trimmingCharacters(in: .whitespacesAndNewlines)
                let body = place.isEmpty
                    ? "\(title): golden hour starts at \(start)."
                    : "\(title): golden hour at \(place) starts at \(start)."
                return ShootAlert(identifier: "\(ShootAlert.identifierPrefix)\(shootID.uuidString)_\(index)",
                                  date: date, title: "Golden hour in \(minutesBefore) min", body: body)
            }
    }
}

/// Reconciles the golden-hour heads-ups with the shoot log: after a shoot is saved or deleted,
/// and wherever gear reminders are refreshed (launch, foreground, import, restore and changes
/// from other devices).
@MainActor
enum ShootAlertScheduler {
    static func alerts(for shoots: [Shoot], now: Date = Date()) async -> [ShootAlert] {
        let plans = shoots.compactMap { ShootAlertPlan(shoot: $0, now: now) }
        guard !plans.isEmpty else { return [] }
        return await Task.detached(priority: .utility) { plans.flatMap { $0.alerts(after: now) } }.value
    }

    /// Reschedules the heads-ups for every shoot in `context` that has one, after an edit.
    static func refresh(in context: ModelContext, askingPermission: Bool = false) async {
        do {
            let shoots = try context.fetch(FetchDescriptor<Shoot>(predicate: #Predicate { $0.goldenHourAlertMinutes > 0 }))
            await refresh(shoots: shoots, askingPermission: askingPermission)
        } catch {
            Logger(subsystem: Constants.App.loggerSubsystem, category: "Notifications")
                .error("Could not refresh shoot alerts: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Reschedules every shoot's heads-up. `askingPermission` is for a shoot the user just turned
    /// one on for. `notifications` defaults to the shared manager.
    static func refresh(shoots: [Shoot], askingPermission: Bool = false,
                        notifications: NotificationManager? = nil) async {
        let alerts = await alerts(for: shoots)
        await (notifications ?? .shared).replaceShootAlerts(alerts, askingPermission: askingPermission)
    }
}
