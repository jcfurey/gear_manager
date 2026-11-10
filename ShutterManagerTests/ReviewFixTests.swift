//
//  ReviewFixTests.swift
//  ShutterManagerTests
//
//  Regression tests for the defects a review of the 1.0 code found: reminders that never fired or
//  fired twice, timer alerts cut off, shoot times that moved, exports too large to read back, and
//  number fields that misread what was typed.
//

import Foundation
import SwiftData
import UserNotifications
import Testing
@testable import ShutterManager

// MARK: - Reminders

@MainActor
struct ReminderFixTests {
    private typealias FakeCenter = NotificationManagerTests.FakeCenter

    private func enabledDefaults() -> UserDefaults {
        let defaults = TestSupport.makeDefaults()
        defaults.set(true, forKey: Constants.UserDefaultsKeys.gearRemindersEnabled)
        return defaults
    }

    private func days(_ count: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: count, to: Date()) ?? Date()
    }

    @Test func maintenanceRemindersNotifyExceptBesideTheItemsOwnCleaningSchedule() throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let body = GearItem(category: .cameraBody, make: "Nikon", model: "Z6 III")
        body.sensorCleaningIntervalDays = 180
        context.insert(body)
        let firmware = MaintenanceReminder(gearItem: body, type: .firmwareUpdate, dueDate: days(5))
        let cleaning = MaintenanceReminder(gearItem: body, type: .sensorCleaning, dueDate: days(5))
        let done = MaintenanceReminder(gearItem: body, type: .inspection, dueDate: days(5), isActive: false)
        [firmware, cleaning, done].forEach(context.insert)
        try context.save()

        #expect(firmware.notifies(for: body))
        #expect(!cleaning.notifies(for: body), "The body's own schedule already reminds")
        #expect(!done.notifies(for: body))

        let reminders = NotificationManager.GearReminder.all(for: body)
        let scheduled = reminders.filter { $0.identifier.hasPrefix("maintenance_due_") && $0.due != nil }
        #expect(scheduled.map(\.identifier) == ["maintenance_due_\(firmware.id.uuidString)"])
        #expect(scheduled.first?.title == "Firmware Update due")
        #expect(scheduled.first?.body == "Nikon Z6 III is due for firmware update.")

        // With the body's own schedule off, the reminder is the only thing that can remind.
        body.sensorCleaningIntervalDays = 0
        #expect(cleaning.notifies(for: body))
    }

    @Test func aMaintenanceReminderIsScheduledAndCancelledByItsIdentifier() async throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let lens = TestSupport.insertSampleLens(into: context)
        let reminder = MaintenanceReminder(gearItem: lens, type: .cleaning, dueDate: days(5))
        context.insert(reminder)
        try context.save()

        let center = FakeCenter()
        let manager = center.make(defaults: enabledDefaults())
        await manager.refreshGearReminders(for: [lens])
        let identifier = NotificationManager.GearReminder.identifier(for: reminder)
        #expect(center.pending.map(\.identifier) == [identifier])

        // Dismissing a reminder deletes it, so the item no longer lists it; it goes by name.
        manager.cancelReminders(identifiers: [identifier])
        await manager.waitForPendingWork()
        #expect(center.pending.isEmpty)
    }

    @Test func aDeletedLoansReminderGoesByItsIdentifier() async throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let body = GearItem(category: .cameraBody, make: "Sony", model: "A7 IV")
        context.insert(body)
        let loan = GearLoan(gearItem: body, person: "Kim", dueDate: days(2))
        context.insert(loan)
        try context.save()

        let center = FakeCenter()
        let manager = center.make(defaults: enabledDefaults())
        await manager.refreshGearReminders(for: [body])
        #expect(center.pending.count == 1)

        // Once the loan is deleted the item no longer lists it, so its reminder is named first
        // and cancelled by that name.
        let identifier = NotificationManager.GearReminder.identifier(for: loan)
        #expect(center.pending.map(\.identifier) == [identifier])
        context.delete(loan)
        try context.save()
        manager.cancelReminders(identifiers: [identifier])
        await manager.waitForPendingWork()
        #expect(center.pending.isEmpty)
    }

    @Test func aDueMaintenanceReminderNeedsAttention() throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let lens = TestSupport.insertSampleLens(into: context)
        #expect(lens.attentionReasons.isEmpty)
        context.insert(MaintenanceReminder(gearItem: lens, type: .cleaning, dueDate: days(-1)))
        context.insert(MaintenanceReminder(gearItem: lens, type: .cleaning, dueDate: days(-30)))
        context.insert(MaintenanceReminder(gearItem: lens, type: .inspection, dueDate: days(30)))
        try context.save()
        #expect(lens.attentionReasons == ["Cleaning due"], "Once for the kind, and nothing for what isn't due yet")
    }

    @Test func theRevisionIgnoresFractionsOfASecond() {
        func reminder(due: Date) -> NotificationManager.GearReminder {
            .init(identifier: "sensor_cleaning_x", title: "Sensor cleaning due", body: "Due.", due: due, hour: 10, minute: 0)
        }
        let whole = Date(timeIntervalSince1970: 1_710_000_000)
        #expect(reminder(due: whole.addingTimeInterval(0.7)).revision == reminder(due: whole).revision,
                "A backup stores the date without its fraction")
        #expect(reminder(due: whole.addingTimeInterval(1)).revision != reminder(due: whole).revision)
        #expect(reminder(due: whole).revision.hasPrefix("1710000000.0|"), "Whole-second dates keep the revision 1.0 stored")
    }

    @Test func aRestoreDoesNotFireADeliveredReminderAgain() async throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let body = GearItem(category: .cameraBody, make: "Nikon", model: "Z6 III")
        body.sensorCleaningIntervalDays = 30
        // Logged with `Date()`, so it has a fraction of a second; overdue for a year.
        body.lastSensorCleaningDate = Date(timeIntervalSince1970: (Date().timeIntervalSince1970 - 400 * 86_400).rounded(.down) + 0.7)
        context.insert(body)
        try context.save()

        let center = FakeCenter()
        let manager = center.make(defaults: enabledDefaults())
        await manager.refreshGearReminders(for: [body])
        #expect(center.pending.count == 1, "An overdue reminder is delivered once")
        center.pending.removeAll()   // iOS delivered it

        await manager.refreshGearReminders(for: [body])
        #expect(center.pending.isEmpty, "Not again on the next foreground")

        // A restore brings the date back without its fraction.
        let stored = try #require(body.lastSensorCleaningDate)
        body.lastSensorCleaningDate = Date(timeIntervalSince1970: stored.timeIntervalSince1970.rounded(.down))
        await manager.refreshGearReminders(for: [body])
        #expect(center.pending.isEmpty, "Nor after a restore")
    }
}

// MARK: - Timer and shoot alerts

@MainActor
struct TimerAlertFixTests {
    private typealias FakeCenter = NotificationManagerTests.FakeCenter

    @Test func aLongStepKeepsItsPourAndDoneAlerts() {
        // Forty minutes with five seconds every thirty: 79 agitations, more than iOS will hold.
        var session = DevelopmentSession(steps: [
            DevelopmentStepPlan(name: "Developer", duration: 2400, agitation: .everyThirtySeconds),
            DevelopmentStepPlan(name: "Fixer", duration: 300, agitation: .none)
        ])
        let now = Date(timeIntervalSince1970: 1_000)
        session.start(at: now)
        let alerts = ToolTimers.alerts(for: session, now: now)
        #expect(alerts.count > NotificationManager.maximumTimerAlerts)

        let scheduled = NotificationManager.timerAlertsToSchedule(alerts)
        #expect(scheduled.count == NotificationManager.maximumTimerAlerts)
        #expect(scheduled.map(\.title).suffix(2) == ["Developer: pour out", "Developer done"])
        #expect(scheduled.last?.date == now.addingTimeInterval(2400))
        #expect(scheduled.map(\.date) == scheduled.map(\.date).sorted())
        // The rest are the soonest agitations, with none skipped.
        let agitations = alerts.filter { !$0.isRequired }.sorted { $0.date < $1.date }
        #expect(Array(scheduled.prefix(38)) == Array(agitations.prefix(38)))
    }

    @Test func alertsThatFitAreAllKeptInOrder() {
        let now = Date(timeIntervalSince1970: 1_000)
        let alerts = [
            NotificationManager.TimerAlert(date: now.addingTimeInterval(60), title: "Done", body: "", isRequired: true),
            NotificationManager.TimerAlert(date: now.addingTimeInterval(30), title: "Agitate", body: "")
        ]
        #expect(NotificationManager.timerAlertsToSchedule(alerts).map(\.title) == ["Agitate", "Done"])
        #expect(NotificationManager.timerAlertsToSchedule(alerts, limit: 1).map(\.title) == ["Done"])
    }

    @Test func comingBackToTheAppTopsUpARunningStepsAlerts() async {
        let center = FakeCenter()
        let manager = center.make(defaults: TestSupport.makeDefaults())
        await manager.refreshAuthorizationStatus()
        let timers = ToolTimers(notifications: manager)
        timers.beginDevelopment(recipeName: "HP5", recipeID: nil, steps: [
            DevelopmentStepPlan(name: "Developer", duration: 600, agitation: .everyMinute)
        ])
        timers.refreshDevelopmentAlerts()
        await manager.waitForPendingWork()
        #expect(center.pending.isEmpty, "Nothing to top up before the step starts")

        timers.startStep()
        await manager.waitForPendingWork()
        let whole = center.pending.count
        center.pending.removeFirst(3)   // delivered while the phone was in a pocket
        timers.refreshDevelopmentAlerts()
        await manager.waitForPendingWork()
        #expect(center.pending.count == whole)

        timers.pauseStep()
        timers.refreshDevelopmentAlerts()
        await manager.waitForPendingWork()
        #expect(center.pending.isEmpty, "A paused step stays quiet")
    }

    @Test func aGoldenHourHeadsUpIsAMomentNotAClockTime() async throws {
        let center = FakeCenter()
        let manager = center.make(defaults: TestSupport.makeDefaults())
        let alert = ShootAlert(identifier: "shoot_a_0", date: Date().addingTimeInterval(3600), title: "Golden hour", body: "Soon")
        await manager.replaceShootAlerts([alert])
        // A calendar trigger would follow the wall clock into another time zone.
        let trigger = try #require(center.pending.first?.trigger as? UNTimeIntervalNotificationTrigger)
        #expect(abs(trigger.timeInterval - 3600) < 5)
        #expect(!trigger.repeats)
    }
}

// MARK: - Shoots

struct ShootPlaceFixTests {
    private let newYork = TimeZone(identifier: "America/New_York")!
    private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!

    private func clock(_ date: Date, in zone: TimeZone) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    @Test func choosingAPlaceKeepsTheTimesOnTheClock() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = newYork
        // 7 PM on 21 June, typed on a phone in New York before the place was chosen.
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 19)))
        var draft = ShootDraft(now: start)
        draft.startDate = start
        draft.endDate = start.addingTimeInterval(2 * 3600)

        let beach = PlaceValue(name: "Venice Beach", coordinate: GeoCoordinate(latitude: 33.985, longitude: -118.4695),
                               timeZoneIdentifier: "America/Los_Angeles")
        draft.setPlace(beach, deviceTimeZone: newYork)
        #expect(draft.place == beach)
        #expect(clock(draft.startDate, in: losAngeles) == clock(start, in: newYork), "Still 7 PM, now at the beach")
        #expect(draft.startDate == start.addingTimeInterval(3 * 3600))
        #expect(draft.endDate.timeIntervalSince(draft.startDate) == 2 * 3600)

        // Taking the place away puts the times back on the phone's clock.
        draft.setPlace(nil, deviceTimeZone: newYork)
        #expect(draft.startDate == start)
    }

    @Test func aPlaceInTheSameZoneMovesNothing() {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        var draft = ShootDraft(now: start)
        let before = draft
        draft.setPlace(PlaceValue(name: "Santa Monica", coordinate: GeoCoordinate(latitude: 34.01, longitude: -118.5),
                                  timeZoneIdentifier: "America/Los_Angeles"), deviceTimeZone: losAngeles)
        #expect(draft.startDate == before.startDate)
        #expect(draft.endDate == before.endDate)
        // A saved place losing its link (it was deleted from My Places) isn't a move either.
        var unlinked = draft.place
        unlinked?.savedPlaceID = nil
        draft.setPlace(unlinked, deviceTimeZone: newYork)
        #expect(draft.startDate == before.startDate)
    }
}

// MARK: - Exports, backups and imports

@MainActor
struct ExportSizeFixTests {
    /// A body with one large photo: about 270 KB as base64, and a few KB of everything else.
    private func bodyWithALargePhoto(in context: ModelContext) -> GearItem {
        let body = TestSupport.insertSampleBody(into: context)
        body.appendGalleryPhoto(Data(repeating: 7, count: 200_000), in: context)
        return body
    }

    @Test func anExportTooLargeToReadBackIsRefused() async throws {
        let container = try TestSupport.makeContainer()
        let body = bodyWithALargePhoto(in: container.mainContext)
        try container.mainContext.save()
        let library = LibraryContents(gearItems: [body], developmentRecipes: [])
        let service = DataExportService(settingsStore: TestSupport.makeDefaults(), maximumBytes: 100_000)

        await #expect(throws: ExportError.self) {
            _ = try await service.exportData(configuration: .init(format: .json), library: library)
        }
        // Without photos it fits, and the same file is what a backup falls back to.
        var withoutPhotos = DataExportService.ExportConfiguration(format: .json)
        withoutPhotos.includePhotos = false
        let url = try await service.exportData(configuration: withoutPhotos, library: library)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try Data(contentsOf: url).count < 100_000)
        #expect(!service.lastExportDroppedPhotos)

        let message = ExportError.tooLarge(megabytes: 300, limitMegabytes: 256, includesPhotos: true).localizedDescription
        #expect(message.contains("300 MB") && message.contains("256 MB") && message.contains("Photos"))
    }

    @Test func aBackupThatCantHoldThePhotosKeepsEverythingElse() async throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let body = bodyWithALargePhoto(in: context)
        try context.save()

        let manager = BackupManager(directory: directory, defaults: TestSupport.makeDefaults(), maximumBackupBytes: 100_000)
        #expect(manager.configuration.includePhotos)
        try await manager.createBackup(library: LibraryContents(gearItems: [body], developmentRecipes: []))
        let backup = try #require(manager.availableBackups.first)
        #expect(backup.includesPhotos == false, "Listed as what it is")
        #expect(manager.lastBackupLeftPhotosOut)
        #expect(manager.lastBackupError == nil)
        #expect(backup.itemCounts.gearItems == 1)

        // A library that fits is backed up whole, and the note goes away.
        let lens = TestSupport.insertSampleLens(into: context)
        try context.save()
        try await manager.createBackup(library: LibraryContents(gearItems: [lens], developmentRecipes: []))
        #expect(!manager.lastBackupLeftPhotosOut)
        #expect(manager.availableBackups.contains { $0.includesPhotos == true })
    }

    @Test func removingPhotosMatchesAnExportMadeWithoutThem() throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let body = bodyWithALargePhoto(in: context)
        try context.save()
        let record = try #require(body.maintenanceRecords?.first)
        record.photoData = Data([1, 2, 3])
        try context.save()
        let service = DataExportService(settingsStore: TestSupport.makeDefaults())
        let library = LibraryContents(gearItems: [body], developmentRecipes: [])
        let full = service.buildExportData(configuration: .init(format: .json), library: library)
        #expect(full.includesPhotos)
        #expect(full.gearItems[0].photos?.count == 1)
        #expect(full.maintenanceRecords[0].photoData != nil)

        let stripped = full.removingPhotos()
        #expect(!stripped.includesPhotos)
        #expect(stripped.gearItems[0].photos == nil)
        #expect(stripped.maintenanceRecords[0].photoData == nil)
        #expect(stripped.recordCount == full.recordCount - 1)
        #expect(stripped.loans.count == full.loans.count)
    }

    @Test func aFileThatListsARecordTwiceImportsItOnce() async throws {
        let source = try TestSupport.makeContainer()
        let body = TestSupport.insertSampleBody(into: source.mainContext)
        let recipe = TestSupport.insertSampleRecipe(into: source.mainContext)
        try source.mainContext.save()
        let service = DataExportService(settingsStore: TestSupport.makeDefaults())
        var document = service.buildExportData(configuration: .init(format: .json),
                                               library: LibraryContents(gearItems: [body], developmentRecipes: [recipe]))
        // As an export of a library that already had duplicates would be.
        document.gearItems += document.gearItems
        document.loans += document.loans
        document.shutterCountReadings += document.shutterCountReadings
        document.maintenanceRecords += document.maintenanceRecords
        document.maintenanceReminders += document.maintenanceReminders
        document.developmentRecipes = (document.developmentRecipes ?? []) + (document.developmentRecipes ?? [])

        let destination = try TestSupport.makeContainer()
        let context = destination.mainContext
        try await DataImportService(settingsStore: TestSupport.makeDefaults()).apply(document, to: context, strategy: .replace)
        #expect(try context.fetchCount(FetchDescriptor<GearItem>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<GearLoan>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<ShutterCountReading>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<MaintenanceRecord>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<MaintenanceReminder>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<DevelopmentRecipe>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<DevelopmentStep>()) == 3)
    }
}

// MARK: - Typed numbers

struct NumberInputFixTests {
    private let german = Locale(identifier: "de_DE")
    private let american = Locale(identifier: "en_US")

    @Test func aPointIsADecimalInACoordinateEverywhere() {
        // Pasted from a map link, in a region that writes decimals with a comma.
        #expect(PlaceValue.degrees(from: "48.137154", locale: german) == 48.137154)
        #expect(PlaceValue.degrees(from: "0.125", locale: german) == 0.125, "Not one hundred and twenty-five")
        #expect(PlaceValue.degrees(from: "-0.0005", locale: german) == -0.0005)
        #expect(PlaceValue.degrees(from: " 11.576124 ", locale: german) == 11.576124)
        #expect(PlaceValue.degrees(from: "48.137154", locale: american) == 48.137154)
    }

    @Test func aCommaIsReadByTheRegionsRules() {
        #expect(PlaceValue.degrees(from: "48,137154", locale: german) == 48.137154)
        #expect(PlaceValue.degrees(from: "\u{2212}109,8679", locale: german) == -109.8679)
        #expect(PlaceValue.degrees(from: "48,137154", locale: american) == nil, "A comma isn't a decimal there")
        #expect(PlaceValue.degrees(from: "north", locale: american) == nil)
        #expect(PlaceValue.degrees(from: "", locale: american) == nil)
        #expect(PlaceValue.degrees(from: "1.2.3", locale: american) == nil)
    }

    @Test func aCoordinateFieldReadsBackWhatItShows() throws {
        for locale in [german, american, Locale(identifier: "fr_FR"), Locale(identifier: "sv_SE")] {
            for degrees in [38.3895, -109.8679, 0.00012, -0.5] {
                let text = PlaceValue.fieldText(degrees: degrees, locale: locale)
                let read = try #require(PlaceValue.degrees(from: text, locale: locale), "\(text) in \(locale.identifier)")
                #expect(abs(read - degrees) < 0.000_005, "\(text) in \(locale.identifier)")
            }
        }
        #expect(PlaceValue.fieldText(degrees: 48.137154, locale: german) == "48,13715")
    }

    @Test func aDistanceFieldShowsARoundNumber() {
        let feet = MeasurementUnits(metric: false)
        // The depth-of-field tool's default five metres, on a phone set to feet.
        #expect(feet.fieldDistance(millimetres: 5000) == 16.404)
        #expect(MeasurementInput.text(feet.fieldDistance(millimetres: 5000), locale: american) == "16.404")
        // Seven feet typed in used to come back as 6.999999999999999.
        #expect(feet.fieldDistance(millimetres: feet.millimetres(fromDisplay: 7)) == 7)
        for typed in [7.0, 14, 28, 31, 56, 3.5, 0.75] {
            #expect(feet.fieldDistance(millimetres: feet.millimetres(fromDisplay: typed)) == typed)
        }
        #expect(MeasurementUnits(metric: true).fieldDistance(millimetres: 1234) == 1.234)
    }
}

// MARK: - Navigation

@MainActor
struct LibraryReplacedFixTests {
    @Test func replacingTheLibrarySendsTheTabsBackToTheirFirstScreens() {
        let navigation = AppNavigation()
        navigation.open(.ndFilter)
        navigation.openedLabel = .kit(UUID())
        #expect(!navigation.toolsPath.isEmpty)
        let before = navigation.libraryGeneration

        navigation.libraryWasReplaced()
        #expect(navigation.libraryGeneration == before + 1, "The tabs are rebuilt for the new value")
        #expect(navigation.toolsPath.isEmpty)
        #expect(navigation.openedLabel == nil)
        #expect(navigation.tab == .tools, "The selected tab stays where the user left it")
    }
}
